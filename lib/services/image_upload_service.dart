import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'user_service.dart';

/// Handles uploading card/set images to Firebase Storage.
/// Works both for images picked from the device and for images fetched from an API URL.
/// Always returns a Firebase Storage download URL for consistency.
/// All operations require the current user to be an administrator.
class ImageUploadService {
  static final _userService = UserService();

  /// Lets the user pick an image from the device, uploads it to Firebase Storage
  /// and returns the download URL, or null if cancelled.
  /// Throws [PermissionDeniedException] if the current user is not an admin.
  static Future<String?> pickAndUpload({
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    await _assertAdmin();

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) return null;

    return _uploadBytes(
      bytes: bytes,
      catalog: catalog,
      cardId: cardId,
      setCode: setCode,
    );
  }

  /// Downloads an image from [imageUrl] and uploads it to Firebase Storage.
  /// Returns the Firebase download URL, or null on failure.
  /// Throws [PermissionDeniedException] if the current user is not an admin.
  static Future<String?> uploadFromUrl({
    required String imageUrl,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    await _assertAdmin();

    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) return null;

    return _uploadBytes(
      bytes: response.bodyBytes,
      catalog: catalog,
      cardId: cardId,
      setCode: setCode,
    );
  }

  static Future<void> _assertAdmin() async {
    final isAdmin = await _userService.isCurrentUserAdmin();
    if (!isAdmin) throw PermissionDeniedException();
  }

  static Future<String?> _uploadBytes({
    required Uint8List bytes,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    final safeId = cardId.toString().replaceAll(RegExp(r'[/\s]'), '_');
    final safeCode = setCode?.replaceAll(RegExp(r'[/\s]'), '_') ?? '';
    final path = safeCode.isNotEmpty
        ? 'catalog/$catalog/images/${safeId}_$safeCode.jpg'
        : 'catalog/$catalog/images/$safeId.jpg';

    // flutter_image_compress non supporta Windows/Linux/Web — usa i bytes originali
    final toUpload = (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)
        ? bytes
        : await FlutterImageCompress.compressWithList(
            bytes,
            minWidth: 400,
            minHeight: 9999,
            quality: 78,
            format: CompressFormat.jpeg,
          );

    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(toUpload, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }
}

class PermissionDeniedException implements Exception {
  @override
  String toString() => 'Operazione riservata agli amministratori';
}
