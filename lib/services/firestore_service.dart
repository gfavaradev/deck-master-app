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
    } catch (e) { // ignore: empty_catches
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
      // PERF #1 fix: fetch chunk in parallelo (batch di 10) invece di N round-trip sequenziali
      const batchSize = 10;
      for (int start = 1; start <= totalChunks; start += batchSize) {
        final end = (start + batchSize - 1).clamp(1, totalChunks);
        final futures = [
          for (int i = start; i <= end; i++)
            _firestore
                .collection(FirestorePaths.catalog(catalogName))
                .doc(FirestoreConstants.catalogChunks)
                .collection(FirestoreConstants.catalogItems)
                .doc(FirestoreConstants.getChunkId(i))
                .get(),
        ];
        final docs = await Future.wait(futures);
        for (final doc in docs) {
          if (doc.exists && doc.data() != null) {
            final List<dynamic> cards = doc.data()!['cards'] ?? [];
            for (var card in cards) {
              allCards.add(Map<String, dynamic>.from(card as Map));
            }
          }
        }
        onProgress?.call(end, totalChunks);
      }

      AppLogger.success(
        'Fetched ${allCards.length} cards from $catalogName',
        tag: 'FirestoreService',
      );
      return allCards;
    } catch (e) { // ignore: empty_catches
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
      // PERF #1 fix: fetch in parallelo a batch di 10
      const batchSize = 10;
      for (int start = 0; start < total; start += batchSize) {
        final end = (start + batchSize).clamp(0, total);
        final batch = chunkIds.sublist(start, end);
        final docs = await Future.wait(batch.map((chunkId) => _firestore
            .collection(FirestorePaths.catalog(catalogName))
            .doc(FirestoreConstants.catalogChunks)
            .collection(FirestoreConstants.catalogItems)
            .doc(chunkId)
            .get()));
        for (final doc in docs) {
          if (doc.exists && doc.data() != null) {
            final List<dynamic> cards = doc.data()!['cards'] ?? [];
            for (var card in cards) {
              allCards.add(Map<String, dynamic>.from(card as Map));
            }
          }
        }
        onProgress?.call(end, total);
      }

      AppLogger.success(
        'Fetched ${allCards.length} cards from ${chunkIds.length} chunks of $catalogName',
        tag: 'FirestoreService',
      );
      return allCards;
    } catch (e) { // ignore: empty_catches
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
    } catch (e) { // ignore: empty_catches
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
    } catch (e) { // ignore: empty_catches
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
    } catch (e) { // ignore: empty_catches
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
      // BUG #8 fix: persiste il valore manuale dell'utente così è visibile su altri dispositivi
      if (card.value > 0) 'value': card.value,
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
      // BUG #8 fix: persiste il valore manuale su Firestore
      'value': card.value > 0 ? card.value : FieldValue.delete(),
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
    } catch (_) { // ignore: empty_catches
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

    // PERF #3 fix: delete old chunks in batches (max 500 ops per WriteBatch)
    final oldChunks = await ref.collection('chunks').get();
    const maxBatch = 400;
    for (int i = 0; i < oldChunks.docs.length; i += maxBatch) {
      final batch = _firestore.batch();
      final end = (i + maxBatch).clamp(0, oldChunks.docs.length);
      for (final doc in oldChunks.docs.sublist(i, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // Write new chunks in batches
    final chunkStarts = [for (int i = 0; i < prices.length; i += _ctChunkSize) i];
    for (int i = 0; i < chunkStarts.length; i += maxBatch) {
      final batch = _firestore.batch();
      final end = (i + maxBatch).clamp(0, chunkStarts.length);
      for (final start in chunkStarts.sublist(i, end)) {
        final slice = prices.sublist(start, (start + _ctChunkSize).clamp(0, prices.length));
        batch.set(ref.collection('chunks').doc('$start'), {'rows': slice});
      }
      await batch.commit();
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
    } catch (_) { // ignore: empty_catches
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

  /// Returns syncedAt + modifiedChunks from the catalog metadata,
  /// written by syncCatalogPricesToFirestore when prices are embedded in chunks.
  Future<Map<String, dynamic>?> getCatalogPriceSyncInfo(String catalog) async {
    try {
      final catalogCollection = '${catalog}_catalog';
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('metadata')
          .get()
          .timeout(const Duration(seconds: 8));
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final ts = data['pricesSyncedAt'];
      if (ts is! Timestamp) return null;
      final rawChunks = data['priceModifiedChunks'];
      final modifiedChunks = rawChunks is List
          ? rawChunks.whereType<String>().toList()
          : <String>[];
      return {'syncedAt': ts.toDate(), 'modifiedChunks': modifiedChunks};
    } catch (_) {
      return null;
    }
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
