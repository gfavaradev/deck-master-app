import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Handles signed image uploads to Cloudinary.
class CloudinaryService {
  static const String _cloudName = AppSecrets.cloudinaryCloudName;
  static const String _apiKey = AppSecrets.cloudinaryApiKey;
  static const String _apiSecret = AppSecrets.cloudinaryApiSecret;

  /// Builds a deterministic Cloudinary public_id that mirrors the old Firebase path.
  static String buildPublicId(String catalog, dynamic cardId, {String? setCode}) {
    final safeId = cardId.toString().replaceAll(RegExp(r'[/\s]'), '_');
    if (setCode != null && setCode.isNotEmpty) {
      final safeCode = setCode.replaceAll(RegExp(r'[/\s]'), '_');
      return 'catalog/$catalog/images/${safeId}_$safeCode';
    }
    return 'catalog/$catalog/images/$safeId';
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

  /// Uploads raw bytes to Cloudinary and returns the secure_url.
  /// Returns null if the upload fails.
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    final publicId = buildPublicId(catalog, cardId, setCode: setCode);
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final params = {'public_id': publicId, 'timestamp': timestamp};
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
    if (streamed.statusCode != 200) return null;
    final json = jsonDecode(body) as Map<String, dynamic>;
    // Use optimized delivery URL (f_auto,q_auto) instead of the raw secure_url.
    // Cloudinary selects the best format (WebP/AVIF) and quality automatically.
    final uploadedPublicId = json['public_id'] as String?;
    if (uploadedPublicId == null) return null;
    return buildUrl(uploadedPublicId);
  }
}
