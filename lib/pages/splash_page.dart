import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_layout.dart';
import 'login_page.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';

enum _Phase { loading, greeting }

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  final DataRepository _repo = DataRepository();

  _Phase _phase = _Phase.loading;
  String _statusMessage = '';
  double? _downloadProgress;
  String _greetingName = '';
  bool _isFirstLogin = false;
  bool _navigating = false;
  String? _updatedVersion;

  late AnimationController _greetingController;
  late Animation<double> _greetingFade;

  static const String _lastVersionKey = 'app_last_version';

  static const _returningMessages = [
    'Le tue carte ti stavano aspettando.',
    'Il tuo mazzo è pronto per l\'azione.',
    'La collezione chiama, il collezionista risponde.',
    'Ogni carta ha una storia. Qual è la tua di oggi?',
  ];

  @override
  void initState() {
    super.initState();
    _greetingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _greetingFade = CurvedAnimation(parent: _greetingController, curve: Curves.easeOut);
    _checkAuth();
  }

  @override
  void dispose() {
    _greetingController.dispose();
    super.dispose();
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

  Future<void> _checkAuth() async {
    // On Windows desktop, Firebase Auth restores credentials asynchronously from
    // a local JSON file. Using currentUser directly can return null before restoration
    // completes. authStateChanges().first waits for the first emitted auth state.
    final User? user = await FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => null);

    if (user != null) {
      // Sync parte subito in parallelo con il greeting — non blocca la UI
      // ma aspettiamo che finisca prima di navigare (max 2s extra dopo il greeting)
      final syncFuture = _repo.syncOnLogin()
          .timeout(const Duration(seconds: 20))
          .catchError((_) {});
      _checkAppVersion().then((v) { if (mounted) _updatedVersion = v; });

      // Solo SharedPreferences — velocissimo (~10ms)
      final prefs = await SharedPreferences.getInstance();
      final key = 'first_login_done_${user.uid}';
      final hasLoggedInBefore = prefs.getBool(key) ?? false;
      await prefs.setBool(key, true);

      final rawName = user.displayName ?? user.email?.split('@').first ?? 'Collezionista';
      final name = rawName.split(' ').first;

      if (!mounted) return;

      setState(() {
        _phase = _Phase.greeting;
        _greetingName = name;
        _isFirstLogin = !hasLoggedInBefore;
        _statusMessage = '';
        _downloadProgress = null;
      });
      _greetingController.forward();

      // Aspetta il greeting (1.8s) + max 2s in più per il sync
      await Future.delayed(const Duration(milliseconds: 1800));
      await syncFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      _navigateToMain();
    } else {
      // Aspetta il primo frame prima di navigare — evita di chiamare
      // Navigator.of(context) dentro initState prima del primo build
      await Future.delayed(Duration.zero);
      if (!mounted) return;
      _navigateToLogin();
    }
  }

  void _navigateToMain() {
    if (_navigating || !mounted) return;
    _navigating = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => MainLayout(updateNotification: _updatedVersion),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => const LoginPage(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: GestureDetector(
        onTap: _phase == _Phase.greeting ? _navigateToMain : null,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgDark, Color(0xFF121526), AppColors.bgMedium],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: _phase == _Phase.loading ? _buildLoading() : _buildGreeting(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      key: const ValueKey('loading'),
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
    );
  }

  Widget _buildGreeting() {
    final subtitle = _isFirstLogin
        ? 'La tua avventura da collezionista inizia ora. 🎴'
        : _returningMessages[DateTime.now().millisecond % _returningMessages.length];

    return Center(
      key: const ValueKey('greeting'),
      child: FadeTransition(
        opacity: _greetingFade,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgMedium,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.5),
                      blurRadius: 40,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.style, size: 54, color: AppColors.gold),
              ),
              const SizedBox(height: 36),
              Text(
                _isFirstLogin ? 'Benvenuto,' : 'Bentornato,',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.gold, Color(0xFFFFE88A)],
                ).createShader(bounds),
                child: Text(
                  _greetingName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(height: 1, width: 80, color: AppColors.gold.withValues(alpha: 0.4)),
              const SizedBox(height: 24),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.6),
              ),
              const SizedBox(height: 64),
              const Text(
                'Tocca per continuare',
                style: TextStyle(color: AppColors.textHint, fontSize: 12, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
