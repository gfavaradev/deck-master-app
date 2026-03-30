import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';
import '../models/collection_model.dart';
import '../constants/app_constants.dart';
import '../utils/firestore_paths.dart';
import '../utils/app_logger.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================================
  // Catalog Methods (Generic for all catalogs)
  // ============================================================

  /// Get catalog metadata (version, total chunks, etc.)
  /// Works for any catalog (yugioh, pokemon, magic, etc.)
  Future<Map<String, dynamic>?> getCatalogMetadata(String catalogName) async {
    try {
      final doc = await _firestore
          .collection(FirestorePaths.catalog(catalogName))
          .doc(FirestoreConstants.catalogMetadata)
          .get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      AppLogger.error(
        'Error getting catalog metadata',
        tag: 'FirestoreService',
        error: e,
      );
      return null;
    }
  }

  /// Fetch catalog from Firestore chunks
  /// Generic method that works for any catalog
  Future<List<Map<String, dynamic>>> fetchCatalog(
    String catalogName, {
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      AppLogger.info('Fetching catalog: $catalogName', tag: 'FirestoreService');

      // Get metadata to know total chunks
      final metadata = await getCatalogMetadata(catalogName);
      if (metadata == null) {
        throw Exception('Catalog metadata not found for $catalogName');
      }

      final int totalChunks = metadata['totalChunks'] ?? 0;
      if (totalChunks == 0) {
        throw Exception('No chunks available for $catalogName');
      }

      final List<Map<String, dynamic>> allCards = [];

      for (int i = 1; i <= totalChunks; i++) {
        final chunkId = FirestoreConstants.getChunkId(i);
        final doc = await _firestore
            .collection(FirestorePaths.catalog(catalogName))
            .doc(FirestoreConstants.catalogChunks)
            .collection(FirestoreConstants.catalogItems)
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

      AppLogger.success(
        'Fetched ${allCards.length} cards from $catalogName',
        tag: 'FirestoreService',
      );
      return allCards;
    } catch (e) {
      AppLogger.error(
        'Error fetching catalog $catalogName',
        tag: 'FirestoreService',
        error: e,
      );
      rethrow;
    }
  }

  /// Fetch specific catalog chunks from Firestore (for incremental/delta updates).
  /// Only the chunks listed in [chunkIds] are downloaded.
  Future<List<Map<String, dynamic>>> fetchCatalogChunks(
    String catalogName,
    List<String> chunkIds, {
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      AppLogger.info('Fetching ${chunkIds.length} chunks for $catalogName', tag: 'FirestoreService');
      final List<Map<String, dynamic>> allCards = [];
      final total = chunkIds.length;

      for (int i = 0; i < total; i++) {
        final chunkId = chunkIds[i];
        final doc = await _firestore
            .collection(FirestorePaths.catalog(catalogName))
            .doc(FirestoreConstants.catalogChunks)
            .collection(FirestoreConstants.catalogItems)
            .doc(chunkId)
            .get();

        if (doc.exists && doc.data() != null) {
          final List<dynamic> cards = doc.data()!['cards'] ?? [];
          for (var card in cards) {
            allCards.add(Map<String, dynamic>.from(card as Map));
          }
        }
        onProgress?.call(i + 1, total);
      }

      AppLogger.success(
        'Fetched ${allCards.length} cards from ${chunkIds.length} chunks of $catalogName',
        tag: 'FirestoreService',
      );
      return allCards;
    } catch (e) {
      AppLogger.error(
        'Error fetching catalog chunks for $catalogName',
        tag: 'FirestoreService',
        error: e,
      );
      rethrow;
    }
  }

  /// Backward compatibility: Fetch Yu-Gi-Oh catalog
  @Deprecated('Use fetchCatalog(CatalogConstants.yugioh) instead')
  Future<List<Map<String, dynamic>>> fetchYugiohCatalog({
    void Function(int current, int total)? onProgress,
  }) async {
    return fetchCatalog(CatalogConstants.yugioh, onProgress: onProgress);
  }

  // ============================================================
  // User Collections Methods
  // ============================================================

  Future<void> setCollections(String userId, List<CollectionModel> collections) async {
    try {
      final batch = _firestore.batch();
      for (var col in collections) {
        final ref = _firestore.doc(FirestorePaths.userCollection(userId, col.key));
        batch.set(ref, {
          'name': col.name,
          'isUnlocked': col.isUnlocked,
        });
      }
      await batch.commit();
      AppLogger.sync('Set ${collections.length} collections for user $userId');
    } catch (e) {
      AppLogger.error('Error setting collections', tag: 'FirestoreService', error: e);
      rethrow;
    }
  }

  Future<void> setCollectionUnlocked(String userId, String collectionKey, bool unlocked) async {
    try {
      await _firestore.doc(FirestorePaths.userCollection(userId, collectionKey)).set(
        {'isUnlocked': unlocked},
        SetOptions(merge: true),
      );
      AppLogger.sync('Collection $collectionKey unlocked: $unlocked');
    } catch (e) {
      AppLogger.error('Error unlocking collection', tag: 'FirestoreService', error: e);
      rethrow;
    }
  }

  Future<List<CollectionModel>> getCollections(String userId) async {
    try {
      final snapshot = await _firestore.collection(FirestorePaths.userCollections(userId)).get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return CollectionModel(
          key: doc.id,
          name: data['name'] ?? doc.id,
          isUnlocked: data['isUnlocked'] ?? false,
        );
      }).toList();
    } catch (e) {
      AppLogger.error('Error getting collections', tag: 'FirestoreService', error: e);
      return [];
    }
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

  Future<DateTime?> getLastSync(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final ts = doc.data()?['lastSyncAt'];
      if (ts is Timestamp) return ts.toDate();
    } catch (_) {}
    return null;
  }

  Future<bool> hasUserData(String userId) async {
    try {
      // Check if user document exists OR if user has any subcollections
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists) return true;

      // Check albums subcollection (most reliable indicator of real data)
      final albums = await _firestore
          .collection('users')
          .doc(userId)
          .collection('albums')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      if (albums.docs.isNotEmpty) return true;

      // Check cards subcollection
      final cards = await _firestore
          .collection('users')
          .doc(userId)
          .collection('cards')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      return cards.docs.isNotEmpty;
    } catch (_) {
      // Offline o timeout → assume che i dati remoti esistano se c'è cache locale
      return false;
    }
  }

  // ============================================================
  // CardTrader Prices (shared, not per-user)
  // ============================================================

  static const int _ctChunkSize = 400;

  Future<void> saveCardtraderPrices(
    String catalog,
    List<Map<String, dynamic>> prices,
  ) async {
    final ref = _firestore.collection('cardtrader_prices').doc(catalog);

    // Delete old chunks
    final oldChunks = await ref.collection('chunks').get();
    for (final chunk in oldChunks.docs) {
      await chunk.reference.delete();
    }

    // Write new chunks
    for (int i = 0; i < prices.length; i += _ctChunkSize) {
      final slice = prices.sublist(i, (i + _ctChunkSize).clamp(0, prices.length));
      await ref.collection('chunks').doc('$i').set({'rows': slice});
    }

    // Update metadata
    await ref.set({
      'catalog': catalog,
      'count': prices.length,
      'syncedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchCardtraderPrices(String catalog) async {
    try {
      final chunks = await _firestore
          .collection('cardtrader_prices')
          .doc(catalog)
          .collection('chunks')
          .get()
          .timeout(const Duration(seconds: 30));

      final result = <Map<String, dynamic>>[];
      for (final doc in chunks.docs) {
        final rows = doc.data()['rows'] as List<dynamic>? ?? [];
        result.addAll(rows.cast<Map<String, dynamic>>());
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<DateTime?> getCardtraderPricesSyncedAt(String catalog) async {
    try {
      final doc = await _firestore
          .collection('cardtrader_prices')
          .doc(catalog)
          .get()
          .timeout(const Duration(seconds: 8));
      final ts = doc.data()?['syncedAt'];
      if (ts is Timestamp) return ts.toDate();
    } catch (_) {}
    return null;
  }

  /// Delete all albums, cards and decks documents for a user.
  /// Used by resetAndResync to start from a clean slate.
  Future<void> clearUserData(String userId) async {
    for (final col in ['albums', 'cards', 'decks']) {
      QuerySnapshot snapshot;
      do {
        snapshot = await _firestore
            .collection('users/$userId/$col')
            .limit(450)
            .get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (snapshot.docs.length == 450);
    }
  }
}
