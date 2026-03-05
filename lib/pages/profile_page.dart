import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserService _userService = UserService();
  final User? _firebaseUser = FirebaseAuth.instance.currentUser;
  final _nicknameController = TextEditingController();

  bool _isSavingNickname = false;
  bool _isUploadingPhoto = false;
  String? _currentPhotoUrl;

  @override
  void initState() {
    super.initState();
    _currentPhotoUrl = _firebaseUser?.photoURL;
    _nicknameController.text = _firebaseUser?.displayName ?? '';
    _loadProfileFromFirestore();
  }

  Future<void> _loadProfileFromFirestore() async {
    final user = await _userService.getCurrentUser();
    if (!mounted) return;
    if (user != null) {
      setState(() {
        if (_nicknameController.text.isEmpty && user.displayName != null) {
          _nicknameController.text = user.displayName!;
        }
        _currentPhotoUrl ??= user.photoUrl;
      });
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il nickname non può essere vuoto')),
      );
      return;
    }

    setState(() => _isSavingNickname = true);
    try {
      // Update Firebase Auth display name
      await _firebaseUser?.updateDisplayName(nickname);

      // Update Firestore user document
      final uid = _firebaseUser?.uid;
      if (uid != null) {
        await _userService.updateUserProfile(uid: uid, displayName: nickname);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nickname aggiornato!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingNickname = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();

      // Compress
      final Uint8List compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 300,
        minHeight: 9999,
        quality: 85,
        format: CompressFormat.jpeg,
      );

      // Upload to Firebase Storage
      final uid = _firebaseUser?.uid;
      if (uid == null) return;

      final ref = FirebaseStorage.instance.ref('users/$uid/avatar.jpg');
      final uploadTask = await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Update Firebase Auth photo
      await _firebaseUser?.updatePhotoURL(downloadUrl);

      // Update Firestore
      await _userService.updateUserProfile(uid: uid, photoUrl: downloadUrl);

      if (mounted) {
        setState(() => _currentPhotoUrl = downloadUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profilo aggiornata!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore upload: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          // Avatar
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundImage: _currentPhotoUrl != null
                      ? NetworkImage(_currentPhotoUrl!)
                      : null,
                  backgroundColor: AppColors.bgLight,
                  child: _currentPhotoUrl == null
                      ? const Icon(Icons.person, size: 56, color: AppColors.textSecondary)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bgDark, width: 2),
                      ),
                      child: _isUploadingPhoto
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.camera_alt, size: 18, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _firebaseUser?.email ?? '',
              style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ),
          const SizedBox(height: 40),

          // Nickname
          const Text(
            'Nickname',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nicknameController,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: 'Il tuo nome visualizzato',
              prefixIcon: Icon(Icons.person_outline),
              counterText: '',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveNickname(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: _isSavingNickname
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.save_outlined, color: Colors.black),
              label: const Text('Salva Nickname', style: TextStyle(color: Colors.black)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              onPressed: _isSavingNickname ? null : _saveNickname,
            ),
          ),
        ],
      ),
    );
  }
}
