import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';
import '../models/collection_model.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  static const _syncCooldown = Duration(hours: 6);
  static const _hasRemoteDataPrefix = 'sync_has_remote_';

  // Cache locale: una volta che sappiamo che il remoto ha dati, rimane vero per sempre
  Future<bool> _getCachedHasRemote(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_hasRemoteDataPrefix$uid') ?? false;
  }

  Future<void> _setCachedHasRemote(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_hasRemoteDataPrefix$uid', true);
  }

  // ============================================================
  // Remote Change Stream (notifica le pagine dopo sync/push)
  // ============================================================

  final _remoteChangeController = StreamController<String>.broadcast();
  Stream<String> get onRemoteChange => _remoteChangeController.stream;

  Future<void> Function(String catalog, List<String> chunkIds)? _catalogPriceUpdateListener;

  void registerCatalogPriceUpdateListener(
      Future<void> Function(String, List<String>) listener) {
    _catalogPriceUpdateListener = listener;
  }

  // I listener real-time Firestore sono stati rimossi per azzerare le letture
  // passive (ogni riconnessione costava N reads = tutti i documenti).
  // La UI si aggiorna tramite onRemoteChange emesso da pullFromCloud() e dai push locali.
  void startListening() {}
  void stopListening() {}

  /// Notifica tutte le pagine che i dati locali sono cambiati (insert/update/delete).
  /// Usato da DataRepository dopo ogni scrittura locale.
  void notifyLocalChange(String table) {
    _remoteChangeController.add(table);
  }

  /// Check if sync is possible (user authenticated and not in offline mode)
  Future<bool> canSync() async {
    final isOffline = await _authService.isOfflineMode();
    if (isOffline) return false;
    return FirebaseAuth.instance.currentUser != null;
  }

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  // ============================================================
  // Initial Upload: Push all local data to Firestore (first time)
  // ============================================================

  Future<void> initialUpload() async {
    final userId = _userId;
    if (userId == null) return;

    try {
      // Upload collections
      final collections = await _dbHelper.getCollections();
      await _firestoreService.setCollections(userId, collections);

      // Upload albums and build ID mapping
      final albums = await _dbHelper.getAllAlbums();
      final Map<int, String> albumIdMap = {}; // localId -> firestoreId

      for (var album in albums) {
        final firestoreId = await _firestoreService.insertAlbum(userId, album);
        if (album.id != null) {
          albumIdMap[album.id!] = firestoreId;
          await _dbHelper.updateFirestoreId('albums', album.id!, firestoreId);
        }
      }

      // Upload cards
      final cards = await _dbHelper.getAllCards();
      for (var card in cards) {
        final albumFirestoreId = albumIdMap[card.albumId];
        final firestoreId = await _firestoreService.insertCard(
          userId,
          card,
          albumFirestoreId: albumFirestoreId,
        );
        if (card.id != null) {
          await _dbHelper.updateFirestoreId('cards', card.id!, firestoreId);
        }
      }

      // Upload decks
      final decks = await _dbHelper.getAllDecks();
      for (var deck in decks) {
        final firestoreId = await _firestoreService.insertDeck(
          userId,
          deck['name'],
          deck['collection'],
        );
        final localDeckId = deck['id'] as int?;
        if (localDeckId == null) continue;
        await _dbHelper.updateFirestoreId('decks', localDeckId, firestoreId);

        // Upload deck cards
        final deckCards = await _dbHelper.getDeckCards(localDeckId);
        for (var dc in deckCards) {
          await _firestoreService.addCardToDeck(
            userId,
            firestoreId,
            dc['id'] as int,
            dc['deckQuantity'] as int,
          );
        }
      }

      await _firestoreService.updateLastSync(userId);
      await _dbHelper.clearPendingSync();


    } catch (e) { // ignore: empty_catches

      rethrow;
    }
  }

  // ============================================================
  // Pull from Cloud: Download Firestore data into SQLite
  // ============================================================

  Future<void> pullFromCloud() async {
    final userId = _userId;
    if (userId == null) return;

    try {
      // ── Fetch remote data in parallel ──────────────────────────────────────
      // NOTE: deleteOrphanedItems() is called AFTER this fetch succeeds.
      // Calling it before would delete local-only items if the fetch fails (offline).
      final results = await Future.wait([
        _firestoreService.getCollections(userId),
        _firestoreService.getAlbums(userId),
        _firestoreService.getCards(userId),
        _firestoreService.getDecks(userId),
      ]).timeout(const Duration(seconds: 20));

      // Remove orphaned local rows (no firestoreId, not in pending_sync).
      // These accumulate when sync fails mid-way and cause items to appear
      // doubled alongside the remote versions that are about to be pulled.
      // Safe to run here because we've confirmed Firestore is reachable above.
      await _dbHelper.deleteOrphanedItems();

      final remoteCollections = results[0] as List<CollectionModel>;
      final remoteAlbums      = results[1] as List<Map<String, dynamic>>;
      final remoteCards       = results[2] as List<Map<String, dynamic>>;
      final remoteDecks       = results[3] as List<Map<String, dynamic>>;

      // Collections — aggiorna solo se il server ha risposto con dati reali
      if (remoteCollections.isNotEmpty) {
        await _dbHelper.resetCollectionsLockState();
        for (final col in remoteCollections) {
          if (col.isUnlocked) await _dbHelper.unlockCollection(col.key);
        }
      }

      // ── Albums: upsert by firestoreId ─────────────────────────────────────
      final Map<String, int> firestoreToLocalAlbumId = {};
      final remoteAlbumFsIds = <String>[];

      for (final albumData in remoteAlbums) {
        final firestoreId = albumData['firestoreId'] as String;
        remoteAlbumFsIds.add(firestoreId);

        final incoming = AlbumModel(
          name: albumData['name'] ?? '',
          collection: albumData['collection'] ?? '',
          maxCapacity: albumData['maxCapacity'] ?? 100,
        );

        final existing = await _dbHelper.getAlbumByFirestoreId(firestoreId);
        if (existing != null) {
          await _dbHelper.updateAlbum(
            incoming.copyWith(id: existing.id, firestoreId: firestoreId),
          );
          firestoreToLocalAlbumId[firestoreId] = existing.id!;
        } else {
          final localId = await _dbHelper.insertAlbum(incoming);
          await _dbHelper.updateFirestoreId('albums', localId, firestoreId);
          firestoreToLocalAlbumId[firestoreId] = localId;
        }
      }

      // Delete local albums removed on another device (has firestoreId not in remote set)
      await _dbHelper.deleteAlbumsNotInFirestoreIds(remoteAlbumFsIds);

      // ── Cards: upsert by firestoreId ──────────────────────────────────────
      final remoteCardFsIds = <String>[];

      for (final cardData in remoteCards) {
        final firestoreId = cardData['firestoreId'] as String?;
        if (firestoreId == null) continue;
        remoteCardFsIds.add(firestoreId);

        // Map albumFirestoreId → local albumId
        int albumId = cardData['albumId'] ?? -1;
        final albumFirestoreId = cardData['albumFirestoreId'] as String?;
        if (albumFirestoreId != null && firestoreToLocalAlbumId.containsKey(albumFirestoreId)) {
          albumId = firestoreToLocalAlbumId[albumFirestoreId]!;
        }

        final card = CardModel(
          catalogId:    cardData['catalogId'],
          name:         cardData['name'] ?? '',
          serialNumber: cardData['serialNumber'] ?? '',
          collection:   cardData['collection'] ?? '',
          albumId:      albumId,
          type:         cardData['type'] ?? '',
          rarity:       cardData['rarity'] ?? '',
          description:  cardData['description'] ?? '',
          quantity:     cardData['quantity'] ?? 1,
          value:        (cardData['value'] as num?)?.toDouble() ?? 0.0,
          imageUrl:     cardData['imageUrl'],
          firestoreId:  firestoreId,
        );

        final existing = await _dbHelper.getCardByFirestoreId(firestoreId);
        if (existing != null) {
          // Preserve local value — CT prices come from shared Firestore collection,
          // not from per-user card documents.
          await _dbHelper.updateCard(card.copyWith(
            id: existing.id,
            value: existing.value,
            cardtraderValue: existing.cardtraderValue,
          ));
        } else {
          final localId = await _dbHelper.insertCard(card);
          await _dbHelper.updateFirestoreId('cards', localId, firestoreId);
        }
      }

      // Delete local cards removed on another device
      await _dbHelper.deleteCardsNotInFirestoreIds(remoteCardFsIds);

      // ── Decks: upsert by firestoreId ──────────────────────────────────────
      final db = await _dbHelper.database;
      for (final deckData in remoteDecks) {
        final firestoreId = deckData['firestoreId'] as String?;
        if (firestoreId == null) continue;

        final existing = await db.query('decks',
            where: 'firestoreId = ?', whereArgs: [firestoreId]);
        if (existing.isNotEmpty) {
          await db.update(
            'decks',
            {'name': deckData['name'], 'collection': deckData['collection']},
            where: 'firestoreId = ?', whereArgs: [firestoreId],
          );
        } else {
          final localDeckId = await _dbHelper.insertDeck(
            deckData['name'] ?? '',
            deckData['collection'] ?? '',
          );
          await _dbHelper.updateFirestoreId('decks', localDeckId, firestoreId);
        }
      }

      await _dbHelper.clearPendingSync();


      // Sync CardTrader prices from shared Firestore collection
      await _syncCardtraderPrices();

      _remoteChangeController.add('cards');
    } catch (e) { // ignore: empty_catches

      rethrow;
    }
  }

  static const _catalogNames = {
    'yugioh': 'Yu-Gi-Oh!',
    'pokemon': 'Pokémon',
    'onepiece': 'One Piece',
  };

  Future<void> _syncCardtraderPrices() async {
    try {
      for (final catalog in ['yugioh', 'pokemon', 'onepiece']) {
        final prefs = await SharedPreferences.getInstance();
        int updated = 0;

        // ── Part A: raw cardtrader_prices collection ──────────────────────────
        // Indipendente da Part B: viene saltato se già aggiornato, ma Part B
        // viene sempre eseguito (BUG #3 fix).
        final remoteSyncedAt = await _firestoreService
            .getCardtraderPricesSyncedAt(catalog)
            .timeout(const Duration(seconds: 10), onTimeout: () => null);

        if (remoteSyncedAt != null) {
          final localKey = 'ct_prices_synced_at_$catalog';
          final localStr = prefs.getString(localKey);
          final localSyncedAt = localStr != null ? DateTime.tryParse(localStr) : null;

          if (localSyncedAt == null || remoteSyncedAt.isAfter(localSyncedAt)) {
            final prices = await _firestoreService
                .fetchCardtraderPrices(catalog)
                .timeout(const Duration(seconds: 20), onTimeout: () => []);
            if (prices.isNotEmpty) {
              await _dbHelper.upsertCardtraderPrices(prices);
              updated = await _dbHelper.syncCollectionValuesFromCardtrader(catalog);
              await _dbHelper.syncCatalogPricesFromCardtrader(catalog);
              await prefs.setString(localKey, remoteSyncedAt.toIso8601String());
            }
          }
        }

        // ── Part B: prezzi embedded nei chunk del catalogo (sempre controllato)
        // Se l'admin ha eseguito syncCatalogPricesToFirestore, i chunk sono stati
        // aggiornati con prezzi embedded. Questo blocco è indipendente da Part A
        // e non viene saltato anche se i raw cardtrader_prices sono già in sync.
        try {
          final priceSyncInfo = await _firestoreService
              .getCatalogPriceSyncInfo(catalog)
              .timeout(const Duration(seconds: 10), onTimeout: () => null);
          if (priceSyncInfo != null) {
            final syncedAt = priceSyncInfo['syncedAt'] as DateTime;
            final chunkIds = priceSyncInfo['modifiedChunks'] as List<String>;
            final localCatalogKey = 'ct_catalog_prices_synced_at_$catalog';
            final localCatalogStr = prefs.getString(localCatalogKey);
            final localCatalogSyncedAt = localCatalogStr != null
                ? DateTime.tryParse(localCatalogStr)
                : null;
            if ((localCatalogSyncedAt == null || syncedAt.isAfter(localCatalogSyncedAt)) &&
                chunkIds.isNotEmpty) {
              // BUG #1 fix: await il listener e salva il flag SOLO al completamento.
              await _catalogPriceUpdateListener?.call(catalog, chunkIds);
              await prefs.setString(localCatalogKey, syncedAt.toIso8601String());
            }
          }
        } catch (_) {}

        // ── Notifica utente ───────────────────────────────────────────────────
        if (updated > 0) {
          final collections = await _dbHelper.getCollections();
          final isUnlocked = collections.any((c) => c.key == catalog && c.isUnlocked);
          if (isUnlocked) {
            await NotificationService().showPricesSyncedNotification(
              collectionName: _catalogNames[catalog] ?? catalog,
              updatedCount: updated,
            );
          }
        }
      }
    } catch (e) { // ignore: empty_catches

    }
  }

  // ============================================================
  // Sync on Login: Decide whether to push or pull
  // ============================================================

  static const _lastSyncKey = 'sync_last_sync_at';

  Future<void> _saveLocalLastSyncAt(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, dt.toIso8601String());
  }

  Future<void> syncOnLogin() async {
    if (kIsWeb) return;
    if (_isSyncing) return;

    // Controlla se ci sono item pending: se sì, non applicare il cooldown
    final pendingCount = await _dbHelper.getPendingSyncCount();
    final hasPending = pendingCount > 0;

    if (!hasPending && _lastSyncTime != null &&
        DateTime.now().difference(_lastSyncTime!) < _syncCooldown) {

      return;
    }

    _isSyncing = true;

    try {
      final userId = _userId;
      if (userId == null) return;

      // Letture in parallelo
      final cachedHasRemote = await _getCachedHasRemote(userId);

      final syncCollsFuture   = _syncCollections(userId);
      final hasRemoteFuture   = cachedHasRemote
          ? Future.value(true)
          : _firestoreService.hasUserData(userId);
      final albumsFuture      = _dbHelper.getAllAlbums();
      final cardsFuture       = _dbHelper.getAllCards();

      await syncCollsFuture;
      final hasRemoteData  = await hasRemoteFuture;
      final localAlbums    = await albumsFuture;
      final localCards     = await cardsFuture;

      if (hasRemoteData) await _setCachedHasRemote(userId);

      // Local is considered "present" only when BOTH albums and cards exist.
      // Albums without cards is an anomalous/partial state (e.g. cards table
      // was cleared mid-sync) — treat it the same as fully empty so we pull
      // fresh data from the cloud instead of skipping the restore.
      final hasLocalData = localAlbums.isNotEmpty && localCards.isNotEmpty;

      if (hasRemoteData && !hasLocalData) {
        // Cloud ha dati, locale vuoto o incompleto → flush pending, poi scarica dal cloud
        if (hasPending) await flushPendingQueue();
        await pullFromCloud();
      } else if (hasLocalData && !hasRemoteData) {
        // Locale ha dati, cloud vuoto → carica sul cloud
        await initialUpload();
      } else if (hasRemoteData && hasLocalData) {
        // Entrambi hanno dati.
        // 1. Flush pending: pusha su Firestore solo le modifiche in coda
        //    (carte/album creati/modificati offline o con sync fallita).
        //    initialUpload() NON va usato qui — reinseriscerebbe tutti gli item
        //    come nuovi documenti Firestore, causando duplicati.
        if (hasPending) await flushPendingQueue();

        // 2. Pull: riceve le modifiche dal cloud (altri dispositivi, ecc.)
        await pullFromCloud();
      }

      final now = DateTime.now();
      _lastSyncTime = now;
      await _saveLocalLastSyncAt(now);
    } catch (e) { // ignore: empty_catches

    } finally {
      _isSyncing = false;
    }
  }

  /// Sync collections (unlocked status) from Firestore
  Future<void> _syncCollections(String userId) async {
    if (kIsWeb) return;
    try {
      final remoteCollections = await _firestoreService.getCollections(userId)
          .timeout(const Duration(seconds: 8));

      // Se la lista è vuota potremmo essere offline (getCollections ritorna []
      // in caso di errore). Non resettare lo stato locale per evitare di
      // bloccare tutte le collezioni sbloccate dell'utente.
      if (remoteCollections.isEmpty) {

        return;
      }

      await _dbHelper.resetCollectionsLockState();
      for (var col in remoteCollections) {
        if (col.isUnlocked) await _dbHelper.unlockCollection(col.key);
      }

    } catch (e) { // ignore: empty_catches

    }
  }

  // ============================================================
  // Push Single Change (called after local writes)
  // ============================================================

  Future<void> pushAlbumChange(AlbumModel album, String changeType) async {
    if (!await canSync()) {
      if (album.id != null) {
        // For deletes, store firestoreId in 'data' so flushPendingQueue can
        // push the Firestore delete even after the local row is gone.
        await _dbHelper.addPendingSync(
          'albums',
          album.id!,
          changeType,
          data: changeType == 'delete' ? album.firestoreId : null,
        );
      }
      return;
    }

    final userId = _userId;
    if (userId == null) return;

    try {
      switch (changeType) {
        case 'insert':
          final firestoreId = await _firestoreService.insertAlbum(userId, album)
              .timeout(const Duration(seconds: 10));
          if (album.id != null) {
            await _dbHelper.updateFirestoreId('albums', album.id!, firestoreId);
          }
          break;
        case 'update':
          if (album.firestoreId != null) {
            await _firestoreService.updateAlbum(userId, album.firestoreId!, album)
                .timeout(const Duration(seconds: 10));
          }
          break;
        case 'delete':
          if (album.firestoreId != null) {
            await _firestoreService.deleteAlbum(userId, album.firestoreId!)
                .timeout(const Duration(seconds: 10));
          }
          break;
      }
    } catch (e) { // ignore: empty_catches

      if (album.id != null) {
        await _dbHelper.addPendingSync('albums', album.id!, changeType);
      }
    }
  }

  Future<void> pushCardChange(CardModel card, String changeType) async {
    if (!await canSync()) {
      if (card.id != null) {
        // For deletes, store firestoreId in 'data' so flushPendingQueue can
        // push the Firestore delete even after the local row is gone.
        await _dbHelper.addPendingSync(
          'cards',
          card.id!,
          changeType,
          data: changeType == 'delete' ? card.firestoreId : null,
        );
      }
      return;
    }

    final userId = _userId;
    if (userId == null) return;

    try {
      switch (changeType) {
        case 'insert':
          String? albumFirestoreId;
          if (card.albumId > 0) {
            albumFirestoreId = await _dbHelper.getFirestoreId('albums', card.albumId);
          }
          // BUG #10 fix: se la carta ha già un firestoreId (sync parziale precedente)
          // aggiorna invece di inserire di nuovo per evitare duplicati su Firestore.
          if (card.firestoreId != null) {
            await _firestoreService.updateCard(
              userId,
              card.firestoreId!,
              card,
              albumFirestoreId: albumFirestoreId,
            ).timeout(const Duration(seconds: 10));
          } else {
            final firestoreId = await _firestoreService.insertCard(
              userId,
              card,
              albumFirestoreId: albumFirestoreId,
            ).timeout(const Duration(seconds: 10));
            if (card.id != null) {
              await _dbHelper.updateFirestoreId('cards', card.id!, firestoreId);
            }
          }
          break;
        case 'update':
          if (card.firestoreId != null) {
            String? albumFirestoreId;
            if (card.albumId > 0) {
              albumFirestoreId = await _dbHelper.getFirestoreId('albums', card.albumId);
            }
            await _firestoreService.updateCard(
              userId,
              card.firestoreId!,
              card,
              albumFirestoreId: albumFirestoreId,
            ).timeout(const Duration(seconds: 10));
          }
          break;
        case 'delete':
          if (card.firestoreId != null) {
            await _firestoreService.deleteCard(userId, card.firestoreId!)
                .timeout(const Duration(seconds: 10));
          }
          break;
      }
    } catch (e) { // ignore: empty_catches

      if (card.id != null) {
        await _dbHelper.addPendingSync('cards', card.id!, changeType);
      }
    }
  }

  Future<void> pushDeckChange(int deckId, String changeType) async {
    if (!await canSync()) {
      await _dbHelper.addPendingSync('decks', deckId, changeType);
      return;
    }

    final userId = _userId;
    if (userId == null) return;

    try {
      final firestoreId = await _dbHelper.getFirestoreId('decks', deckId);
      switch (changeType) {
        // BUG #12 fix: gestisce 'insert' per deck creati offline.
        case 'insert':
          if (firestoreId == null) {
            final decks = await _dbHelper.getAllDecks();
            final deck = decks.where((d) => d['id'] == deckId).firstOrNull;
            if (deck != null) {
              final newFirestoreId = await _firestoreService.insertDeck(
                userId,
                deck['name'] as String? ?? '',
                deck['collection'] as String? ?? '',
              ).timeout(const Duration(seconds: 10));
              await _dbHelper.updateFirestoreId('decks', deckId, newFirestoreId);
            }
          }
          break;
        case 'delete':
          if (firestoreId != null) {
            await _firestoreService.deleteDeck(userId, firestoreId)
                .timeout(const Duration(seconds: 10));
          }
          break;
      }
    } catch (e) { // ignore: empty_catches

      await _dbHelper.addPendingSync('decks', deckId, changeType);
    }
  }

  Future<void> pushCollectionUnlock(String collectionKey) async {
    if (!await canSync()) return;
    final userId = _userId;
    if (userId == null) return;

    try {
      await _firestoreService.setCollectionUnlocked(userId, collectionKey, true)
          .timeout(const Duration(seconds: 10));
    } catch (e) { // ignore: empty_catches

    }
  }

  // ============================================================
  // Flush Pending Queue
  // ============================================================

  // ============================================================
  // Reset & Resync: deduplicate local data, clean Firestore, re-upload
  // ============================================================

  /// Wipe all local user data and pull a fresh copy from Firestore.
  /// Use when the user sees doubled cards/albums/decks in the app
  /// (local SQLite has orphaned rows that Firestore does not know about).
  Future<void> resetAndResync({void Function(String)? onStatus}) async {
    stopListening();

    final userId = _userId;
    if (userId == null) return;

    try {
      onStatus?.call('Pulizia dati locali...');

      // Clear all local user tables (albums, cards, decks, deck_cards, pending_sync)
      await _dbHelper.clearUserData();

      onStatus?.call('Scaricamento dal cloud...');

      // Pull a fresh copy from Firestore (already clean, no duplicates)
      await pullFromCloud();

      // Reset the cached has-remote flag so next sync re-checks from scratch
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_hasRemoteDataPrefix$userId');

      onStatus?.call('Completato!');

    } catch (e) { // ignore: empty_catches

      rethrow;
    } finally {
      startListening();
    }
  }

  Future<void> flushPendingQueue() async {
    if (!await canSync()) return;

    final userId = _userId;
    if (userId == null) return;

    final pending = await _dbHelper.getPendingSync();
    if (pending.isEmpty) return;



    for (var item in pending) {
      try {
        final tableName = item['table_name'] as String;
        final localId = item['local_id'] as int;
        final changeType = item['change_type'] as String;
        // firestoreId stored at queue-time for offline deletes (item may be gone from SQLite)
        final storedFirestoreId = item['data'] as String?;

        switch (tableName) {
          case 'albums':
            final albums = await _dbHelper.getAllAlbums();
            final album = albums.where((a) => a.id == localId).firstOrNull;
            if (album != null) {
              await pushAlbumChange(album, changeType);
            } else if (changeType == 'delete' && storedFirestoreId != null) {
              // Album already deleted locally; push the delete to Firestore directly.
              await _firestoreService.deleteAlbum(userId, storedFirestoreId);
            }
            // If album is null and no storedFirestoreId, it was never synced → nothing to do.
            break;
          case 'cards':
            final cards = await _dbHelper.getAllCards();
            final card = cards.where((c) => c.id == localId).firstOrNull;
            if (card != null) {
              await pushCardChange(card, changeType);
            } else if (changeType == 'delete' && storedFirestoreId != null) {
              // Card already deleted locally; push the delete to Firestore directly.
              await _firestoreService.deleteCard(userId, storedFirestoreId);
            }
            break;
          case 'decks':
            await pushDeckChange(localId, changeType);
            break;
        }

        await _dbHelper.clearPendingSync(id: item['id'] as int);
      } catch (e) { // ignore: empty_catches

        // Keep the item in the queue for next attempt
      }
    }
  }
}
