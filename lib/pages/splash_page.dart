import 'dart:async';

import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_layout.dart';
import 'login_page.dart';
import 'onboarding_page.dart';
import '../services/app_preferences.dart';
import '../services/data_repository.dart';
import '../services/startup_gate.dart';
import '../theme/app_colors.dart';
import '../widgets/booster_intro_animation.dart';

enum _Phase { loading, greeting }

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  final DataRepository _repo = DataRepository();

  _Phase _phase = _Phase.loading;
  String _greetingName = '';
  bool _isFirstLogin = false;
  bool _navigating = false;
  String? _updatedVersion;

  late AnimationController _greetingController;
  late Animation<double> _greetingFade;

  // Si completa quando l'animazione di apertura booster ha finito di girare.
  // Tutte le navigazioni fuori dallo splash aspettano questo, cosi l'intro
  // gioca sempre per intero anche se l'auth check finisce prima.
  final Completer<void> _introDone = Completer<void>();
  Future<void> get _introFinished => _introDone.future;

  static const String _lastVersionKey = 'app_last_version';

  // Returning messages are now handled via l10n in _buildGreeting
  static List<String> _getReturningMessages(AppLocalizations l10n) => [
    l10n.splashReturning1,
    l10n.splashReturning2,
    l10n.splashReturning3,
    l10n.splashReturning4,
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
    } catch (e) { // ignore: empty_catches
    }
    return null;
  }

  Future<void> _checkAuth() async {
    // On Windows desktop, Firebase Auth restores credentials asynchronously from
    // a local JSON file. Using currentUser directly can return null before restoration
    // completes. authStateChanges().first waits for the first emitted auth state.
    // Prova prima il valore sincrono (già disponibile in cache locale)
    // Se non c'è, aspetta fino a 8s per il ripristino asincrono (Windows/desktop)
    User? user = FirebaseAuth.instance.currentUser;
    user ??= await FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 8), onTimeout: () => null);

    // Prima apertura assoluta: mostra onboarding indipendentemente dall'auth state
    if (!AppPreferences.instance.isOnboardingDone) {
      await _introFinished;
      if (!mounted) return;
      _navigateToOnboarding(isLoggedIn: user != null);
      return;
    }

    if (user != null) {
      _checkAppVersion().then((v) { if (mounted) _updatedVersion = v; });

      // Solo SharedPreferences — velocissimo (~10ms)
      final prefs = await SharedPreferences.getInstance();
      final key = 'first_login_done_${user.uid}';
      final hasLoggedInBefore = prefs.getBool(key) ?? false;
      await prefs.setBool(key, true);

      final rawName = user.displayName ?? user.email?.split('@').first;
      final namePart = rawName?.split(' ').first ?? '';

      if (!mounted) return;

      final greetingName = namePart.isNotEmpty
          ? namePart
          : AppLocalizations.of(context)!.splashDefaultCollector;

      // L'intro booster gira sempre per intero prima di mostrare il greeting.
      await _introFinished;
      if (!mounted) return;

      setState(() {
        _phase = _Phase.greeting;
        _greetingName = greetingName;
        _isFirstLogin = !hasLoggedInBefore;
      });
      _greetingController.forward();

      // Il sync parte solo ORA, non in parallelo all'intro: gira sull'isolate
      // principale (getAllCards da SQLite, streaming dei prezzi CardTrader in
      // batch) e sovrapposto all'animazione faceva perdere frame proprio nelle
      // fasi con più movimento. La schermata di saluto invece è statica dopo
      // la dissolvenza, quindi lì lo stesso lavoro non si vede.
      final syncFuture = _repo.syncOnLogin()
          .timeout(const Duration(seconds: 20))
          .catchError((_) {});

      // Aspetta il greeting (1.8s) e poi il sync — così un account esistente
      // vede subito le proprie collezioni in home invece di un breve stato
      // vuoto. Il cap è più basso del timeout del sync: se è più lento di così
      // prosegue in background invece di allungare ancora lo splash, dato che
      // ora parte 7s più tardi di prima.
      await Future.delayed(const Duration(milliseconds: 1800));
      await syncFuture.timeout(const Duration(seconds: 6), onTimeout: () {});
      _navigateToMain(showTutorial: _isFirstLogin);
    } else {
      await _introFinished;
      if (!mounted) return;
      _navigateToLogin();
    }
  }

  void _navigateToMain({bool showTutorial = false}) {
    if (_navigating || !mounted) return;
    _navigating = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => MainLayout(
          updateNotification: _updatedVersion,
          showTutorial: showTutorial,
        ),
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

  void _navigateToOnboarding({required bool isLoggedIn}) {
    if (!mounted) return;
    // Catturiamo il NavigatorState prima del pushReplacement: dopo la sostituzione
    // SplashPage viene smontata (mounted=false), quindi _navigateToMain/_navigateToLogin
    // non funzionerebbero. Il NavigatorState rimane valido per tutta la durata dell'app.
    final nav = Navigator.of(context);
    nav.pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => OnboardingPage(
          onComplete: () {
            if (isLoggedIn) {
              nav.pushReplacement(PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 500),
                pageBuilder: (_, _, _) => MainLayout(
                  updateNotification: _updatedVersion,
                  showTutorial: true,
                ),
                transitionsBuilder: (_, anim, _, child) => FadeTransition(
                  opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                  child: child,
                ),
              ));
            } else {
              nav.pushReplacement(PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (_, _, _) => const LoginPage(),
                transitionsBuilder: (_, anim, _, child) => FadeTransition(
                  opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                  child: child,
                ),
              ));
            }
          },
        ),
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
      // Niente SafeArea attorno alla scena: il padding di sistema in basso
      // accorciava l'area di disegno, e siccome l'intro è centrata in quella
      // box la si vedeva spostata verso l'alto rispetto allo schermo. Il
      // greeting si prende la sua SafeArea da sé.
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: _phase == _Phase.loading ? _buildLoading() : _buildGreeting(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return SplashIntro(
      key: const ValueKey('loading'),
      onCompleted: () {
        if (!_introDone.isCompleted) _introDone.complete();
        // Sblocca gli init pesanti tenuti fuori dai frame dell'animazione.
        StartupGate.open();
      },
    );
  }

  Widget _buildGreeting() {
    final l10n = AppLocalizations.of(context)!;
    final returningMessages = _getReturningMessages(l10n);
    final subtitle = _isFirstLogin
        ? l10n.splashFirstLoginSubtitle
        : returningMessages[DateTime.now().millisecond % returningMessages.length];

    return SafeArea(
      key: const ValueKey('greeting'),
      child: Center(
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
                  _isFirstLogin ? l10n.splashWelcomeFirst : l10n.splashWelcomeBack,
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
                      fontFamily: 'Caveat',
                      color: Colors.white,
                      fontSize: 58,
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
                Text(
                  l10n.splashTapToContinue,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 12, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
