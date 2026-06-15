import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

/// Gestisce abbonamento Pro
class SubscriptionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _users => _db.collection('users');

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  // ── Lettura stato utente ───────────────────────────────────────────────────

  Future<UserModel?> getCurrentUserModel() async {
    final uid = _currentUid;
    if (uid == null) return null;
    try {
      final doc = await _users.doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data() as Map<String, dynamic>);
    } catch (_) { // ignore: empty_catches
      return null;
    }
  }

  Future<bool> currentUserHasPro() async {
    final user = await getCurrentUserModel();
    return user?.hasProAccess ?? false;
  }

  // ── Gestione Pro (admin) ───────────────────────────────────────────────────

  /// Attiva Pro manualmente per un utente (senza scadenza)
  Future<void> activateProManually(String uid) async {
    await _users.doc(uid).set({
      'isPro': true,
      'proSource': 'manual',
      'proExpiresAt': null,
    }, SetOptions(merge: true));
  }

  /// Disattiva Pro per un utente
  Future<void> deactivateProManually(String uid) async {
    await _users.doc(uid).set({
      'isPro': false,
      'proSource': null,
      'proExpiresAt': null,
    }, SetOptions(merge: true));
  }

  /// Attiva Pro con scadenza specifica (per abbonamenti IAP futuri)
  Future<void> activateProWithExpiry(String uid, DateTime expiresAt, {String source = 'iap'}) async {
    await _users.doc(uid).set({
      'isPro': true,
      'proSource': source,
      'proExpiresAt': expiresAt.toIso8601String(),
    }, SetOptions(merge: true));
  }

  // ── Tutti gli utenti (per admin) ──────────────────────────────────────────

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _users.get();
    final list = <UserModel>[];
    for (final doc in snap.docs) {
      try {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        // Garantisce uid anche se mancante nel documento
        data.putIfAbsent('uid', () => doc.id);
        data.putIfAbsent('email', () => '');
        data.putIfAbsent('createdAt', () => DateTime.now().toIso8601String());
        list.add(UserModel.fromFirestore(data));
      } catch (_) { // ignore: empty_catches
        // Documento malformato — skip
      }
    }
    return list;
  }

  Future<List<UserModel>> getProUsers() async {
    final snap = await _users.where('isPro', isEqualTo: true).get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data() as Map<String, dynamic>))
        .toList();
  }
}
