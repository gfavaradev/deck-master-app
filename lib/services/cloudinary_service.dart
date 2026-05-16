import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Handles signed image uploads to Cloudinary.
class CloudinaryService {
  static const String _cloudName = AppSecrets.cloudinaryCloudName;
  static const String _apiKey = AppSecrets.cloudinaryApiKey;
  static const String _apiSecret = AppSecrets.cloudinaryApiSecret;

  /// Returns the Cloudinary folder path for a given catalog.
  /// e.g. 'collections/yugioh', 'collections/pokemon', 'collections/onepiece'
  static String buildFolder(String catalog) => 'collections/$catalog';

  /// Returns just the filename portion of the public_id (no folder).
  static String buildFilename(dynamic cardId, {String? setCode}) {
    final safeId = cardId.toString().replaceAll(RegExp(r'[/\s]'), '_');
    if (setCode != null && setCode.isNotEmpty) {
      final safeCode = setCode.replaceAll(RegExp(r'[/\s]'), '_');
      return '${safeId}_$safeCode';
    }
    return safeId;
  }

  /// Builds an optimized delivery URL for a given public_id.
  /// f_auto → serves WebP/AVIF based on browser/OS support.
  /// q_auto → Cloudinary picks the best quality/size trade-off automatically.
  static String buildUrl(String publicId) {
    return 'https://res.cloudinary.com/$_cloudName/image/upload/f_auto,q_auto/$publicId';
  }

  static String _sign(Map<String, String> params) {
    final sorted = params.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final toSign = sorted.map((e) => '${e.key}=${e.value}').join('&') + _apiSecret;
    return sha1.convert(utf8.encode(toSign)).toString();
  }

  /// Verifies that a Cloudinary URL is accessible (HTTP 200).
  /// Returns true if the image exists, false otherwise.
  static Future<bool> verifyUrl(String url) async {
    try {
      final request = http.Request('HEAD', Uri.parse(url));
      final streamed = await request.send().timeout(const Duration(seconds: 10));
      return streamed.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Uploads raw bytes to Cloudinary and returns the secure_url.
  /// Uses explicit [folder] + [public_id] parameters so Cloudinary creates
  /// the proper folder hierarchy in the dashboard (not just root/home).
  /// Returns null if the upload fails.
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    final folder = buildFolder(catalog);
    final filename = buildFilename(cardId, setCode: setCode);
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // folder must be included in the signature alongside public_id and timestamp.
    final params = {
      'folder': folder,
      'public_id': filename,
      'timestamp': timestamp,
    };
    final signature = _sign(params);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload'),
    );
    request.fields.addAll({
      ...params,
      'api_key': _apiKey,
      'signature': signature,
    });
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'image.jpg'),
    );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      debugPrint('[Cloudinary] Upload failed ${streamed.statusCode}: $body');
      return null;
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    // Cloudinary stores the full public_id as 'folder/filename' (e.g. 'catalog/yugioh/images/12345').
    // Use optimized delivery URL (f_auto, q_auto).
    final uploadedPublicId = json['public_id'] as String?;
    if (uploadedPublicId == null) return null;
    return buildUrl(uploadedPublicId);
  }
}
