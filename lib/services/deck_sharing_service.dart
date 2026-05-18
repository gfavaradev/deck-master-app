import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DeckSharingService {
  static final _db = FirebaseFirestore.instance;
  static final _col = _db.collection('public_decks');

  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _generateCode() {
    final rand = Random.secure();
    return List.generate(6, (_) => _chars[rand.nextInt(_chars.length)]).join();
  }

  /// Pubblica il deck su Firestore e restituisce il codice breve.
  static Future<String> publishDeck({
    required String deckName,
    required String collectionKey,
    required String collectionName,
    required List<Map<String, dynamic>> cards,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ownerName = FirebaseAuth.instance.currentUser?.displayName ?? 'Anonimo';
    if (uid == null) throw Exception('Utente non autenticato');

    final totalCards = cards.fold<int>(0, (s, c) => s + ((c['quantity'] as int?) ?? 1));

    String code;
    int attempts = 0;
    do {
      code = _generateCode();
      attempts++;
      if (attempts > 10) throw Exception('Impossibile generare codice univoco');
    } while (await _col.doc(code).get().then((d) => d.exists));

    await _col.doc(code).set({
      'shortCode': code,
      'deckName': deckName,
      'collectionKey': collectionKey,
      'collectionName': collectionName,
      'ownerUid': uid,
      'ownerName': ownerName,
      'cards': cards,
      'totalCards': totalCards,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return code;
  }

  /// Recupera un deck condiviso per codice. Restituisce null se non trovato.
  static Future<Map<String, dynamic>?> fetchDeck(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return null;
    final doc = await _col.doc(clean).get();
    if (!doc.exists) return null;
    return {'shortCode': clean, ...doc.data()!};
  }

  /// Elimina un deck condiviso (solo il proprietario può farlo).
  static Future<void> deleteDeck(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final doc = await _col.doc(code).get();
    if (!doc.exists) return;
    if (doc.data()?['ownerUid'] != uid) throw Exception('Non autorizzato');
    await _col.doc(code).delete();
  }
}
