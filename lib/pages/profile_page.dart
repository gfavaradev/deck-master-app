import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/subscription_model.dart';
import '../models/user_model.dart';
import '../services/subscription_service.dart';
import '../services/user_service.dart';
import '../services/data_repository.dart';
import '../services/xp_service.dart';
import '../theme/app_colors.dart';
import '../widgets/donation_badge.dart';

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
  String? _currentPhotoUrl;
  UserModel? _userModel;

  int _xp = 0;
  String? _selectedAvatarId;
  Map<String, double> _collectionCompletions = {};

  @override
  void initState() {
    super.initState();
    _currentPhotoUrl = _firebaseUser?.photoURL;
    _nicknameController.text = _firebaseUser?.displayName ?? '';
    _loadProfile();
    _loadXp();
  }

  Future<void> _loadXp() async {
    final results = await Future.wait([
      XpService().getCurrentXp(),
      XpService().getSelectedAvatarId(),
      DataRepository().getCollectionCompletions(),
    ]);
    if (mounted) {
      setState(() {
        _xp = results[0] as int;
        _selectedAvatarId = results[1] as String?;
        _collectionCompletions = results[2] as Map<String, double>;
      });
    }
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

  Future<void> _selectAvatar(String id) async {
    await XpService().setSelectedAvatarId(id);
    if (mounted) setState(() => _selectedAvatarId = id);
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
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingNickname = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final tier = _userModel?.donationTier ?? DonationTier.none;
    final hasPro = _userModel?.hasProAccess ?? false;
    const radius = 56.0;

    final level = XpService.levelFromXp(_xp);
    final progress = XpService.levelProgress(_xp);
    final xpToNext = XpService.xpToNextLevel(_xp);
    final maxLevel = level >= XpService.levelThresholds.length;

    // Avatar da mostrare: selezionato, oppure foto Google/custom
    AvatarDef? selectedAvatarDef;
    if (_selectedAvatarId != null) {
      try {
        selectedAvatarDef = XpService.avatars.firstWhere((a) => a.id == _selectedAvatarId);
      } catch (_) {}
    }

    Widget avatarCircle = selectedAvatarDef != null
        ? selectedAvatarDef.buildCircle(radius)
        : CircleAvatar(
            radius: radius,
            backgroundImage: _currentPhotoUrl != null ? NetworkImage(_currentPhotoUrl!) : null,
            backgroundColor: AppColors.bgLight,
            child: _currentPhotoUrl == null
                ? Icon(Icons.person, size: radius, color: AppColors.textSecondary)
                : null,
          );

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
          // ── Avatar con bordo tier e badge livello ──────────────────────────
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DonationAvatarBorder(
                  tier: tier,
                  radius: radius,
                  child: avatarCircle,
                ),
                // Badge livello in alto a sinistra
                Positioned(
                  top: -4,
                  left: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bgMedium,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.gold, width: 1.5),
                    ),
                    child: Text(
                      'Lv.$level',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                // Badge PRO in alto a destra
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

          if (tier != DonationTier.none) ...[
            const SizedBox(height: 10),
            Center(child: DonationBadge(tier: tier, size: 20, showLabel: true)),
          ],

          const SizedBox(height: 24),

          // ── Barra XP ──────────────────────────────────────────────────────
          _buildXpBar(level, progress, xpToNext, maxLevel),

          const SizedBox(height: 28),

          // ── Selettore Avatar ──────────────────────────────────────────────
          _buildAvatarPicker(level, _collectionCompletions),

          const SizedBox(height: 28),

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

  Widget _buildXpBar(int level, double progress, int xpToNext, bool maxLevel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Livello $level',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                maxLevel ? 'Livello MAX' : '${XpService.levelThresholds[level - 1]} / ${XpService.levelThresholds[level]} XP',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.bgLight,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            maxLevel ? 'Hai raggiunto il livello massimo!' : '$_xp XP totali · ancora $xpToNext XP al prossimo livello',
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPicker(int level, Map<String, double> completions) {
    // Global avatars
    final globalAvatars = XpService.avatars
        .where((a) => a.unlockType == AvatarUnlockType.level)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Avatar',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sblocca avatar collezionando carte. Ogni collezione ha i suoi avatar esclusivi.',
          style: TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
        const SizedBox(height: 16),

        // ── Avatar Globali ──────────────────────────────────────────────
        _buildAvatarSectionHeader('Avatar Globali', null, level / XpService.levelThresholds.length),
        const SizedBox(height: 8),
        _buildAvatarGrid(globalAvatars, level, completions),

        const SizedBox(height: 16),

        // ── Avatar per Collezione (solo se avviata) ─────────────────────
        ...XpService.collections.where((meta) => (completions[meta.key] ?? 0.0) > 0.0).map((meta) {
          final colAvatars = XpService.avatars
              .where((a) => a.collectionKey == meta.key)
              .toList();
          final completion = completions[meta.key] ?? 0.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatarSectionHeader(meta.name, meta.key, completion),
              const SizedBox(height: 8),
              _buildAvatarGrid(colAvatars, level, completions),
              const SizedBox(height: 16),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildAvatarSectionHeader(String title, String? collectionKey, double completion) {
    final pct = (completion * 100).round();
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        if (collectionKey != null) ...[
          Text(
            '$pct%',
            style: TextStyle(
              color: pct == 100 ? AppColors.gold : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: completion,
                minHeight: 5,
                backgroundColor: AppColors.bgLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct == 100 ? AppColors.gold : AppColors.blue,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatarGrid(List<AvatarDef> avatarList, int level, Map<String, double> completions) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: avatarList.length,
      itemBuilder: (context, i) {
        final avatar = avatarList[i];
        final unlocked = avatar.isUnlocked(level, completions);
        final selected = _selectedAvatarId == avatar.id;
        return _buildAvatarTile(avatar, unlocked, selected);
      },
    );
  }

  Widget _buildAvatarTile(AvatarDef avatar, bool unlocked, bool selected) {
    final unlockLabel = avatar.unlockType == AvatarUnlockType.level
        ? 'Lv.${avatar.unlockLevel}'
        : '${avatar.unlockPercent}%';

    return GestureDetector(
      onTap: unlocked ? () => _selectAvatar(avatar.id) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.bgMedium,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.gold
                : unlocked
                    ? AppColors.bgLight
                    : AppColors.bgLight.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ColorFiltered(
                  colorFilter: unlocked
                      ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                      : const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      0.4, 0,
                        ]),
                  child: avatar.buildCircle(22),
                ),
                if (!unlocked)
                  const Icon(Icons.lock, size: 13, color: Colors.white54),
                if (selected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 9, color: Colors.black),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              avatar.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: unlocked ? AppColors.textPrimary : AppColors.textHint,
                fontSize: 8,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!unlocked)
              Text(
                unlockLabel,
                style: const TextStyle(color: AppColors.textHint, fontSize: 8),
              ),
          ],
        ),
      ),
    );
  }

  // Pro banner temporaneamente nascosto — da riabilitare quando il pagamento sarà configurato
  Widget _buildProBanner(bool hasPro) => const SizedBox.shrink();
}
