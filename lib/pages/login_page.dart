import '../l10n/app_localizations.dart';
import 'dart:io' show Platform, InternetAddress;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import 'main_layout.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;
  // null = checking, true = offline, false = online
  bool? _isOffline;

  /// Su mobile (Android/iOS) usiamo solo social login
  bool get _isSocialOnly => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    setState(() => _isOffline = null); // mostra spinner mentre verifica
    bool offline = true;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      offline = result.isEmpty || result[0].rawAddress.isEmpty;
    } catch (_) {
      offline = true;
    }
    if (mounted) setState(() => _isOffline = offline);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignIn(Future<dynamic> Function() signInMethod) async {
    setState(() => _isLoading = true);
    try {
      final result = await signInMethod();
      if (result != null || signInMethod.toString().contains('signInOffline')) {
        // Aspetta il sync (con timeout) prima di navigare, così un account
        // esistente vede subito le proprie collezioni sbloccate in home.
        await _repo.syncOnLogin(isManualLogin: true)
            .timeout(const Duration(seconds: 20))
            .catchError((_) {});
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainLayout()),
          );
        }
      } else {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.msgLoginCancelled)),
          );
        }
      }
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        String errorMessage;
        final msg = e.toString();
        if (msg.contains('user-not-found')) {
          errorMessage = l10n.msgUserNotFound;
        } else if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
          errorMessage = l10n.msgInvalidCredentials;
        } else if (msg.contains('email-already-in-use')) {
          errorMessage = l10n.msgEmailInUse;
        } else if (msg.contains('popup-closed-by-user') || msg.contains('cancelled')) {
          errorMessage = l10n.msgLoginCancelledShort;
        } else if (msg.contains('popup-blocked')) {
          errorMessage = l10n.msgPopupBlocked;
        } else if (msg.contains('unauthorized-domain')) {
          errorMessage = l10n.msgUnauthorizedDomain;
        } else if (msg.contains('network')) {
          errorMessage = l10n.msgNetworkError;
        } else {
          errorMessage = l10n.msgErrorGeneric(msg);
        }
        // Segna come offline dopo un errore di rete durante il login
        if (msg.contains('network') || msg.contains('timeout') || msg.contains('socket')) {
          setState(() => _isOffline = true);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _emailAuth() {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.msgInsertEmailPassword)),
      );
      return;
    }

    if (_isLogin) {
      _handleSignIn(() => _authService.signInWithEmailAndPassword(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          ));
    } else {
      _handleSignIn(() => _authService.registerWithEmailAndPassword(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: true,
        child: Stack(
          children: [
            // Base gradient
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgDark, Color(0xFF121526), AppColors.bgMedium],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // Glow blu/viola in alto (dietro il logo)
            Positioned(
              top: -70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [AppColors.glowBlue, Color(0x224D7FFF), Colors.transparent],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Glow viola a sinistra (metà pagina)
            Positioned(
              top: 220,
              left: -55,
              child: Container(
                width: 190,
                height: 190,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.glowPurple, Colors.transparent],
                  ),
                ),
              ),
            ),
            // Glow dorato in basso a destra
            Positioned(
              bottom: -60,
              right: -60,
              child: Container(
                width: 230,
                height: 230,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.glowGold, Colors.transparent],
                  ),
                ),
              ),
            ),
            // Contenuto
            SizedBox(
              width: double.infinity,
              child: _isSocialOnly ? _buildSocialOnlyLayout() : _buildFullLayout(),
            ),
          ],
        )
      ),
    );
  }

  // ─── Layout solo social (Android / iOS) ────────────────────────────────────

  Widget _buildSocialOnlyLayout() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Image.asset('assets/icon/dm_logo_no_white.png', height: 160),
          const SizedBox(height: 16),
          const Text(
            'Deck Master',
            style: TextStyle(
              fontFamily: 'Caveat',
              fontSize: 50,
              fontWeight: FontWeight.w600,
              color: AppColors.splashGold,
            ),
          ),
          Text(
            l10n.loginSubtitle.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.splashGoldSoft,
              letterSpacing: 2.2,
            ),
          ),
          const Spacer(flex: 2),
          if (_isLoading)
            const CircularProgressIndicator(color: AppColors.gold)
          else if (_isOffline == null)
            // Verifica connessione in corso
            const CircularProgressIndicator(color: AppColors.gold)
          else if (_isOffline == true)
            _buildOfflinePanel(l10n)
          else ...[
            Text(
              l10n.loginAccessToContinue.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.splashGoldSoft,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildSocialButton(
              svgAsset: 'assets/icon/google.svg',
              onPressed: () => _handleSignIn(_authService.signInWithGoogle),
            ),
          ],
          const Spacer(flex: 1),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Pannello offline (sostituisce il pulsante Google) ─────────────────────

  Widget _buildOfflinePanel(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 36),
        const SizedBox(height: 12),
        Text(
          l10n.loginNoInternetTitle,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.loginNoInternetBody,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Riprova connessione
            OutlinedButton.icon(
              onPressed: _checkConnectivity,
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              label: Text(
                l10n.loginBtnRetry,
                style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins'),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(width: 16),
            // Accesso offline
            ElevatedButton.icon(
              onPressed: () => _handleSignIn(() async {
                await _authService.signInOffline();
                return true;
              }),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                l10n.loginBtnOfflineAccess,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Layout completo con email/password (Web / Desktop) ────────────────────

  Widget _buildFullLayout() {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 100),
              Image.asset('assets/icon/dm_logo_no_white.png', height: 170),
              const SizedBox(height: 20),
              const Text(
                'Deck Master',
                style: TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: 52,
                  fontWeight: FontWeight.w600,
                  color: AppColors.splashGold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.loginAccessToContinue.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.splashGoldSoft,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 42),
              // Form email/password — visibile solo online
              if (_isOffline != true) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isLogin ? l10n.btnLogin : l10n.btnRegister,
                        style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 25),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          hintText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      if (_isLoading)
                        const CircularProgressIndicator()
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _emailAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade900,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _isLogin ? l10n.loginBtnAccedi : l10n.loginBtnRegistrati,
                              style: TextStyle(fontFamily: 'Poppins',fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => setState(() => _isLogin = !_isLogin),
                        child: Text(
                          _isLogin ? l10n.loginNoAccount : l10n.loginHasAccount,
                          style: TextStyle(color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Expanded(child: Divider(color: Colors.white70)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        l10n.loginOrContinueWith,
                        style: TextStyle(fontFamily: 'Poppins',color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    const Expanded(child: Divider(color: Colors.white70)),
                  ],
                ),
                const SizedBox(height: 25),
                if (_isLoading)
                  const CircularProgressIndicator(color: AppColors.gold)
                else if (_isOffline == null)
                  const CircularProgressIndicator(color: AppColors.gold)
                else
                  _buildSocialButton(
                    svgAsset: 'assets/icon/google.svg',
                    onPressed: () => _handleSignIn(_authService.signInWithGoogle),
                  ),
              ] else
                _buildOfflinePanel(l10n),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required String svgAsset,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        width: 60,
        height: 60,
        child: SvgPicture.asset(svgAsset),
      ),
    );
  }
}
