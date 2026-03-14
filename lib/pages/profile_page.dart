import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/subscription_model.dart';
import '../models/user_model.dart';
import '../services/subscription_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../widgets/donation_badge.dart';
import 'donations_page.dart';
import 'pro_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserService _userService = UserService();
  final SubscriptionService _subService = SubscriptionService();
  final User? _firebaseUser = FirebaseAuth.instance.currentUser;
  final _nicknameController = TextEditingController();

  bool _isSavingNickname = false;
  bool _isUploadingPhoto = false;
  String? _currentPhotoUrl;
  UserModel? _userModel;

  @override
  void initState() {
    super.initState();
    _currentPhotoUrl = _firebaseUser?.photoURL;
    _nicknameController.text = _firebaseUser?.displayName ?? '';
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = await _subService.getCurrentUserModel();
    if (!mounted) return;
    setState(() {
      _userModel = user;
      if (_nicknameController.text.isEmpty && user?.displayName != null) {
        _nicknameController.text = user!.displayName!;
      }
      _currentPhotoUrl ??= user?.photoUrl;
    });
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
      await _firebaseUser?.updateDisplayName(nickname);
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
    final permission = await Permission.photos.request();
    if (permission.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permesso galleria negato. Abilitalo nelle impostazioni.'),
          action: SnackBarAction(label: 'Impostazioni', onPressed: openAppSettings),
        ),
      );
      return;
    }
    if (!permission.isGranted) return;

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
      final Uint8List compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 300,
        minHeight: 300,
        quality: 85,
        format: CompressFormat.jpeg,
      );

      final uid = _firebaseUser?.uid;
      if (uid == null) return;

      final ref = FirebaseStorage.instance.ref('users/$uid/avatar.jpg');
      final uploadTask = await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await _firebaseUser?.updatePhotoURL(downloadUrl);
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
    final tier = _userModel?.donationTier ?? DonationTier.none;
    final hasPro = _userModel?.hasProAccess ?? false;
    final radius = 56.0;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Profilo'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.gold.withValues(alpha: 0.2)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          // ── Avatar con bordo tier e badge Pro ──────────────────────────
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Avatar con bordo donazione
                DonationAvatarBorder(
                  tier: tier,
                  radius: radius,
                  child: CircleAvatar(
                    radius: radius,
                    backgroundImage: _currentPhotoUrl != null
                        ? NetworkImage(_currentPhotoUrl!)
                        : null,
                    backgroundColor: AppColors.bgLight,
                    child: _currentPhotoUrl == null
                        ? Icon(Icons.person, size: radius, color: AppColors.textSecondary)
                        : null,
                  ),
                ),
                // Pulsante fotocamera
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
                // Badge Pro in alto a destra
                if (hasPro)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.bgDark, width: 1.5),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
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

          // Badge donazione
          if (tier != DonationTier.none) ...[
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DonationsPage()),
                ),
                child: DonationBadge(tier: tier, size: 20, showLabel: true),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── Piano Pro ────────────────────────────────────────────────────
          _buildProBanner(hasPro),
          const SizedBox(height: 28),

          // ── Nickname ─────────────────────────────────────────────────────
          const Text(
            'Nickname',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nicknameController,
            maxLength: 30,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Il tuo nome visualizzato',
              hintStyle: TextStyle(color: AppColors.textHint),
              prefixIcon: Icon(Icons.person_outline, color: AppColors.textSecondary),
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
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

  Widget _buildProBanner(bool hasPro) {
    if (hasPro) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.workspace_premium, color: AppColors.gold, size: 22),
            SizedBox(width: 10),
            Text(
              'Piano Pro attivo',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: AppColors.gold, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Scopri Deck Master Pro',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}
