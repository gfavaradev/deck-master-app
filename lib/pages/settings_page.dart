import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import 'login_page.dart';
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
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isOffline = false;
  bool _isDownloading = false;
  bool _isAdmin = false;
  String _selectedLanguage = 'EN';
  String _downloadStatus = '';
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
    _loadLanguagePreference();
    _checkAdminStatus();
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
          if (_isAdmin) ...[
            _buildAdminSection(),
            const Divider(),
          ],
          _buildCatalogSection(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sincronizza Dati'),
            subtitle: const Text('Sincronizza dati con il cloud'),
            onTap: () async {
              try {
                await _repo.fullSync();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sincronizzazione completata!')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Errore sync: $e')),
                );
              }
            },
          ),
          const ListTile(
            leading: Icon(Icons.notifications),
            title: Text('Notifiche'),
            subtitle: Text('Configura le notifiche'),
          ),
          const ListTile(
            leading: Icon(Icons.language),
            title: Text('Lingua App'),
            subtitle: Text('Italiano'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await _authService.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Elimina Account', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Cancella account e tutti i dati associati'),
            onTap: _isOffline ? null : _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Account'),
        content: const Text(
          'Sei sicuro? Questa azione è irreversibile.\n\n'
          'Il tuo account e tutti i dati (deck, album, carte) verranno eliminati definitivamente.',
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
      await _authService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('requires-recent-login')
          ? 'Per sicurezza, esegui prima il logout e accedi di nuovo, poi riprova.'
          : 'Errore durante l\'eliminazione: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
    }
  }

  Widget _buildCatalogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Catalogo Yu-Gi-Oh!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
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
  }) async {
    try {
      setState(() {
        _downloadStatus = 'Scaricando da Firestore...';
        _downloadProgress = null;
      });

      await _repo.redownloadYugiohCatalog(
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = current / total;
              _downloadStatus = 'Scaricando chunk $current di $total';
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
      return const ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.person_off, color: Colors.white),
        ),
        title: Text('Modalità Offline'),
        subtitle: Text('I dati non sono sincronizzati sul cloud'),
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
    );
  }
}
