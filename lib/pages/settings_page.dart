import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../services/subscription_service.dart';
import '../models/user_model.dart';
import '../theme/app_colors.dart';
import '../widgets/user_avatar_widget.dart';
import 'main_layout.dart';
import 'login_page.dart';
import 'profile_page.dart';
import 'pro_page.dart';
import 'donations_page.dart';
import 'admin_users_page.dart';
import 'admin_home_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  final SubscriptionService _subService = SubscriptionService();
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isOffline = false;
  bool _isSigningIn = false;

  bool _isAdmin = false;
  UserModel? _userModel;
  bool _notificationsEnabled = false;
  bool _notifAppUpdates = true;
  bool _notifCatalogUpdates = true;
  final NotificationService _notifService = NotificationService();
  String _selectedLanguage = 'EN';

  bool _isExporting = false;
  bool _isResetting = false;
  String _resetStatus = '';

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
    _loadLanguagePreference();
    _checkAdminStatus();
    _loadNotificationPreference();
    _loadUserModel();
  }

  Future<void> _loadUserModel() async {
    final user = await _subService.getCurrentUserModel();
    if (mounted) setState(() => _userModel = user);
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
    setState(() {
      _isOffline = offline;
    });
  }

  Future<void> _checkAdminStatus() async {
    final isAdmin = await _authService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    }
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }


  Future<void> _loadLanguagePreference() async {
    final lang = await LanguageService.getPreferredLanguage();
    setState(() {
      _selectedLanguage = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          _buildUserSection(),
          const Divider(),
          _buildProSection(),
          const Divider(),
          if (_isAdmin) ...[
            _buildAdminSection(),
            const Divider(),
          ],
          _buildCatalogSection(),
          const Divider(),
          _buildExportSection(),
          const Divider(),
          _buildSyncSection(),
          const Divider(),
          _buildGeneralSection(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Elimina Account', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Elimina definitivamente il tuo account'),
            onTap: _isOffline ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Account'),
        content: const Text(
          'Questa azione è irreversibile.\n\n'
          'Il tuo account e tutti i dati associati verranno eliminati definitivamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
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
    } catch (e) {
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
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage()));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.cardCount} carte esportate come ${result.format} (negli appunti)')),
      );
    } catch (e) {
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
      builder: (ctx) => AlertDialog(
        title: const Text('Ripristina Sincronizzazione'),
        content: const Text(
          'Questa operazione deduplicerà le carte/album/deck presenti due volte, '
          'ripulirà il cloud e ricaricherà i dati corretti.\n\n'
          'Procedi solo se vedi elementi duplicati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ripristina'),
          ),
        ],
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() { _isResetting = false; _resetStatus = ''; });
    }
  }

  Widget _buildExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Esporta Collezione', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        ),
        ListTile(
          leading: _isExporting
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.table_chart_outlined),
          title: const Text('Esporta come CSV'),
          subtitle: const Text('Copia negli appunti — richiede Pro'),
          enabled: !_isExporting,
          onTap: () => _exportData('csv'),
        ),
        ListTile(
          leading: _isExporting
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.data_object),
          title: const Text('Esporta come JSON'),
          subtitle: const Text('Copia negli appunti — richiede Pro'),
          enabled: !_isExporting,
          onTap: () => _exportData('json'),
        ),
      ],
    );
  }

  Widget _buildSyncSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Sincronizzazione',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: _isResetting
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_problem_outlined, color: Colors.orange),
          title: const Text('Ripristina Sincronizzazione'),
          subtitle: Text(
            _isResetting ? _resetStatus : 'Risolve elementi duplicati nel cloud',
          ),
          enabled: !_isResetting && !_isOffline,
          onTap: _resetAndResync,
        ),
      ],
    );
  }

  Widget _buildGeneralSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Generale',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Notifiche Push'),
          subtitle: const Text('Ricevi notifiche dall\'app'),
          value: _notificationsEnabled,
          onChanged: _toggleNotifications,
        ),
        if (_notificationsEnabled) ...[
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 56, right: 16),
            title: const Text('Aggiornamenti App', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Nuove versioni disponibili', style: TextStyle(fontSize: 12)),
            value: _notifAppUpdates,
            onChanged: (v) async {
              await _notifService.setAppUpdates(v);
              if (mounted) setState(() => _notifAppUpdates = v);
            },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 56, right: 16),
            title: const Text('Aggiornamenti Catalogo', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Nuove carte e aggiornamenti prezzi', style: TextStyle(fontSize: 12)),
            value: _notifCatalogUpdates,
            onChanged: (v) async {
              await _notifService.setCatalogUpdates(v);
              if (mounted) setState(() => _notifCatalogUpdates = v);
            },
          ),
        ],
        const Divider(indent: 16, endIndent: 16),
        const ListTile(
          leading: Icon(Icons.language),
          title: Text('Lingua App'),
          subtitle: Text('Italiano'),
        ),
      ],
    );
  }

  Widget _buildCatalogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Catalogo Yu-Gi-Oh!', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        ),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('Lingua Catalogo'),
          subtitle: Text(LanguageService.languageLabels[_selectedLanguage] ?? _selectedLanguage),
          onTap: _showLanguagePicker,
        ),
      ],
    );
  }


  void _showLanguagePicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lingua Catalogo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LanguageService.supportedLanguages.map((code) {
            return RadioListTile<String>(
              title: Text(LanguageService.languageLabels[code] ?? code),
              value: code,
              groupValue: _selectedLanguage,
              onChanged: (val) async {
                if (val != null) {
                  await LanguageService.setPreferredLanguage(val);
                  if (!context.mounted) return;
                  setState(() => _selectedLanguage = val);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProSection() {
    final hasPro = _userModel?.hasProAccess ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Piano',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
          title: Text(hasPro ? 'Deck Master Pro' : 'Passa a Pro'),
          subtitle: Text(
            hasPro ? 'Abbonamento attivo — grazie!' : 'Sblocca il Deck Builder e altre funzioni',
          ),
          trailing: hasPro
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_outline, color: Color(0xFFFF6B35)),
          title: const Text('Supporta il Progetto'),
          subtitle: const Text('Donazioni e badge esclusivi'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DonationsPage()),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text(
                'Amministrazione',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.people, color: Colors.orange),
          title: const Text('Gestisci Utenti'),
          subtitle: const Text('Visualizza e modifica ruoli utenti'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AdminUsersPage()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.storage, color: Colors.orange),
          title: const Text('Gestisci Catalogo'),
          subtitle: const Text('Aggiungi/Modifica carte nel catalogo'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AdminHomePage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUserSection() {
    if (_isOffline) {
      return Column(
        children: [
          const ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey,
              child: Icon(Icons.person_off, color: Colors.white),
            ),
            title: Text('Modalità Offline'),
            subtitle: Text('I dati non sono sincronizzati sul cloud'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _isSigningIn
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi),
                label: const Text('Accedi e torna online'),
                onPressed: _isSigningIn ? null : _signInWithGoogle,
              ),
            ),
          ),
        ],
      );
    }

    if (_user == null) {
      return const ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text('Utente non loggato'),
      );
    }

    return ListTile(
      leading: UserAvatarWidget(radius: 22, photoUrl: _user.photoURL),
      title: Text(_user.displayName ?? 'Utente'),
      subtitle: Text(_user.email ?? ''),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      ),
    );
  }
}
