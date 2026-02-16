import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';
import '../models/collection_model.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================================
  // Yu-Gi-Oh Catalog Methods
  // ============================================================

  /// Get catalog metadata (version, total chunks, etc.)
  Future<Map<String, dynamic>?> getCatalogMetadata() async {
    try {
      final doc = await _firestore.collection('yugioh_catalog').doc('metadata').get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('Error getting catalog metadata: $e');
      return null;
    }
  }

  /// Fetch Yu-Gi-Oh catalog from Firestore chunks.
  /// Returns cards in the same format as the old ApiService for compatibility
  /// with DatabaseHelper.insertYugiohCards().
  Future<List<Map<String, dynamic>>> fetchYugiohCatalog({
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      // Get metadata to know total chunks
      final metadata = await getCatalogMetadata();
      if (metadata == null) {
        throw Exception('Catalog metadata not found in Firestore');
      }

      final int totalChunks = metadata['totalChunks'] ?? 0;
      if (totalChunks == 0) {
        throw Exception('No catalog chunks available');
      }

      final List<Map<String, dynamic>> allCards = [];

      for (int i = 1; i <= totalChunks; i++) {
        final chunkId = 'chunk_${i.toString().padLeft(3, '0')}';
        final doc = await _firestore
            .collection('yugioh_catalog')
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .get();

        if (doc.exists && doc.data() != null) {
          final List<dynamic> cards = doc.data()!['cards'] ?? [];
          for (var card in cards) {
            allCards.add(Map<String, dynamic>.from(card as Map));
          }
        }

        onProgress?.call(i, totalChunks);
      }

      return allCards;
    } catch (e) {
      throw Exception('Error fetching Yu-Gi-Oh catalog from Firestore: $e');
    }
  }

  // ============================================================
  // User Collections Methods
  // ============================================================

  Future<void> setCollections(String userId, List<CollectionModel> collections) async {
    final batch = _firestore.batch();
    for (var col in collections) {
      final ref = _firestore
          .collection('users')
          .doc(userId)
          .collection('collections')
          .doc(col.key);
      batch.set(ref, {
        'name': col.name,
        'isUnlocked': col.isUnlocked,
      });
    }
    await batch.commit();
  }

  Future<void> setCollectionUnlocked(String userId, String collectionKey, bool unlocked) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('collections')
        .doc(collectionKey)
        .set({'isUnlocked': unlocked}, SetOptions(merge: true));
  }

  Future<List<CollectionModel>> getCollections(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('collections')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return CollectionModel(
        key: doc.id,
        name: data['name'] ?? doc.id,
        isUnlocked: data['isUnlocked'] ?? false,
      );
    }).toList();
  }

  // ============================================================
  // User Albums Methods
  // ============================================================

  Future<String> insertAlbum(String userId, AlbumModel album) async {
    final ref = await _firestore
        .collection('users')
        .doc(userId)
        .collection('albums')
        .add({
      'name': album.name,
      'collection': album.collection,
      'maxCapacity': album.maxCapacity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateAlbum(String userId, String firestoreId, AlbumModel album) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('albums')
        .doc(firestoreId)
        .update({
      'name': album.name,
      'collection': album.collection,
      'maxCapacity': album.maxCapacity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAlbum(String userId, String firestoreId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('albums')
        .doc(firestoreId)
        .delete();
  }

  Future<List<Map<String, dynamic>>> getAlbums(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('albums')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'firestoreId': doc.id,
        'name': data['name'],
        'collection': data['collection'],
        'maxCapacity': data['maxCapacity'],
      };
    }).toList();
  }

  // ============================================================
  // User Cards Methods
  // ============================================================

  Future<String> insertCard(String userId, CardModel card, {String? albumFirestoreId}) async {
    final ref = await _firestore
        .collection('users')
        .doc(userId)
        .collection('cards')
        .add({
      'catalogId': card.catalogId,
      'name': card.name,
      'serialNumber': card.serialNumber,
      'collection': card.collection,
      'albumId': card.albumId,
      'albumFirestoreId': albumFirestoreId,
      'type': card.type,
      'rarity': card.rarity,
      'description': card.description,
      'quantity': card.quantity,
      'value': card.value,
      'imageUrl': card.imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateCard(String userId, String firestoreId, CardModel card, {String? albumFirestoreId}) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('cards')
        .doc(firestoreId)
        .update({
      'catalogId': card.catalogId,
      'name': card.name,
      'serialNumber': card.serialNumber,
      'collection': card.collection,
      'albumId': card.albumId,
      'albumFirestoreId': albumFirestoreId,
      'type': card.type,
      'rarity': card.rarity,
      'description': card.description,
      'quantity': card.quantity,
      'value': card.value,
      'imageUrl': card.imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCard(String userId, String firestoreId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('cards')
        .doc(firestoreId)
        .delete();
  }

  Future<List<Map<String, dynamic>>> getCards(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('cards')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'firestoreId': doc.id,
        'catalogId': data['catalogId'],
        'name': data['name'],
        'serialNumber': data['serialNumber'],
        'collection': data['collection'],
        'albumId': data['albumId'],
        'albumFirestoreId': data['albumFirestoreId'],
        'type': data['type'],
        'rarity': data['rarity'],
        'description': data['description'],
        'quantity': data['quantity'],
        'value': (data['value'] as num?)?.toDouble(),
        'imageUrl': data['imageUrl'],
      };
    }).toList();
  }

  // ============================================================
  // User Decks Methods
  // ============================================================

  Future<String> insertDeck(String userId, String name, String collection) async {
    final ref = await _firestore
        .collection('users')
        .doc(userId)
        .collection('decks')
        .add({
      'name': name,
      'collection': collection,
      'cards': [],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> deleteDeck(String userId, String firestoreId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(firestoreId)
        .delete();
  }

  Future<void> addCardToDeck(String userId, String deckFirestoreId, int cardId, int quantity) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckFirestoreId)
        .update({
      'cards': FieldValue.arrayUnion([
        {'cardId': cardId, 'quantity': quantity}
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeCardFromDeck(String userId, String deckFirestoreId, int cardId) async {
    // Need to read current cards, remove the one, then write back
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckFirestoreId)
        .get();

    if (doc.exists) {
      final List<dynamic> cards = doc.data()?['cards'] ?? [];
      cards.removeWhere((c) => c['cardId'] == cardId);
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('decks')
          .doc(deckFirestoreId)
          .update({
        'cards': cards,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getDecks(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('decks')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'firestoreId': doc.id,
        'name': data['name'],
        'collection': data['collection'],
        'cards': data['cards'] ?? [],
      };
    }).toList();
  }

  // ============================================================
  // User Profile Methods
  // ============================================================

  Future<void> updateLastSync(String userId) async {
    await _firestore.collection('users').doc(userId).set({
      'lastSyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> hasUserData(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.exists;
  }
}
