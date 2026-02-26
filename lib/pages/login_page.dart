import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';
import 'main_layout.dart';
import 'package:google_fonts/google_fonts.dart';

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

  /// Su mobile (Android/iOS) usiamo solo social login
  bool get _isSocialOnly => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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
        try {
          await _repo.syncOnLogin();
        } catch (e) {
          debugPrint('Sync on login failed: $e');
        }
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainLayout()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Accesso annullato o non riuscito')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage;
        final msg = e.toString();
        if (msg.contains('user-not-found')) {
          errorMessage = 'Utente non trovato';
        } else if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
          errorMessage = 'Credenziali non valide';
        } else if (msg.contains('email-already-in-use')) {
          errorMessage = 'Email già in uso';
        } else if (msg.contains('popup-closed-by-user') || msg.contains('cancelled')) {
          errorMessage = 'Accesso annullato';
        } else if (msg.contains('popup-blocked')) {
          errorMessage = 'Popup bloccato dal browser. Consenti i popup per questo sito.';
        } else if (msg.contains('unauthorized-domain')) {
          errorMessage = 'Dominio non autorizzato in Firebase Console';
        } else if (msg.contains('network')) {
          errorMessage = 'Errore di rete. Controlla la connessione.';
        } else {
          errorMessage = 'Errore: $msg';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci email e password')),
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
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade900, Colors.blue.shade600],
          ),
        ),
        child: _isSocialOnly ? _buildSocialOnlyLayout() : _buildFullLayout(),
      ),
    );
  }

  // ─── Layout solo social (Android / iOS) ────────────────────────────────────

  Widget _buildSocialOnlyLayout() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Image.asset('assets/icon/logo_dm_carte_collezionabili_1.png', height: 120),
            const SizedBox(height: 16),
            Text(
              'Deck Master',
              style: GoogleFonts.poppins(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'La tua collezione di carte',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Accedi per continuare',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.white54,
              ),
            ),
            const Spacer(flex: 2),
            if (_isLoading)
              const CircularProgressIndicator(color: Colors.white)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSocialButton(
                    svgAsset: 'assets/icon/google.svg',
                    onPressed: () => _handleSignIn(_authService.signInWithGoogle),
                  ),
                  // TODO: riabilitare quando Facebook app è in modalità Live
                  // const SizedBox(width: 24),
                  // _buildSocialButton(
                  //   svgAsset: 'assets/icon/facebook.svg',
                  //   onPressed: () => _handleSignIn(_authService.signInWithFacebook),
                  // ),
                ],
              ),
            const Spacer(flex: 1),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => _handleSignIn(() async {
                        await _authService.signInOffline();
                        return true;
                      }),
              child: const Text(
                'Continua Offline',
                style: TextStyle(
                  color: Colors.white,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── Layout completo con email/password (Web / Desktop) ────────────────────

  Widget _buildFullLayout() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 100),
            Image.asset('assets/icon/logo_dm_carte_collezionabili_1.png', height: 130),
            const SizedBox(height: 20),
            Text(
              'Deck Master',
              style: GoogleFonts.poppins(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Accedi per continuare',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 42),
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
                    _isLogin ? 'Accedi' : 'Registrati',
                    style: GoogleFonts.poppins(
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
                          _isLogin ? 'ACCEDI' : 'REGISTRATI',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin
                          ? 'Non hai un account? Registrati'
                          : 'Hai già un account? Accedi',
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
                    'Oppure continua con',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const Expanded(child: Divider(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSocialButton(
                  svgAsset: 'assets/icon/google.svg',
                  onPressed: () => _handleSignIn(_authService.signInWithGoogle),
                ),
                // TODO: riabilitare quando Facebook app è in modalità Live
                // const SizedBox(width: 20),
                // _buildSocialButton(
                //   svgAsset: 'assets/icon/facebook.svg',
                //   onPressed: () => _handleSignIn(_authService.signInWithFacebook),
                // ),
              ],
            ),
            const SizedBox(height: 30),
            TextButton(
              onPressed: () => _handleSignIn(() async {
                await _authService.signInOffline();
                return true;
              }),
              child: const Text(
                'Continua Offline',
                style: TextStyle(color: Colors.white, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 50),
          ],
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
