import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:deck_master/services/user_service.dart';
import 'package:deck_master/services/database_helper.dart';
import 'package:deck_master/services/sync_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final UserService _userService = UserService();
  static const String _offlineKey = 'is_offline_mode';
  bool _isGoogleInitialized = false;

  // Platform support checks
  bool get isFacebookAuthSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  bool get isAppleSignInSupported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  Stream<User?> get user => _auth.authStateChanges();

  String? get currentUserId => _auth.currentUser?.uid;

  // Web client ID from google-services.json (client_type: 3)
  // Required by Android Credential Manager to request an ID token for Firebase Auth
  static const String _googleServerClientId =
      '983642109584-pm5dfs2r7qh11ts79vve7vm46kkqqpe6.apps.googleusercontent.com';

  Future<void> _ensureGoogleInitialized() async {
    if (!_isGoogleInitialized) {
      await _googleSignIn.initialize(serverClientId: _googleServerClientId);
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
      UserCredential userCredential;

      if (kIsWeb) {
        // Web: signInWithPopup apre un popup OAuth (supportato da firebase_auth_web)
        final googleProvider = GoogleAuthProvider();
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else if (!kIsWeb && Platform.isWindows) {
        // Windows desktop: apre il browser per OAuth
        final googleProvider = GoogleAuthProvider();
        userCredential = await _auth.signInWithProvider(googleProvider);
      } else {
        // Mobile (Android / iOS): use GoogleSignIn package
        await _ensureGoogleInitialized();
        final googleUser = await _googleSignIn.authenticate();
        final googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
        userCredential = await _auth.signInWithCredential(credential);
      }

      await setOfflineMode(false);

      // Create or update user document in Firestore
      final user = userCredential.user;
      if (user != null) {
        final userExists = await _userService.userExists(user.uid);
        if (!userExists) {
          await _userService.createUser(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName,
            photoUrl: user.photoURL,
          );
        } else {
          await _userService.updateLastLogin(user.uid);
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  Future<UserCredential?> signInWithFacebook() async {
    if (!isFacebookAuthSupported) {
      debugPrint('Facebook authentication is not supported on this platform (${kIsWeb ? 'Web' : Platform.operatingSystem})');
      return null;
    }

    try {
      final LoginResult result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final AuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        final userCredential = await _auth.signInWithCredential(credential);
        await setOfflineMode(false);

        // Create or update user document in Firestore
        final user = userCredential.user;
        if (user != null) {
          final userExists = await _userService.userExists(user.uid);
          if (!userExists) {
            await _userService.createUser(
              uid: user.uid,
              email: user.email ?? '',
              displayName: user.displayName,
              photoUrl: user.photoURL,
            );
          } else {
            await _userService.updateLastLogin(user.uid);
          }
        }

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

      // Update last login
      final user = userCredential.user;
      if (user != null) {
        await _userService.updateLastLogin(user.uid);
      }

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

      // Create user document in Firestore with default 'user' role
      final user = userCredential.user;
      if (user != null) {
        await _userService.createUser(
          uid: user.uid,
          email: user.email ?? email,
          displayName: user.displayName,
          photoUrl: user.photoURL,
        );
      }

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
    SyncService().stopListening();

    // GoogleSignIn package is only used on mobile — skip on web
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Error during Google signOut: $e');
      }
    }

    if (isFacebookAuthSupported) {
      try {
        await FacebookAuth.instance.logOut();
      } catch (e) {
        debugPrint('Error during Facebook logOut: $e');
      }
    }

    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error during Firebase signOut: $e');
    }

    // SQLite is not available on web — skip local data clear
    if (!kIsWeb) {
      try {
        final dbHelper = DatabaseHelper();
        await dbHelper.clearUserData();
        debugPrint('User personal data cleared on logout (albums, cards, decks)');
      } catch (e) {
        debugPrint('Error clearing user data: $e');
      }
    }

    await setOfflineMode(false);
  }

  /// Check if current user is administrator
  Future<bool> isCurrentUserAdmin() async {
    return await _userService.isCurrentUserAdmin();
  }

  /// Get UserService instance for advanced user management
  UserService get userService => _userService;

  /// Delete the current user's account and all associated data
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    // Stop real-time listeners before deleting
    SyncService().stopListening();

    // Delete Firestore subcollections and user document
    try {
      final firestore = FirebaseFirestore.instance;
      for (final col in ['decks', 'albums', 'cards']) {
        final docs = await firestore.collection('users/$uid/$col').get();
        for (final doc in docs.docs) {
          await doc.reference.delete();
        }
      }
      await _userService.deleteUser(uid);
    } catch (e) {
      debugPrint('Error deleting Firestore data: $e');
    }

    // Clear local SQLite data
    if (!kIsWeb) {
      try {
        final dbHelper = DatabaseHelper();
        await dbHelper.clearUserData();
      } catch (e) {
        debugPrint('Error clearing local data: $e');
      }
    }

    // Sign out from social providers
    if (!kIsWeb) {
      try { await _googleSignIn.signOut(); } catch (_) {}
    }
    if (isFacebookAuthSupported) {
      try { await FacebookAuth.instance.logOut(); } catch (_) {}
    }

    // Delete Firebase Auth account (may throw requires-recent-login)
    await user.delete();

    await setOfflineMode(false);
  }
}
