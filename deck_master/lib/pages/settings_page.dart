import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
  }

  Future<void> _checkOfflineMode() async {
    final offline = await _authService.isOfflineMode();
    setState(() {
      _isOffline = offline;
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
          const ListTile(
            leading: Icon(Icons.notifications),
            title: Text('Notifiche'),
            subtitle: Text('Configura le notifiche'),
          ),
          const ListTile(
            leading: Icon(Icons.language),
            title: Text('Lingua'),
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
