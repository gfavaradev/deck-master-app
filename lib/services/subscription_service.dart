import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// Gestisce abbonamento Pro
class SubscriptionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _users => _db.collection('users');

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Tetto di attesa su ogni lettura del documento utente.
  ///
  /// La persistence nativa di Firestore è disabilitata (SQLite fa da cache), e
  /// senza persistence una `get()` offline — o rifiutata da App Check — **non
  /// ritorna e non lancia**: resta appesa a ritentare. Non essendoci nessun
  /// errore da intercettare, il `catch` non scattava e le pagine che aspettano
  /// questo controllo restavano sullo spinner per sempre
  /// (`ai_deck_builder_page`, `card_scanner_page`, il paywall).
  static const Duration readTimeout = Duration(seconds: 8);

  static const String _kProCachePrefix = 'pro_status_';

  // ── Lettura stato utente ───────────────────────────────────────────────────

  Future<UserModel?> getCurrentUserModel() async {
    final uid = _currentUid;
    if (uid == null) return null;
    try {
      final doc = await _users.doc(uid).get().timeout(readTimeout);
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data() as Map<String, dynamic>);
    } catch (_) {
      // Timeout, rete assente o documento malformato: nessuno stato utente.
      return null;
    }
  }

  /// True se l'utente ha il Pro attivo.
  ///
  /// L'ultimo valore letto con successo viene messo in cache per uid: se la
  /// lettura fallisce (offline, timeout, App Check) si ripiega su quello invece
  /// di degradare a "free" un abbonato che sta solo viaggiando in metro.
  /// L'autorizzazione vera resta su Firestore, scritta solo dal backend: questa
  /// è una cache di comodo per la UI, non una fonte di verità.
  Future<bool> currentUserHasPro() async {
    final uid = _currentUid;
    if (uid == null) return false;

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final cacheKey = '$_kProCachePrefix$uid';

    try {
      final doc = await _users.doc(uid).get().timeout(readTimeout);
      final model = doc.exists
          ? UserModel.fromFirestore(doc.data() as Map<String, dynamic>)
          : null;
      final hasPro = model?.hasProAccess ?? false;
      await prefs?.setBool(cacheKey, hasPro);
      return hasPro;
    } catch (_) {
      return prefs?.getBool(cacheKey) ?? false;
    }
  }

  /// Svuota la cache locale dello stato Pro per [uid]. Da chiamare al logout,
  /// altrimenti l'account successivo sullo stesso dispositivo erediterebbe il
  /// ripiego di quello precedente.
  static Future<void> clearProCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kProCachePrefix$uid');
    } catch (_) {}
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
