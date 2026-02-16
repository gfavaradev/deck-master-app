import 'package:flutter/material.dart';
import 'main_layout.dart';
import 'login_page.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    final bool isOffline = await _authService.isOfflineMode();

    if (user != null) {
      // Logged in: sync data with Firestore
      setState(() => _statusMessage = 'Sincronizzazione...');
      try {
        await _repo.syncOnLogin();
      } catch (e) {
        debugPrint('Sync on login failed: $e');
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else if (isOffline) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.style, size: 100, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Deck Master',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const CircularProgressIndicator(),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_statusMessage, style: const TextStyle(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
