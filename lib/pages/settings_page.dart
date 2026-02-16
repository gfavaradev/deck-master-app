import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import 'login_page.dart';

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
  String _selectedLanguage = 'EN';

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
    _loadLanguagePreference();
  }

  Future<void> _checkOfflineMode() async {
    final offline = await _authService.isOfflineMode();
    setState(() {
      _isOffline = offline;
    });
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
          _buildCatalogSection(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sincronizza Dati'),
            subtitle: const Text('Sincronizza dati con il cloud'),
            onTap: () async {
              try {
                await _repo.fullSync();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sincronizzazione completata!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Errore sync: $e')),
                  );
                }
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
              if (mounted) {
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
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
          title: const Text('Aggiorna Catalogo'),
          subtitle: const Text('Scarica/Aggiorna tutte le carte in tutte le lingue'),
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

    final statusNotifier = ValueNotifier<String>('Cancellazione catalogo vecchio...');
    final progressNotifier = ValueNotifier<double?>(null);
    final detailNotifier = ValueNotifier<String>('');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Download Catalogo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double?>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) {
                  return CircularProgressIndicator(value: progress);
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, status, _) {
                  return Text(status, textAlign: TextAlign.center);
                },
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: detailNotifier,
                builder: (context, detail, _) {
                  return Text(
                    detail,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    void disposeNotifiers() {
      statusNotifier.dispose();
      progressNotifier.dispose();
      detailNotifier.dispose();
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      statusNotifier.value = 'Scaricando da Firestore...';

      await _repo.redownloadYugiohCatalog(
        onProgress: (current, total) {
          progressNotifier.value = current / total;
          detailNotifier.value = 'Chunk $current di $total';
        },
        onSaveProgress: (progress) {
          statusNotifier.value = 'Salvando nel database...';
          progressNotifier.value = progress;
          detailNotifier.value = '${(progress * 100).toInt()}%';
        },
      );

      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogo aggiornato con successo!')),
        );
      }
      disposeNotifiers();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      disposeNotifiers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
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
                  setState(() => _selectedLanguage = val);
                  if (mounted) Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
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
