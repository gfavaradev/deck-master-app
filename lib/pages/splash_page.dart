import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_layout.dart';
import 'login_page.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
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

      setState(() => _statusMessage = check['canDoIncremental'] == true
          ? 'Aggiornamento in corso...'
          : 'Download catalogo in corso...');

      await _repo.downloadYugiohCatalog(
        updateInfo: check,
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

  Future<void> _checkAuth() async {
    // currentUser is synchronous and uses the locally cached auth state —
    // no network call needed, works offline immediately after Firebase.initializeApp().
    final User? user = FirebaseAuth.instance.currentUser;
    final String? updatedVersion = await _checkAppVersion();

    if (!mounted) return;

    if (user != null) {
      // Try to sync, but never block navigation if offline/slow network.
      setState(() => _statusMessage = 'Sincronizzazione...');
      try {
        await _repo.syncOnLogin().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Sync on login skipped (offline?): $e');
      }

      // Check catalog updates only if reachable; skip silently if offline.
      try {
        await _ensureCatalogDownloaded().timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Catalog check skipped (offline?): $e');
      }

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
      backgroundColor: AppColors.bgDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon/dm_logo_no_white.png', height: 180),
            const SizedBox(height: 20),
            const Text(
              'Deck Master',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            if (_downloadProgress != null)
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  color: AppColors.gold,
                  backgroundColor: Colors.white24,
                ),
              )
            else
              const CircularProgressIndicator(color: AppColors.gold),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_statusMessage, style: const TextStyle(color: AppColors.textHint)),
            ],
          ],
        ),
      ),
    );
  }
}
