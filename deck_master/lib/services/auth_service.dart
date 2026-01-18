import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static const String _offlineKey = 'is_offline_mode';
  bool _isGoogleInitialized = false;

  Stream<User?> get user => _auth.authStateChanges();

  Future<void> _ensureGoogleInitialized() async {
    if (!_isGoogleInitialized) {
      await _googleSignIn.initialize();
      _isGoogleInitialized = true;
    }
  }

  Future<bool> isOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_offlineKey) ?? false;
  }

  Future<void> setOfflineMode(bool isOffline) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineKey, isOffline);
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();
      final googleUser = await _googleSignIn.authenticate();

      final googleAuth = await googleUser.authentication;
      
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await setOfflineMode(false);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: [${e.code}] ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      if (e.toString().contains('16')) {
        debugPrint('TIP: Check if SHA-1 fingerprint is correctly registered in Firebase Console.');
      }
      return null;
    }
  }

  Future<UserCredential?> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final AuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        final userCredential = await _auth.signInWithCredential(credential);
        await setOfflineMode(false);
        return userCredential;
      }
      return null;
    } catch (e) {
      debugPrint('Error signing in with Facebook: $e');
      return null;
    }
  }

  Future<void> signInOffline() async {
    await setOfflineMode(true);
    if (_auth.currentUser != null) {
      await _auth.signOut();
    }
  }

  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      await setOfflineMode(false);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Sign-In Error: $e');
      rethrow;
    }
  }

  Future<UserCredential?> registerWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await setOfflineMode(false);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Registration Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Error during Google signOut: $e');
    }

    try {
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint('Error during Facebook logOut: $e');
    }

    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error during Firebase signOut: $e');
    }

    await setOfflineMode(false);
  }
}
