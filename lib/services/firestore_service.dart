import 'dart:async';
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
  FirestoreService._internal() : _firestore = FirebaseFirestore.instance;

  // Used by integration tests only — never call in production code.
  FirestoreService.forTesting(this._firestore);

  final FirebaseFirestore _firestore;

  /// Safe per-call ceiling for user-owned collection reads.
  ///
  /// Firestore `.get()` on an unbounded collection deserializes every document
  /// into memory at once, which OOMs / crashes on Android with realistic
  /// collection sizes (>500 docs). Every user-collection read caps at this
  /// limit; callers that need the full set must paginate (see
  /// `integration_test/crashes/firestore_oom_test.dart`).
  static const int kQueryLimit = 500;

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

  /// Downloads catalog chunks one small batch at a time, calling [onBatch]
  /// immediately after each batch so it can be processed and freed from RAM.
  /// Use this instead of [fetchCatalog] for full-catalog downloads to avoid OOM.
  Future<void> streamCatalog(
    String catalogName, {
    required Future<void> Function(
      List<Map<String, dynamic>> cards,
      int chunksDone,
      int chunksTotal,
    ) onBatch,
    int batchSize = 1,
  }) async {
    final metadata = await getCatalogMetadata(catalogName);
    if (metadata == null) throw Exception('Catalog metadata not found for $catalogName');
    final int totalChunks = metadata['totalChunks'] ?? 0;
    if (totalChunks == 0) throw Exception('No chunks available for $catalogName');

    AppLogger.info('Streaming catalog: $catalogName ($totalChunks chunks)', tag: 'FirestoreService');

    for (int start = 1; start <= totalChunks; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, totalChunks);
      // Fetch in a separate method so DocumentSnapshot objects go out of scope
      // (and become GC-eligible) before onBatch runs the heavy SQLite insert.
      // Retry once on timeout/network hiccup before propagating the error.
      List<Map<String, dynamic>> batchCards;
      try {
        batchCards = await _fetchChunkCards(catalogName, start, end);
      } on TimeoutException {
        await Future.delayed(const Duration(seconds: 2));
        batchCards = await _fetchChunkCards(catalogName, start, end);
      }
      await onBatch(batchCards, end, totalChunks);
      // Yield to the event loop so the GC can collect between chunks and the
      // UI thread stays responsive during the full catalog download.
      await Future.delayed(Duration.zero);
    }
  }

  /// Fetches Firestore chunks [start..end] and returns only plain card maps.
  /// Keeping this in a separate stack frame ensures DocumentSnapshot objects
  /// are released before the caller's onBatch (SQLite insert) runs.
  Future<List<Map<String, dynamic>>> _fetchChunkCards(
    String catalogName,
    int start,
    int end,
  ) async {
    final futures = [
      for (int i = start; i <= end; i++)
        _firestore
            .collection(FirestorePaths.catalog(catalogName))
            .doc(FirestoreConstants.catalogChunks)
            .collection(FirestoreConstants.catalogItems)
            .doc(FirestoreConstants.getChunkId(i))
            .get(),
    ];
    final docs = await Future.wait(futures)
        .timeout(const Duration(seconds: 30));
    final cards = <Map<String, dynamic>>[];
    for (final doc in docs) {
      if (doc.exists && doc.data() != null) {
        final List<dynamic> rawCards = doc.data()!['cards'] ?? [];
        for (var card in rawCards) {
          cards.add(Map<String, dynamic>.from(card as Map));
        }
      }
    }
    return cards;
    // docs goes out of scope here → DocumentSnapshot objects eligible for GC
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
        .collection(FirestorePaths.userAlbums(userId))
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
        .doc(FirestorePaths.userAlbum(userId, firestoreId))
        .update({
      'name': album.name,
      'collection': album.collection,
      'maxCapacity': album.maxCapacity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAlbum(String userId, String firestoreId) async {
    await _firestore
        .doc(FirestorePaths.userAlbum(userId, firestoreId))
        .delete();
  }

  Map<String, dynamic> _albumDocToMap(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return {
      'firestoreId': doc.id,
      'name': data['name'],
      'collection': data['collection'],
      'maxCapacity': data['maxCapacity'],
    };
  }

  /// Capped read (≤ [kQueryLimit]). For a full sync use [getAllAlbums].
  Future<List<Map<String, dynamic>>> getAlbums(String userId) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.userAlbums(userId))
        .limit(kQueryLimit)
        .get();

    return snapshot.docs.map(_albumDocToMap).toList();
  }

  /// Reads every album, paginating in [kQueryLimit]-sized pages so a large
  /// collection never deserializes into memory in a single query (Android OOM).
  Future<List<Map<String, dynamic>>> getAllAlbums(String userId) {
    return _readAllPaged(
      _firestore.collection(FirestorePaths.userAlbums(userId)),
      _albumDocToMap,
    );
  }

  // ============================================================
  // User Cards Methods
  // ============================================================

  Future<String> insertCard(String userId, CardModel card, {String? albumFirestoreId}) async {
    final ref = await _firestore
        .collection(FirestorePaths.userCards(userId))
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
        .doc(FirestorePaths.userCard(userId, firestoreId))
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
        .doc(FirestorePaths.userCard(userId, firestoreId))
        .delete();
  }

  Map<String, dynamic> _cardDocToMap(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
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
  }

  /// Capped read (≤ [kQueryLimit]). For a full sync use [getAllCards].
  Future<List<Map<String, dynamic>>> getCards(String userId) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.userCards(userId))
        .limit(kQueryLimit)
        .get();

    return snapshot.docs.map(_cardDocToMap).toList();
  }

  /// Reads every card, paginating in [kQueryLimit]-sized pages so a large
  /// collection never deserializes into memory in a single query (Android OOM).
  Future<List<Map<String, dynamic>>> getAllCards(String userId) {
    return _readAllPaged(
      _firestore.collection(FirestorePaths.userCards(userId)),
      _cardDocToMap,
    );
  }

  /// Reads every document of [collection] in [kQueryLimit]-sized pages using
  /// document-id cursor pagination, mapping each with [mapper]. Every underlying
  /// Firestore query stays bounded, so the full set is retrieved without a single
  /// oversized query.
  Future<List<Map<String, dynamic>>> _readAllPaged(
    Query<Map<String, dynamic>> collection,
    Map<String, dynamic> Function(DocumentSnapshot<Map<String, dynamic>>) mapper,
  ) async {
    final results = <Map<String, dynamic>>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      // Apply the cursor before .limit(): some Firestore backends (and
      // fake_cloud_firestore) drop startAfterDocument if it is chained after limit.
      Query<Map<String, dynamic>> page =
          collection.orderBy(FieldPath.documentId);
      if (cursor != null) page = page.startAfterDocument(cursor);
      final snapshot = await page.limit(kQueryLimit).get();
      if (snapshot.docs.isEmpty) break;
      results.addAll(snapshot.docs.map(mapper));
      if (snapshot.docs.length < kQueryLimit) break;
      cursor = snapshot.docs.last;
    }
    return results;
  }

  // ============================================================
  // User Decks Methods
  // ============================================================

  Future<String> insertDeck(String userId, String name, String collection) async {
    final ref = await _firestore
        .collection(FirestorePaths.userDecks(userId))
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
        .doc(FirestorePaths.userDeck(userId, firestoreId))
        .delete();
  }

  Future<void> renameDeck(String userId, String firestoreId, String name) async {
    await _firestore
        .doc(FirestorePaths.userDeck(userId, firestoreId))
        .update({'name': name, 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ============================================================
  // Wishlist Methods
  // ============================================================

  Future<void> upsertWishlistItem(String userId, Map<String, dynamic> item) async {
    await _firestore
        .doc(FirestorePaths.userWishlistItem(userId, item['catalogId'] as String))
        .set({
      'catalogId': item['catalogId'],
      'name': item['name'],
      'collection': item['collection'],
      'imageUrl': item['imageUrl'],
      'serialNumber': item['serialNumber'],
      'rarity': item['rarity'],
      'target_price': item['target_price'],
      'added_at': item['added_at'],
    });
  }

  Future<void> deleteWishlistItem(String userId, String catalogId) async {
    await _firestore
        .doc(FirestorePaths.userWishlistItem(userId, catalogId))
        .delete();
  }

  Future<void> updateWishlistTargetPrice(String userId, String catalogId, double? targetPrice) async {
    await _firestore
        .doc(FirestorePaths.userWishlistItem(userId, catalogId))
        .set({'target_price': targetPrice}, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getWishlistItems(String userId) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.userWishlist(userId))
        .get();
    return snapshot.docs.map((doc) {
      final d = doc.data();
      return {
        'catalogId': d['catalogId'] ?? doc.id,
        'name': d['name'] ?? '',
        'collection': d['collection'] ?? '',
        'imageUrl': d['imageUrl'],
        'serialNumber': d['serialNumber'],
        'rarity': d['rarity'],
        'target_price': d['target_price'],
        'added_at': d['added_at'] ?? '',
      };
    }).toList();
  }

  Future<void> addCardToDeck(String userId, String deckFirestoreId, int cardId, int quantity) async {
    await _firestore
        .doc(FirestorePaths.userDeck(userId, deckFirestoreId))
        .update({
      'cards': FieldValue.arrayUnion([
        {'cardId': cardId, 'quantity': quantity}
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeCardFromDeck(String userId, String deckFirestoreId, int cardId) async {
    final ref = _firestore.doc(FirestorePaths.userDeck(userId, deckFirestoreId));
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      if (!doc.exists) return;
      final List<dynamic> cards = doc.data()?['cards'] ?? [];
      cards.removeWhere((c) => c['cardId'] == cardId);
      transaction.update(ref, {
        'cards': cards,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<List<Map<String, dynamic>>> getDecks(String userId) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.userDecks(userId))
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
    await _firestore.doc(FirestorePaths.user(userId)).set({
      'lastSyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DateTime?> getLastSync(String userId) async {
    try {
      final doc = await _firestore.doc(FirestorePaths.user(userId)).get();
      final ts = doc.data()?['lastSyncAt'];
      if (ts is Timestamp) return ts.toDate();
    } catch (_) {}
    return null;
  }

  Future<bool> hasUserData(String userId) async {
    try {
      final doc = await _firestore
          .doc(FirestorePaths.user(userId))
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists) return true;

      final albums = await _firestore
          .collection(FirestorePaths.userAlbums(userId))
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      if (albums.docs.isNotEmpty) return true;

      final cards = await _firestore
          .collection(FirestorePaths.userCards(userId))
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      return cards.docs.isNotEmpty;
    } catch (_) {
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

  /// Returns the syncedAt timestamp from cardtrader_prices/{catalog}.
  /// Used by SyncService to decide whether to download fresh price rows.
  /// Cost: 1 Firestore read per catalog per check.
  Future<DateTime?> getCardtraderPricesSyncedAt(String catalog) async {
    try {
      final doc = await _firestore
          .collection('cardtrader_prices')
          .doc(catalog)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!doc.exists) return null;
      final ts = doc.data()?['syncedAt'];
      if (ts is! Timestamp) return null;
      return ts.toDate();
    } catch (_) {
      return null;
    }
  }

  /// Streams raw price rows from `cardtrader_prices/{catalog}/chunks` a few
  /// chunks at a time, calling [onBatch] for each batch so it can be written to
  /// SQLite and freed. Each row has the same schema as the local
  /// cardtrader_prices SQLite table.
  ///
  /// Never load this collection with a single `.get()`. Doing so made every
  /// production install crash on 1.3.9 (vc113): the Firestore plugin encodes
  /// the whole QuerySnapshot into ONE platform-channel message, so
  /// `ByteArrayOutputStream.grow` doubled its buffer until
  /// `java.lang.OutOfMemoryError` killed the process. yugioh alone is 626
  /// chunks / ~250 400 rows / ~69 MB, and grows daily — see
  /// `integration_test/crashes/firestore_oom_test.dart`.
  ///
  /// Chunk ids are the numeric row offset (`'0'`, `'400'`, …) and the parent
  /// doc carries `count` = total rows, written identically by
  /// [saveCardtraderPrices] and by `scripts/price_sync/index.js`. That makes
  /// ids derivable without listing the collection, exactly as [streamCatalog]
  /// derives them from `totalChunks`.
  Future<void> streamCardtraderPriceRows(
    String catalog, {
    required Future<void> Function(List<Map<String, dynamic>> rows) onBatch,
    int chunksPerBatch = 5,
  }) async {
    final ref = _firestore.collection('cardtrader_prices').doc(catalog);
    final meta = await ref.get().timeout(const Duration(seconds: 8));
    final count = (meta.data()?['count'] as num?)?.toInt() ?? 0;
    if (count <= 0) return;

    final step = _ctChunkSize * chunksPerBatch;
    for (int start = 0; start < count; start += step) {
      // Fetched in a separate method so the DocumentSnapshot objects go out of
      // scope (and become GC-eligible) before onBatch runs the SQLite insert.
      // Retry once on a timeout/network hiccup before giving up on the batch.
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchPriceChunkRows(ref, start, count, chunksPerBatch);
      } on TimeoutException {
        await Future.delayed(const Duration(seconds: 2));
        rows = await _fetchPriceChunkRows(ref, start, count, chunksPerBatch);
      }
      if (rows.isNotEmpty) await onBatch(rows);
      // Yield to the event loop so the GC can collect between batches and the
      // UI thread stays responsive during the download.
      await Future.delayed(Duration.zero);
    }
  }

  /// Fetches up to [chunksPerBatch] price chunks starting at row offset [start]
  /// and returns only plain row maps. Kept in its own stack frame so the
  /// DocumentSnapshot objects are released before the caller's onBatch runs.
  Future<List<Map<String, dynamic>>> _fetchPriceChunkRows(
    DocumentReference<Map<String, dynamic>> ref,
    int start,
    int count,
    int chunksPerBatch,
  ) async {
    final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    for (int i = 0; i < chunksPerBatch; i++) {
      final offset = start + i * _ctChunkSize;
      if (offset >= count) break;
      futures.add(ref.collection('chunks').doc('$offset').get());
    }
    final docs =
        await Future.wait(futures).timeout(const Duration(seconds: 30));
    final rows = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final rawRows = doc.data()?['rows'] as List<dynamic>?;
      if (rawRows == null) continue;
      for (final r in rawRows) {
        if (r is Map) rows.add(Map<String, dynamic>.from(r));
      }
    }
    return rows;
    // docs goes out of scope here -> DocumentSnapshot objects eligible for GC
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
    for (final colPath in [
      FirestorePaths.userAlbums(userId),
      FirestorePaths.userCards(userId),
      FirestorePaths.userDecks(userId),
    ]) {
      QuerySnapshot snapshot;
      do {
        snapshot = await _firestore
            .collection(colPath)
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

  // ============================================================
  // News
  // ============================================================

  /// Fetch news relevant to [collectionKeys] (unlocked collections).
  /// Documents with collections: ['all'] are always included.
  Future<List<Map<String, dynamic>>> getNews(List<String> collectionKeys) async {
    final tags = ['all', ...collectionKeys];
    // arrayContainsAny supports up to 10 values — safe since we have ≤5 tags.
    final snap = await _firestore
        .collection('news')
        .where('collections', arrayContainsAny: tags)
        .orderBy('publishedAt', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList();
  }
}
