import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Backblaze B2 image storage — drop-in replacement for CloudinaryService.
///
/// Flow:
///   1. b2_authorize_account  → authToken + apiUrl + downloadUrl  (cached 24h)
///   2. b2_get_upload_url      → uploadUrl + uploadAuthToken       (reused until error)
///   3. b2_upload_file         → upload bytes with SHA1 header
///
/// Public URL:  {downloadUrl}/file/{bucketName}/{path}
class BackblazeService {
  static const _authorizeUrl =
      'https://api.backblazeb2.com/b2api/v3/b2_authorize_account';

  // ── Cached session state ───────────────────────────────────────────────────
  static String? _authToken;
  static String? _apiUrl;
  static String? _downloadUrl;
  static DateTime? _authExpiry;

  static String? _uploadUrl;
  static String? _uploadAuthToken;

  // ── Public helpers ─────────────────────────────────────────────────────────

  /// Builds the path in the bucket for a card image.
  /// e.g.  catalog='yugioh', cardId=12345  →  'collections/yugioh/12345.jpg'
  static String buildPath(String catalog, dynamic cardId, {String? setCode}) {
    final safeId = cardId.toString().replaceAll(RegExp(r'[/\s]'), '_');
    final name = setCode != null && setCode.isNotEmpty
        ? '${safeId}_${setCode.replaceAll(RegExp(r'[/\s]'), '_')}'
        : safeId;
    return 'collections/$catalog/$name.jpg';
  }

  /// Returns the public download URL for a stored path.
  /// Uses AppSecrets.backblazeDownloadUrl if set, otherwise falls back to
  /// the URL returned by b2_authorize_account (populated after first auth).
  static String publicUrl(String path) {
    final base = AppSecrets.backblazeDownloadUrl.isNotEmpty
        ? AppSecrets.backblazeDownloadUrl
        : (_downloadUrl ?? 'https://f000.backblazeb2.com');
    return '$base/file/${AppSecrets.backblazeBucketName}/$path';
  }

  /// Whether [url] points to this Backblaze bucket.
  static bool isBackblazeUrl(String url) =>
      url.contains('backblazeb2.com') &&
      url.contains(AppSecrets.backblazeBucketName);

  // ── Upload API ─────────────────────────────────────────────────────────────

  /// Uploads raw bytes and returns the public URL, or null on failure.
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    final path = buildPath(catalog, cardId, setCode: setCode);
    return _upload(bytes: bytes, path: path);
  }

  /// Downloads [imageUrl] and uploads to B2. Returns the public URL or null.
  static Future<String?> uploadFromRemoteUrl({
    required String imageUrl,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(imageUrl), headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; DeckMasterBot/1.0)',
          })
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      return uploadBytes(
        bytes: response.bodyBytes,
        catalog: catalog,
        cardId: cardId,
        setCode: setCode,
      );
    } catch (e) {
      debugPrint('[Backblaze] Remote URL fetch failed: $e');
      return null;
    }
  }

  /// Verifies a URL is accessible (HEAD request).
  static Future<bool> verifyUrl(String url) async {
    try {
      final req = http.Request('HEAD', Uri.parse(url));
      final res = await req.send().timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Internal upload flow ───────────────────────────────────────────────────

  static Future<String?> _upload({
    required Uint8List bytes,
    required String path,
  }) async {
    // Retry once on auth / upload-URL expiry
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await _ensureAuthorized();
        await _ensureUploadUrl();

        final sha1Hex = sha1.convert(bytes).toString();
        final encodedPath = Uri.encodeComponent(path);

        final response = await http
            .post(
              Uri.parse(_uploadUrl!),
              headers: {
                'Authorization': _uploadAuthToken!,
                'X-Bz-File-Name': encodedPath,
                'Content-Type': 'image/jpeg',
                'Content-Length': '${bytes.length}',
                'X-Bz-Content-Sha1': sha1Hex,
              },
              body: bytes,
            )
            .timeout(const Duration(minutes: 2));

        if (response.statusCode == 200) {
          return publicUrl(path);
        }

        // 401 or 503 → reset upload URL and retry
        if (response.statusCode == 401 || response.statusCode == 503) {
          _uploadUrl = null;
          _uploadAuthToken = null;
          if (response.statusCode == 401) {
            _authToken = null; // force full re-auth
          }
          continue;
        }

        debugPrint('[Backblaze] Upload failed ${response.statusCode}: ${response.body}');
        return null;
      } catch (e) {
        debugPrint('[Backblaze] Upload error (attempt ${attempt + 1}): $e');
        _uploadUrl = null;
        _uploadAuthToken = null;
      }
    }
    return null;
  }

  // ── Auth & upload-URL management ───────────────────────────────────────────

  static Future<void> _ensureAuthorized() async {
    final now = DateTime.now();
    if (_authToken != null &&
        _authExpiry != null &&
        now.isBefore(_authExpiry!)) {
      return; // still valid
    }

    final credentials = base64Encode(
      utf8.encode('${AppSecrets.backblazeKeyId}:${AppSecrets.backblazeAppKey}'),
    );
    final response = await http
        .get(
          Uri.parse(_authorizeUrl),
          headers: {'Authorization': 'Basic $credentials'},
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        '[Backblaze] Autorizzazione fallita (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _authToken = json['authorizationToken'] as String?;
    _apiUrl = json['apiInfo']?['storageApi']?['apiUrl'] as String? ??
        json['apiUrl'] as String?;
    _downloadUrl = json['apiInfo']?['storageApi']?['downloadUrl'] as String? ??
        json['downloadUrl'] as String?;

    if (_authToken == null || _apiUrl == null || _downloadUrl == null) {
      throw Exception('[Backblaze] Risposta autorizzazione non valida: ${response.body}');
    }

    // Auth tokens are valid for 24h; expire after 23h to be safe
    _authExpiry = now.add(const Duration(hours: 23));
    _uploadUrl = null; // upload URL must be re-fetched after new auth
    _uploadAuthToken = null;
  }

  static Future<void> _ensureUploadUrl() async {
    if (_uploadUrl != null && _uploadAuthToken != null) return;

    final response = await http
        .post(
          Uri.parse('$_apiUrl/b2api/v3/b2_get_upload_url'),
          headers: {
            'Authorization': _authToken!,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'bucketId': AppSecrets.backblazeBucketId}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        '[Backblaze] Impossibile ottenere upload URL (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _uploadUrl = json['uploadUrl'] as String?;
    _uploadAuthToken = json['authorizationToken'] as String?;

    if (_uploadUrl == null || _uploadAuthToken == null) {
      throw Exception('[Backblaze] Upload URL response non valida');
    }
  }
}
