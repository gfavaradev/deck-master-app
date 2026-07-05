import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/banner_ad_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/app_preferences.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import '../services/subscription_service.dart' show SubscriptionService;
import 'pro_page.dart';
import '../models/collection_model.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/user_avatar_widget.dart';
import 'main_layout.dart';
import 'tutorial_page.dart';
import 'login_page.dart';
import 'profile_page.dart';

class SettingsPage extends StatefulWidget {
  final String? collectionKey;
  const SettingsPage({super.key, this.collectionKey});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isOffline = false;
  bool _isSigningIn = false;

  bool _isPro = false;
  bool _notificationsEnabled = false;
  bool _notifAppUpdates = true;
  bool _notifCatalogUpdates = true;
  final NotificationService _notifService = NotificationService();
  bool _isExporting = false;
  bool _isResetting = false;
  String _resetStatus = '';

  String _languageCode = 'it';
  String _currencyCode = 'EUR';

  Set<String> _unlockedCatalogKeys = {};

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
    _checkProStatus();
    _loadNotificationPreference();
    _loadUnlockedCatalogKeys();
    _loadAppPreferences();
  }

  void _loadAppPreferences() {
    final prefs = AppPreferences.instance;
    setState(() {
      _languageCode = prefs.languageCode;
      _currencyCode = prefs.currencyCode;
    });
  }

  Future<void> _loadUnlockedCatalogKeys() async {
    const supported = {
      'yugioh', 'pokemon', 'onepiece', 'magic',
      'digimon', 'lorcana', 'flesh-and-blood', 'vanguard',
      'dragon-ball-super', 'star-wars', 'riftbound', 'gundam', 'union-arena',
    };
    final all = await _repo.getCollections();
    if (mounted) {
      setState(() {
        _unlockedCatalogKeys = all
            .where((CollectionModel c) => c.isUnlocked && supported.contains(c.key))
            .map((c) => c.key)
            .toSet();
      });
    }
  }

  Future<void> _loadNotificationPreference() async {
    final enabled = await _notifService.isEnabled();
    final appUpdates = await _notifService.isAppUpdatesEnabled();
    final catalogUpdates = await _notifService.isCatalogUpdatesEnabled();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _notifAppUpdates = appUpdates;
        _notifCatalogUpdates = catalogUpdates;
      });
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted = await _notifService.enable();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.msgNotifPermissionDenied),
            ),
          );
        }
        return;
      }
    } else {
      await _notifService.disable();
    }
    if (mounted) setState(() => _notificationsEnabled = value);
  }

  Future<void> _checkOfflineMode() async {
    final offline = await _authService.isOfflineMode();
    if (mounted) setState(() => _isOffline = offline);
  }

  Future<void> _checkProStatus() async {
    final isPro = await SubscriptionService().currentUserHasPro();
    if (mounted) setState(() => _isPro = isPro);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isSigningIn = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (result != null) {
        try { await _repo.syncOnLogin(isManualLogin: true).timeout(const Duration(seconds: 20)); } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainLayout()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.msgLoginCancelledShort)),
          );
        }
      }
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.msgErrorGeneric(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: l10n.dlgDeleteAccountTitle,
        icon: Icons.person_remove_outlined,
        message: l10n.dlgDeleteAccountMsg,
        confirmLabel: l10n.btnDelete,
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final uid = _user?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).delete().catchError((_) {});
      }
      await _user?.delete();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.msgDeleteAccountRelogin),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.msgErrorGeneric(e.message ?? ''))));
      }
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.msgErrorGeneric(e.toString()))));
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    try {
      final result = await ExportService().exportToExcel();
      if (!mounted) return;
      if (result.requiresPro) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.msgExportProRequired)),
        );
        return;
      }
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.msgCardsExported(result.cardCount, result.format))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.msgExportError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _resetAndResync() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: l10n.dlgResetSyncTitle,
        icon: Icons.sync_problem_outlined,
        iconColor: AppColors.blue,
        message: l10n.dlgResetSyncMsg,
        confirmLabel: l10n.btnRestore,
        confirmColor: AppColors.blue,
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _resetStatus = l10n.settingsResetStarting;
    });

    try {
      await _repo.resetAndResync(
        onStatus: (msg) {
          if (mounted) setState(() => _resetStatus = msg);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.msgSyncRestoredSuccess),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.msgErrorGeneric(e.toString())), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() { _isResetting = false; _resetStatus = ''; });
    }
  }

  void _restoreCatalog(String collectionKey) {
    Navigator.pop(context, {'restore': collectionKey});
  }

  static const _catalogMeta = [
    (key: 'yugioh',           label: 'Yu-Gi-Oh!',              icon: Icons.star_outline,             accent: AppColors.yugiohAccent),
    (key: 'pokemon',          label: 'Pokémon',                icon: Icons.catching_pokemon,         accent: AppColors.pokemonAccent),
    (key: 'onepiece',         label: 'One Piece',              icon: Icons.directions_boat_outlined, accent: AppColors.onepieceAccent),
    (key: 'magic',            label: 'Magic: The Gathering',   icon: Icons.diamond_outlined,         accent: AppColors.magicAccent),
    (key: 'digimon',          label: 'Digimon',                icon: Icons.pets,                     accent: Color(0xFF00ACC1)),
    (key: 'lorcana',          label: 'Disney Lorcana',         icon: Icons.auto_stories,             accent: Color(0xFF7B1FA2)),
    (key: 'flesh-and-blood',  label: 'Flesh and Blood',        icon: Icons.sports_martial_arts,      accent: Color(0xFFBF360C)),
    (key: 'vanguard',         label: 'Cardfight!! Vanguard',   icon: Icons.shield,                   accent: Color(0xFF00695C)),
    (key: 'dragon-ball-super',label: 'Dragon Ball Super',      icon: Icons.bolt,                     accent: Color(0xFFFF6D00)),
    (key: 'star-wars',        label: 'Star Wars: Unlimited',   icon: Icons.rocket_launch,            accent: Color(0xFFFFD600)),
    (key: 'riftbound',        label: 'Riftbound',              icon: Icons.casino,                   accent: Color(0xFF1565C0)),
    (key: 'gundam',           label: 'Gundam Card Game',       icon: Icons.smart_toy,                accent: Color(0xFF546E7A)),
    (key: 'union-arena',      label: 'Union Arena',            icon: Icons.people,                   accent: Color(0xFF2E7D32)),
  ];

  void _showRestoreDialog() {
    if (_isOffline) return;
    final l10n = AppLocalizations.of(context)!;

    final unlocked = _catalogMeta
        .where((m) => _unlockedCatalogKeys.contains(m.key))
        .toList();

    if (unlocked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.msgNoCollectionToRestore)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(l10n.settingsRestoreDialogTitle, style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              l10n.settingsRestoreDialogSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Container(height: 0.5, color: AppColors.divider),
          if (unlocked.length >= 2) ...[
            _catalogOption(ctx, Icons.cloud_download_outlined, l10n.settingsRestoreAllCatalogs, 'all', AppColors.blue),
            Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 56)),
          ],
          for (int i = 0; i < unlocked.length; i++) ...[
            _catalogOption(ctx, unlocked[i].icon, unlocked[i].label, unlocked[i].key, unlocked[i].accent),
            if (i < unlocked.length - 1)
              Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 56)),
          ],
          SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 20),
        ],
      ),
    );
  }

  Widget _catalogOption(BuildContext sheetCtx, IconData icon, String label, String key, Color accentColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(sheetCtx);
          _restoreCatalog(key);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accentColor, size: 19),
              ),
              const SizedBox(width: 13),
              Expanded(child: Text(label, style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ))),
              const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Mostrata solo agli utenti non-Pro: porta alla pagina di upgrade.
  Widget _buildProSection() {
    if (_isPro) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2A1F00),
            AppColors.gold.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage())),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 24),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.settingsUpgradePro, style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      )),
                      const SizedBox(height: 2),
                      Text(l10n.settingsUpgradeProSubtitle, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.gold, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMedium,
        title: Text(
          AppLocalizations.of(context)!.settingsTitle,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                children: [
                  _buildUserSection(),
                  const SizedBox(height: 12),
                  _buildProSection(),
                  _buildCatalogSection(),
                  const SizedBox(height: 12),
                  _buildCatalogRestoreSection(),
                  const SizedBox(height: 12),
                  _buildExportSection(),
                  const SizedBox(height: 12),
                  _buildSyncSection(),
                  const SizedBox(height: 12),
                  _buildGeneralSection(),
                  const SizedBox(height: 12),
                  _buildLegalSection(),
                  const SizedBox(height: 12),
                  _buildDangerSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          if (!kIsWeb) const BannerAdWidget(),
        ],
      ),
    );
  }

  // ─── Design helpers ──────────────────────────────────────────────────────────

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<Widget> children,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.bgMedium,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: accentColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: accentColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 0.5, color: AppColors.divider),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color iconColor = AppColors.blue,
    bool enabled = true,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(15.5))
            : BorderRadius.zero,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      )),
                      if (subtitle != null)
                        Text(subtitle, style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        )),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color iconColor = AppColors.blue,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(15.5))
            : BorderRadius.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    )),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      )),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: AppColors.gold,
                activeTrackColor: AppColors.gold.withValues(alpha:0.3),
                inactiveThumbColor: AppColors.textHint,
                inactiveTrackColor: AppColors.bgLight,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    )),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      )),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: AppColors.gold,
                activeTrackColor: AppColors.gold.withValues(alpha:0.3),
                inactiveThumbColor: AppColors.textHint,
                inactiveTrackColor: AppColors.bgMedium,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileDivider() => Padding(
    padding: const EdgeInsets.only(left: 65),
    child: Container(height: 0.5, color: AppColors.divider),
  );

  // ─── Sections ────────────────────────────────────────────────────────────────

  Widget _buildUserSection() {
    if (_isOffline) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withValues(alpha:0.35), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha:0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.wifi_off, color: AppColors.warning, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.of(context)!.settingsOfflineMode, style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          )),
                          const SizedBox(height: 3),
                          Text(AppLocalizations.of(context)!.settingsOfflineSubtitle, style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSigningIn
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.wifi, size: 18),
                    label: Text(AppLocalizations.of(context)!.settingsSignInOnline, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: _isSigningIn ? null : _signInWithGoogle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_user == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.bgLight,
              child: Icon(Icons.person, color: AppColors.textSecondary, size: 28),
            ),
            const SizedBox(width: 14),
            Text(AppLocalizations.of(context)!.settingsUserNotLogged, style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            )),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.bgMedium, AppColors.bgLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha:0.2), width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                UserAvatarWidget(radius: 28, photoUrl: _user.photoURL),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _user.displayName ?? 'Utente',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_user.email ?? '', style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      )),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha:0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.gold.withValues(alpha:0.35), width: 0.5),
                        ),
                        child: Text(AppLocalizations.of(context)!.settingsViewProfile, style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogSection() => const SizedBox.shrink();

  Widget _buildCatalogRestoreSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildSectionCard(
      title: l10n.settingsSectionCatalogRestore,
      icon: Icons.cloud_download_outlined,
      accentColor: AppColors.info,
      children: [
        _buildTile(
          icon: Icons.download_for_offline_outlined,
          title: l10n.settingsRestoreCatalog,
          subtitle: l10n.settingsRestoreCatalogSubtitle,
          iconColor: AppColors.info,
          enabled: !_isOffline,
          isLast: true,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _showRestoreDialog,
        ),
      ],
    );
  }

  Widget _buildExportSection() {
    final l10n = AppLocalizations.of(context)!;
    const spinner = SizedBox(
      width: 16, height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
    );
    return _buildSectionCard(
      title: l10n.settingsSectionExport,
      icon: Icons.file_download_outlined,
      accentColor: AppColors.blue,
      children: [
        _buildTile(
          icon: Icons.table_chart_outlined,
          title: l10n.settingsExportExcel,
          subtitle: l10n.settingsExportExcelSubtitle,
          iconColor: AppColors.blue,
          enabled: !_isExporting,
          isLast: true,
          trailing: _isExporting ? spinner : const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _exportExcel,
        ),
      ],
    );
  }

  Widget _buildSyncSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildSectionCard(
      title: l10n.settingsSectionSync,
      icon: Icons.sync,
      accentColor: AppColors.warning,
      children: [
        _buildTile(
          icon: Icons.sync_problem_outlined,
          title: l10n.settingsResetSync,
          subtitle: _isResetting ? _resetStatus : l10n.settingsResetSyncSubtitle,
          iconColor: AppColors.warning,
          enabled: !_isResetting && !_isOffline,
          isLast: true,
          trailing: _isResetting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning))
              : const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _resetAndResync,
        ),
      ],
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint, borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(AppLocalizations.of(context)!.settingsLanguageDialogTitle,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          Container(height: 0.5, color: AppColors.divider),
          for (final lang in AppPreferences.languages) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  Navigator.pop(ctx);
                  await AppPreferences.instance.setLanguage(lang.code);
                  if (mounted) setState(() => _languageCode = lang.code);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Text(lang.flag, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Expanded(child: Text(lang.name,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15))),
                      if (_languageCode == lang.code)
                        const Icon(Icons.check, color: AppColors.gold, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            if (lang != AppPreferences.languages.last)
              Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 62)),
          ],
          SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 20),
        ],
      ),
    );
  }

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint, borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(AppLocalizations.of(context)!.settingsCurrencyDialogTitle,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          Container(height: 0.5, color: AppColors.divider),
          for (final curr in AppPreferences.currencies) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  Navigator.pop(ctx);
                  await AppPreferences.instance.setCurrency(curr.code);
                  if (mounted) setState(() => _currencyCode = curr.code);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.bgLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text(curr.symbol,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(curr.code, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                            Text(curr.name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_currencyCode == curr.code)
                        const Icon(Icons.check, color: AppColors.gold, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            if (curr != AppPreferences.currencies.last)
              Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 70)),
          ],
          SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildGeneralSection() {
    final l10n = AppLocalizations.of(context)!;
    final langEntry = AppPreferences.languages.firstWhere(
      (l) => l.code == _languageCode, orElse: () => AppPreferences.languages.first);
    final currEntry = AppPreferences.currencies.firstWhere(
      (c) => c.code == _currencyCode, orElse: () => AppPreferences.currencies.first);

    return _buildSectionCard(
      title: l10n.settingsSectionGeneral,
      icon: Icons.tune,
      accentColor: AppColors.purple,
      children: [
        _buildSwitchTile(
          icon: Icons.notifications_outlined,
          title: l10n.settingsPushNotifications,
          subtitle: l10n.settingsPushNotificationsSubtitle,
          value: _notificationsEnabled,
          onChanged: _toggleNotifications,
          iconColor: AppColors.purple,
        ),
        if (_notificationsEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  _buildSubSwitchTile(
                    icon: Icons.system_update_outlined,
                    title: l10n.settingsNotifAppUpdates,
                    subtitle: l10n.settingsNotifAppUpdatesSubtitle,
                    value: _notifAppUpdates,
                    onChanged: (v) async {
                      await _notifService.setAppUpdates(v);
                      if (mounted) setState(() => _notifAppUpdates = v);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 39),
                    child: Container(height: 0.5, color: AppColors.divider),
                  ),
                  _buildSubSwitchTile(
                    icon: Icons.new_releases_outlined,
                    title: l10n.settingsNotifCatalogUpdates,
                    subtitle: l10n.settingsNotifCatalogUpdatesSubtitle,
                    value: _notifCatalogUpdates,
                    onChanged: (v) async {
                      await _notifService.setCatalogUpdates(v);
                      if (mounted) setState(() => _notifCatalogUpdates = v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        _tileDivider(),
        _buildTile(
          icon: Icons.language,
          title: l10n.settingsLanguage,
          subtitle: '${langEntry.flag}  ${langEntry.name}',
          iconColor: AppColors.purple,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _showLanguagePicker,
        ),
        _tileDivider(),
        _buildTile(
          icon: Icons.monetization_on_outlined,
          title: l10n.settingsCurrency,
          subtitle: '${currEntry.symbol}  ${currEntry.code} — ${currEntry.name}',
          iconColor: AppColors.purple,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _showCurrencyPicker,
        ),
        _tileDivider(),
        _buildTile(
          icon: Icons.help_outline,
          title: l10n.settingsAppGuide,
          subtitle: l10n.settingsAppGuideSubtitle,
          iconColor: AppColors.purple,
          isLast: true,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const TutorialPage(),
            ),
          ),
        ),
      ],
    );
  }

  static const _privacyPolicyUrl = 'https://gfavaradev.github.io/deck-master-app/privacy-policy.html';
  Future<void> _launchPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsPrivacyOpenError)),
        );
      }
    }
  }

  Widget _buildLegalSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildSectionCard(
      title: l10n.settingsSectionLegal,
      icon: Icons.gavel_outlined,
      accentColor: AppColors.textHint,
      children: [
        _buildTile(
          icon: Icons.privacy_tip_outlined,
          title: l10n.settingsPrivacyPolicy,
          subtitle: l10n.settingsPrivacyPolicySubtitle,
          iconColor: AppColors.textHint,
          isLast: true,
          trailing: const Icon(Icons.open_in_new, color: AppColors.textHint, size: 18),
          onTap: _launchPrivacyPolicy,
        ),
      ],
    );
  }

  Widget _buildDangerSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildSectionCard(
      title: l10n.settingsSectionDanger,
      icon: Icons.warning_amber_rounded,
      accentColor: AppColors.error,
      borderColor: AppColors.error.withValues(alpha:0.2),
      children: [
        _buildTile(
          icon: Icons.delete_forever,
          title: l10n.settingsDeleteAccount,
          subtitle: l10n.settingsDeleteAccountSubtitle,
          iconColor: AppColors.error,
          enabled: !_isOffline,
          isLast: true,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _deleteAccount,
        ),
      ],
    );
  }
}
