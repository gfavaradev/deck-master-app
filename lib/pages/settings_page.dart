import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import '../models/collection_model.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/user_avatar_widget.dart';
import 'main_layout.dart';
import 'login_page.dart';
import 'profile_page.dart';
import 'admin_users_page.dart';
import 'admin_home_page.dart';

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

  bool _isAdmin = false;
  bool _notificationsEnabled = false;
  bool _notifAppUpdates = true;
  bool _notifCatalogUpdates = true;
  final NotificationService _notifService = NotificationService();
  bool _isExporting = false;
  bool _isResetting = false;
  String _resetStatus = '';

  bool _isRestoring = false;
  String _restoreStatus = '';
  double _restoreProgress = 0.0;

  Set<String> _unlockedCatalogKeys = {};

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
    _checkAdminStatus();
    _loadNotificationPreference();
    _loadUnlockedCatalogKeys();
  }

  Future<void> _loadUnlockedCatalogKeys() async {
    const supported = {'yugioh', 'pokemon', 'onepiece'};
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
            const SnackBar(
              content: Text('Permesso notifiche negato. Abilitalo nelle impostazioni di sistema.'),
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

  Future<void> _checkAdminStatus() async {
    final isAdmin = await _authService.isCurrentUserAdmin();
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isSigningIn = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (result != null) {
        try { await _repo.syncOnLogin(); } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainLayout()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Accesso annullato')),
          );
        }
      }
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AppConfirmDialog(
        title: 'Elimina Account',
        icon: Icons.person_remove_outlined,
        message: 'Questa azione è irreversibile.\n\n'
            'Il tuo account e tutti i dati associati verranno eliminati definitivamente.',
        confirmLabel: 'Elimina',
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
          const SnackBar(
            content: Text('Per sicurezza, esci e accedi di nuovo prima di eliminare l\'account.'),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: ${e.message}')));
      }
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  Future<void> _exportData(String format) async {
    setState(() => _isExporting = true);
    try {
      final result = await ExportService().exportToClipboard(format);
      if (!mounted) return;
      if (result.requiresPro) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Funzione disponibile a breve')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.cardCount} carte esportate come ${result.format} (negli appunti)')),
      );
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore esportazione: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _resetAndResync() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const AppConfirmDialog(
        title: 'Ripristina Sincronizzazione',
        icon: Icons.sync_problem_outlined,
        iconColor: AppColors.blue,
        message: 'Questa operazione deduplicerà le carte/album/deck presenti due volte, '
            'ripulirà il cloud e ricaricherà i dati corretti.\n\n'
            'Procedi solo se vedi elementi duplicati.',
        confirmLabel: 'Ripristina',
        confirmColor: AppColors.blue,
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _resetStatus = 'Avvio...';
    });

    try {
      await _repo.resetAndResync(
        onStatus: (msg) {
          if (mounted) setState(() => _resetStatus = msg);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronizzazione ripristinata con successo!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() { _isResetting = false; _resetStatus = ''; });
    }
  }

  String _catalogLabel(String key) {
    switch (key) {
      case 'yugioh': return 'Yu-Gi-Oh!';
      case 'pokemon': return 'Pokémon';
      case 'onepiece': return 'One Piece';
      default: return key;
    }
  }

  Future<void> _restoreCatalog(String collectionKey) async {
    final keys = collectionKey == 'all'
        ? _unlockedCatalogKeys.toList()
        : [collectionKey];

    setState(() {
      _isRestoring = true;
      _restoreStatus = 'Connessione...';
      _restoreProgress = 0.0;
    });

    try {
      for (int i = 0; i < keys.length; i++) {
        final key = keys[i];
        final label = _catalogLabel(key);
        final base = i / keys.length;
        final slice = 1.0 / keys.length;

        void onFetch(int current, int total) {
          if (!mounted) return;
          setState(() {
            _restoreProgress = base + (total > 0 ? current / total * slice * 0.5 : 0.0);
            _restoreStatus = '$label: scaricamento $current/$total';
          });
        }

        void onSave(double p) {
          if (!mounted) return;
          setState(() {
            _restoreProgress = base + slice * 0.5 + p * slice * 0.5;
            _restoreStatus = '$label: salvataggio ${(p * 100).round()}%';
          });
        }

        switch (key) {
          case 'yugioh':
            await _repo.redownloadYugiohCatalog(onProgress: onFetch, onSaveProgress: onSave);
          case 'pokemon':
            await _repo.redownloadPokemonCatalog(onProgress: onFetch, onSaveProgress: onSave);
          case 'onepiece':
            await _repo.redownloadOnepieceCatalog(onProgress: onFetch, onSaveProgress: onSave);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(collectionKey == 'all'
            ? 'Tutti i cataloghi ripristinati!'
            : '${_catalogLabel(collectionKey)} ripristinato con successo!'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore ripristino: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() { _isRestoring = false; _restoreStatus = ''; _restoreProgress = 0.0; });
    }
  }

  static const _catalogMeta = [
    (key: 'yugioh',   label: 'Yu-Gi-Oh!',  icon: Icons.star_outline,              accent: AppColors.yugiohAccent),
    (key: 'pokemon',  label: 'Pokémon',     icon: Icons.catching_pokemon,          accent: AppColors.pokemonAccent),
    (key: 'onepiece', label: 'One Piece',   icon: Icons.directions_boat_outlined,  accent: AppColors.onepieceAccent),
  ];

  void _showRestoreDialog() {
    if (_isRestoring || _isOffline) return;

    final unlocked = _catalogMeta
        .where((m) => _unlockedCatalogKeys.contains(m.key))
        .toList();

    if (unlocked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna collezione sbloccata da ripristinare.')),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Ripristina Catalogo', style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            )),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              'Il catalogo locale verrà cancellato e riscaricato dal server.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Container(height: 0.5, color: AppColors.divider),
          if (unlocked.length >= 2) ...[
            _catalogOption(ctx, Icons.cloud_download_outlined, 'Tutti i Cataloghi', 'all', AppColors.blue),
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

  // Pro e Donazioni temporaneamente nascosti — da riabilitare quando il pagamento sarà configurato
  Widget _buildProSection() => const SizedBox.shrink();

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRestoring,
      child: Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMedium,
        title: const Text(
          'Impostazioni',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          _buildUserSection(),
          const SizedBox(height: 12),
          _buildProSection(),
          if (_isAdmin) ...[
            _buildAdminSection(),
            const SizedBox(height: 12),
          ],
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
          _buildDangerSection(),
          const SizedBox(height: 32),
        ],
      ),
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
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: accentColor, size: 14),
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: iconColor, size: 19),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 19),
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
              Icon(icon, color: AppColors.textSecondary, size: 17),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Modalità Offline', style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          )),
                          SizedBox(height: 3),
                          Text('I dati non sono sincronizzati sul cloud', style: TextStyle(
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
                    label: const Text('Accedi e torna online', style: TextStyle(fontWeight: FontWeight.w600)),
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
        child: const Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.bgLight,
              child: Icon(Icons.person, color: AppColors.textSecondary, size: 28),
            ),
            SizedBox(width: 14),
            Text('Utente non loggato', style: TextStyle(
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
                        child: const Text('Vedi Profilo', style: TextStyle(
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

  Widget _buildAdminSection() {
    return _buildSectionCard(
      title: 'Amministrazione',
      icon: Icons.admin_panel_settings,
      accentColor: Colors.orange,
      borderColor: Colors.orange.withValues(alpha:0.25),
      children: [
        _buildTile(
          icon: Icons.people,
          title: 'Gestisci Utenti',
          subtitle: 'Visualizza e modifica ruoli utenti',
          iconColor: Colors.orange,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersPage())),
        ),
        _tileDivider(),
        _buildTile(
          icon: Icons.storage,
          title: 'Gestisci Catalogo',
          subtitle: 'Aggiungi/Modifica carte nel catalogo',
          iconColor: Colors.orange,
          isLast: true,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHomePage())),
        ),
      ],
    );
  }

  Widget _buildCatalogSection() => const SizedBox.shrink();

  Widget _buildCatalogRestoreSection() {
    return _buildSectionCard(
      title: 'Ripristino Catalogo',
      icon: Icons.cloud_download_outlined,
      accentColor: AppColors.info,
      children: [
        _buildTile(
          icon: Icons.download_for_offline_outlined,
          title: 'Ripristina Catalogo',
          subtitle: _isRestoring
              ? _restoreStatus
              : 'Riscarica dal server e aggiorna il catalogo locale',
          iconColor: AppColors.info,
          enabled: !_isRestoring && !_isOffline,
          isLast: !_isRestoring,
          trailing: _isRestoring
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info))
              : const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: _showRestoreDialog,
        ),
        if (_isRestoring) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _restoreProgress,
                    backgroundColor: AppColors.bgDark,
                    valueColor: const AlwaysStoppedAnimation(AppColors.info),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_restoreProgress * 100).round()}%',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExportSection() {
    final spinner = const SizedBox(
      width: 16, height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
    );
    return _buildSectionCard(
      title: 'Esporta Collezione',
      icon: Icons.file_download_outlined,
      accentColor: AppColors.blue,
      children: [
        _buildTile(
          icon: Icons.table_chart_outlined,
          title: 'Esporta come CSV',
          subtitle: 'Copia negli appunti — richiede Pro',
          iconColor: AppColors.blue,
          enabled: !_isExporting,
          trailing: _isExporting ? spinner : const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: () => _exportData('csv'),
        ),
        _tileDivider(),
        _buildTile(
          icon: Icons.data_object,
          title: 'Esporta come JSON',
          subtitle: 'Copia negli appunti — richiede Pro',
          iconColor: AppColors.blue,
          enabled: !_isExporting,
          isLast: true,
          trailing: _isExporting ? spinner : const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          onTap: () => _exportData('json'),
        ),
      ],
    );
  }

  Widget _buildSyncSection() {
    return _buildSectionCard(
      title: 'Sincronizzazione',
      icon: Icons.sync,
      accentColor: AppColors.warning,
      children: [
        _buildTile(
          icon: Icons.sync_problem_outlined,
          title: 'Ripristina Sincronizzazione',
          subtitle: _isResetting ? _resetStatus : 'Risolve elementi duplicati nel cloud',
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

  Widget _buildGeneralSection() {
    return _buildSectionCard(
      title: 'Generale',
      icon: Icons.tune,
      accentColor: AppColors.purple,
      children: [
        _buildSwitchTile(
          icon: Icons.notifications_outlined,
          title: 'Notifiche Push',
          subtitle: 'Ricevi notifiche dall\'app',
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
                    title: 'Aggiornamenti App',
                    subtitle: 'Nuove versioni disponibili',
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
                    title: 'Aggiornamenti Catalogo',
                    subtitle: 'Nuove carte e aggiornamenti prezzi',
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
          title: 'Lingua App',
          subtitle: 'Italiano',
          iconColor: AppColors.purple,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildDangerSection() {
    return _buildSectionCard(
      title: 'Zona Pericolosa',
      icon: Icons.warning_amber_rounded,
      accentColor: AppColors.error,
      borderColor: AppColors.error.withValues(alpha:0.2),
      children: [
        _buildTile(
          icon: Icons.delete_forever,
          title: 'Elimina Account',
          subtitle: 'Elimina definitivamente il tuo account e tutti i dati',
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
