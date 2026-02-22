import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_layout.dart';
import 'login_page.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  String _statusMessage = '';
  double? _downloadProgress;

  static const String _lastVersionKey = 'app_last_version';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<String?> _checkAppVersion() async {
    if (kIsWeb) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = '${info.version}+${info.buildNumber}';
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getString(_lastVersionKey);
      await prefs.setString(_lastVersionKey, currentVersion);
      if (storedVersion != null && storedVersion != currentVersion) {
        return info.version;
      }
    } catch (e) {
      debugPrint('Version check error: $e');
    }
    return null;
  }

  Future<void> _ensureCatalogDownloaded() async {
    if (kIsWeb) return;
    try {
      final collections = await _repo.getCollections();
      final yugiohUnlocked = collections.any((c) => c.key == 'yugioh' && c.isUnlocked);
      if (!yugiohUnlocked) return;

      final check = await _repo.checkCatalogUpdates();
      final needsDownload = check['needsUpdate'] == true || check['isFirstDownload'] == true;
      if (!needsDownload) return;

      setState(() => _statusMessage = 'Download catalogo in corso...');

      await _repo.downloadYugiohCatalog(
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = total > 0 ? current / total : null;
              _statusMessage = 'Scaricando... $current/$total';
            });
          }
        },
        onSaveProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _statusMessage = 'Salvataggio... ${(progress * 100).toInt()}%';
            });
          }
        },
      );

      setState(() {
        _downloadProgress = null;
        _statusMessage = 'Catalogo aggiornato';
      });
    } catch (e) {
      debugPrint('Catalog ensure error: $e');
    }
  }

  _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    final bool isOffline = await _authService.isOfflineMode();
    final updatedVersion = await _checkAppVersion();

    if (user != null) {
      setState(() => _statusMessage = 'Sincronizzazione...');
      try {
        await _repo.syncOnLogin();
      } catch (e) {
        debugPrint('Sync on login failed: $e');
      }

      // After sync, check if catalog needs downloading (e.g. account switch)
      await _ensureCatalogDownloaded();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainLayout(updateNotification: updatedVersion),
        ),
      );
    } else if (isOffline) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainLayout(updateNotification: updatedVersion),
        ),
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
            if (_downloadProgress != null)
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: _downloadProgress),
              )
            else
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
