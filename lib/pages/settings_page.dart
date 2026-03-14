import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../services/subscription_service.dart';
import '../models/user_model.dart';
import '../theme/app_colors.dart';
import 'main_layout.dart';
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
  bool _isDownloading = false;

  bool _isAdmin = false;
  UserModel? _userModel;
  bool _notificationsEnabled = false;
  bool _notifAppUpdates = true;
  bool _notifCatalogUpdates = true;
  final NotificationService _notifService = NotificationService();
  String _selectedLanguage = 'EN';
  String _downloadStatus = '';
  double? _downloadProgress;

  // One Piece download state
  bool _isDownloadingOP = false;
  String _downloadStatusOP = '';
  double? _downloadProgressOP;

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
          _buildOnePieceCatalogSection(),
          const Divider(),
          _buildGeneralSection(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Elimina Account', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Invia una richiesta di eliminazione account'),
            onTap: _isOffline ? null : _requestAccountDeletion,
          ),
        ],
      ),
    );
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Account'),
        content: const Text(
          'Verrà aperta la tua app email con una richiesta precompilata.\n\n'
          'Il tuo account verrà eliminato entro 48 ore dalla ricezione della richiesta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continua'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final email = _user?.email ?? '';
    final subject = Uri.encodeComponent('Richiesta eliminazione account DeckMaster');
    final body = Uri.encodeComponent(
      'Salve,\n\nRichiedo l\'eliminazione del mio account DeckMaster.\n\nEmail account: $email\n\nGrazie.',
    );
    final uri = Uri.parse('mailto:support@deckmaster.app?subject=$subject&body=$body');

    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire l\'app email. Contattaci manualmente.')),
      );
    }
  }

  Widget _buildOnePieceCatalogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Catalogo One Piece TCG', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        ),
        ListTile(
          leading: _isDownloadingOP
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sailing),
          title: Text(_isDownloadingOP ? _downloadStatusOP : 'Aggiorna Catalogo'),
          subtitle: _isDownloadingOP
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgressOP),
                    const SizedBox(height: 4),
                    Text(
                      _downloadProgressOP != null
                        ? '${(_downloadProgressOP! * 100).toInt()}%'
                        : 'In corso...',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                )
              : const Text('Scarica/Aggiorna tutte le carte One Piece'),
          enabled: !_isDownloadingOP,
          onTap: _downloadOnePieceCatalog,
        ),
      ],
    );
  }

  Future<void> _downloadOnePieceCatalog() async {
    if (!mounted) return;
    setState(() {
      _isDownloadingOP = true;
      _downloadStatusOP = 'Controllo aggiornamenti...';
      _downloadProgressOP = null;
    });

    try {
      final updateInfo = await _repo.checkOnepieceCatalogUpdates();

      if (updateInfo['error'] != null) {
        if (mounted) {
          setState(() { _isDownloadingOP = false; _downloadStatusOP = ''; _downloadProgressOP = null; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore controllo aggiornamenti: ${updateInfo['error']}')),
          );
        }
        return;
      }

      if (!(updateInfo['needsUpdate'] as bool)) {
        if (mounted) {
          setState(() { _isDownloadingOP = false; _downloadStatusOP = ''; _downloadProgressOP = null; });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Catalogo One Piece già aggiornato!'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      final isIncremental = updateInfo['canDoIncremental'] == true;
      setState(() {
        _downloadStatusOP = isIncremental
            ? 'Aggiornamento incrementale...'
            : 'Scaricando da Firestore...';
      });

      await _repo.downloadOnepieceCatalog(
        updateInfo: updateInfo,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _downloadProgressOP = current / total;
              _downloadStatusOP = isIncremental
                  ? 'Aggiornando chunk $current di $total'
                  : 'Scaricando chunk $current di $total';
            });
          }
        },
        onSaveProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgressOP = progress;
              _downloadStatusOP = 'Salvando nel database...';
            });
          }
        },
      );

      if (mounted) {
        setState(() { _isDownloadingOP = false; _downloadStatusOP = ''; _downloadProgressOP = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogo One Piece aggiornato!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isDownloadingOP = false; _downloadStatusOP = ''; _downloadProgressOP = null; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }
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
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sincronizza Dati'),
          subtitle: const Text('Sincronizza dati con il cloud'),
          onTap: () async {
            try {
              await _repo.fullSync();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sincronizzazione completata!')),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Errore sync: $e')),
              );
            }
          },
        ),
        const Divider(indent: 16, endIndent: 16),
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
          leading: _isDownloading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download),
          title: Text(_isDownloading ? _downloadStatus : 'Aggiorna Catalogo'),
          subtitle: _isDownloading
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 4),
                    Text(
                      _downloadProgress != null
                        ? '${(_downloadProgress! * 100).toInt()}%'
                        : 'In corso...',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                )
              : const Text('Scarica/Aggiorna tutte le carte in tutte le lingue'),
          enabled: !_isDownloading,
          onTap: _downloadCatalog,
        ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('Lingua Catalogo'),
          subtitle: Text(LanguageService.languageLabels[_selectedLanguage] ?? _selectedLanguage),
          onTap: _showLanguagePicker,
        ),
      ],
    );
  }

  Future<void> _downloadCatalog() async {
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
      _downloadStatus = 'Controllo aggiornamenti...';
      _downloadProgress = null;
    });

    try {
      // 1. Check if update is needed
      final updateInfo = await _repo.checkCatalogUpdates();

      if (updateInfo['error'] != null) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloadStatus = '';
            _downloadProgress = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore controllo aggiornamenti: ${updateInfo['error']}')),
          );
        }
        return;
      }

      final needsUpdate = updateInfo['needsUpdate'] as bool;

      // 2. If no update needed, show message and return
      if (!needsUpdate) {
        final totalCards = updateInfo['totalCards'] as int?;

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloadStatus = '';
            _downloadProgress = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Catalogo già aggiornato! ${totalCards != null ? "($totalCards carte)" : ""}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // 3. Update needed - perform download
      final isFirstDownload = updateInfo['isFirstDownload'] as bool? ?? false;
      final remoteVersion = updateInfo['remoteVersion'] as int?;
      final totalCards = updateInfo['totalCards'] as int?;

      if (mounted) {
        await _performDownload(
          isFirstDownload: isFirstDownload,
          remoteVersion: remoteVersion,
          totalCards: totalCards,
          updateInfo: updateInfo,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
          _downloadProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    }
  }

  Future<void> _performDownload({
    required bool isFirstDownload,
    int? remoteVersion,
    int? totalCards,
    Map<String, dynamic>? updateInfo,
  }) async {
    try {
      final isIncremental = updateInfo?['canDoIncremental'] == true;
      setState(() {
        _downloadStatus = isIncremental
            ? 'Aggiornamento incrementale...'
            : 'Scaricando da Firestore...';
        _downloadProgress = null;
      });

      await _repo.downloadYugiohCatalog(
        updateInfo: updateInfo,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = current / total;
              _downloadStatus = isIncremental
                  ? 'Aggiornando chunk $current di $total'
                  : 'Scaricando chunk $current di $total';
            });
          }
        },
        onSaveProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _downloadStatus = 'Salvando nel database...';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
          _downloadProgress = null;
        });

        final message = isFirstDownload
          ? 'Catalogo scaricato con successo! ${totalCards != null ? "($totalCards carte)" : ""}'
          : 'Catalogo aggiornato alla versione $remoteVersion!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
          _downloadProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
      rethrow;
    }
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
      leading: CircleAvatar(
        backgroundImage: _user.photoURL != null ? NetworkImage(_user.photoURL!) : null,
        child: _user.photoURL == null ? const Icon(Icons.person) : null,
      ),
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
