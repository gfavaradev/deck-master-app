import 'package:file_picker/file_picker.dart';
import 'backblaze_service.dart';
import 'user_service.dart';

/// Handles uploading card/set images to Backblaze B2.
/// Works both for images picked from the device and for images fetched from an API URL.
/// Always returns a Backblaze public URL.
/// All operations require the current user to be an administrator.
class ImageUploadService {
  static final _userService = UserService();

  /// Lets the user pick an image from the device, uploads it to Backblaze B2
  /// and returns the public URL, or null if cancelled.
  /// Throws [PermissionDeniedException] if the current user is not an admin.
  static Future<String?> pickAndUpload({
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    await _assertAdmin();
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) return null;
    return BackblazeService.uploadBytes(
      bytes: bytes,
      catalog: catalog,
      cardId: cardId,
      setCode: setCode,
    );
  }

  /// Downloads an image from [imageUrl] and uploads it to Backblaze B2.
  /// Returns the public URL, or null on failure.
  /// Throws [PermissionDeniedException] if the current user is not an admin.
  static Future<String?> uploadFromUrl({
    required String imageUrl,
    required String catalog,
    required dynamic cardId,
    String? setCode,
  }) async {
    await _assertAdmin();
    return BackblazeService.uploadFromRemoteUrl(
      imageUrl: imageUrl,
      catalog: catalog,
      cardId: cardId,
      setCode: setCode,
    );
  }

  static Future<void> _assertAdmin() async {
    final isAdmin = await _userService.isCurrentUserAdmin();
    if (!isAdmin) throw PermissionDeniedException();
  }
}

class PermissionDeniedException implements Exception {
  @override
  String toString() => 'Operazione riservata agli amministratori';
}
