import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/subscription_model.dart';

/// Gestisce abbonamento Pro e donazioni utente
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

  Future<DonationTier> getCurrentDonationTier() async {
    final user = await getCurrentUserModel();
    return user?.donationTier ?? DonationTier.none;
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

  // ── Donazioni ─────────────────────────────────────────────────────────────

  /// Registra una donazione e aggiorna il tier (chiamata da admin)
  Future<DonationTier> recordDonation(
    String uid,
    double amount, {
    String? wallOfFameNickname,
  }) async {
    final doc = await _users.doc(uid).get();
    final current = (doc.data() as Map<String, dynamic>?)?['totalDonated'];
    final currentTotal = (current as num?)?.toDouble() ?? 0.0;
    final newTotal = currentTotal + amount;
    final newTier = DonationTier.fromTotal(newTotal);

    final updates = <String, dynamic>{
      'totalDonated': newTotal,
      'donationTier': newTier.name,
    };

    if (newTier == DonationTier.secretRare && wallOfFameNickname != null) {
      updates['wallOfFameNickname'] = wallOfFameNickname;
    }

    await _users.doc(uid).set(updates, SetOptions(merge: true));
    return newTier;
  }

  /// Rimuove una donazione (correzione admin)
  Future<DonationTier> removeDonation(String uid, double amount) async {
    final doc = await _users.doc(uid).get();
    final current = (doc.data() as Map<String, dynamic>?)?['totalDonated'];
    final currentTotal = (current as num?)?.toDouble() ?? 0.0;
    final newTotal = (currentTotal - amount).clamp(0.0, double.infinity);
    final newTier = DonationTier.fromTotal(newTotal);

    await _users.doc(uid).set({
      'totalDonated': newTotal,
      'donationTier': newTier.name,
    }, SetOptions(merge: true));
    return newTier;
  }

  // ── Wall of Fame ──────────────────────────────────────────────────────────

  /// Restituisce tutti i donatori Secret Rare (Wall of Fame)
  Future<List<Map<String, String>>> getWallOfFame() async {
    try {
      final snap = await _users
          .where('donationTier', isEqualTo: 'secretRare')
          .get();
      return snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {
          'nickname': (data['wallOfFameNickname'] as String?)
              ?? (data['displayName'] as String?)
              ?? 'Fondatore Anonimo',
          'uid': d.id,
        };
      }).toList();
    } catch (_) { // ignore: empty_catches
      return [];
    }
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
