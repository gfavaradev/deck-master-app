import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  bool _isSyncing = false;

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
        final localDeckId = deck['id'] as int;
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

      debugPrint('Initial upload completed successfully');
    } catch (e) {
      debugPrint('Error during initial upload: $e');
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
      // Pull collections
      final remoteCollections = await _firestoreService.getCollections(userId);
      for (var col in remoteCollections) {
        if (col.isUnlocked) {
          await _dbHelper.unlockCollection(col.key);
        }
      }

      // Clear existing user data before pulling
      await _dbHelper.clearUserData();

      // Pull albums
      final remoteAlbums = await _firestoreService.getAlbums(userId);
      final Map<String, int> firestoreToLocalAlbumId = {};

      for (var albumData in remoteAlbums) {
        final album = AlbumModel(
          name: albumData['name'],
          collection: albumData['collection'],
          maxCapacity: albumData['maxCapacity'] ?? 100,
        );
        final localId = await _dbHelper.insertAlbum(album);
        final firestoreId = albumData['firestoreId'] as String;
        await _dbHelper.updateFirestoreId('albums', localId, firestoreId);
        firestoreToLocalAlbumId[firestoreId] = localId;
      }

      // Pull cards
      final remoteCards = await _firestoreService.getCards(userId);
      for (var cardData in remoteCards) {
        // Map albumFirestoreId back to local albumId
        int albumId = cardData['albumId'] ?? -1;
        final albumFirestoreId = cardData['albumFirestoreId'] as String?;
        if (albumFirestoreId != null && firestoreToLocalAlbumId.containsKey(albumFirestoreId)) {
          albumId = firestoreToLocalAlbumId[albumFirestoreId]!;
        }

        final card = CardModel(
          catalogId: cardData['catalogId'],
          name: cardData['name'] ?? '',
          serialNumber: cardData['serialNumber'] ?? '',
          collection: cardData['collection'] ?? '',
          albumId: albumId,
          type: cardData['type'] ?? '',
          rarity: cardData['rarity'] ?? '',
          description: cardData['description'] ?? '',
          quantity: cardData['quantity'] ?? 1,
          value: (cardData['value'] as num?)?.toDouble() ?? 0.0,
          imageUrl: cardData['imageUrl'],
        );
        final localId = await _dbHelper.insertCard(card);
        await _dbHelper.updateFirestoreId('cards', localId, cardData['firestoreId']);
      }

      // Pull decks
      final remoteDecks = await _firestoreService.getDecks(userId);
      for (var deckData in remoteDecks) {
        final localDeckId = await _dbHelper.insertDeck(
          deckData['name'],
          deckData['collection'],
        );
        await _dbHelper.updateFirestoreId('decks', localDeckId, deckData['firestoreId']);

        // Deck cards are embedded - we'd need the local card IDs
        // For now, deck card sync is best-effort
        final List<dynamic> deckCards = deckData['cards'] ?? [];
        for (var dc in deckCards) {
          try {
            await _dbHelper.addCardToDeck(
              localDeckId,
              dc['cardId'] as int,
              dc['quantity'] as int,
            );
          } catch (_) {
            // Card might not exist locally yet, skip
          }
        }
      }

      await _dbHelper.clearPendingSync();
      debugPrint('Pull from cloud completed successfully');
    } catch (e) {
      debugPrint('Error during pull from cloud: $e');
      rethrow;
    }
  }

  // ============================================================
  // Sync on Login: Decide whether to push or pull
  // ============================================================

  Future<void> syncOnLogin() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final userId = _userId;
      if (userId == null) return;

      final hasRemoteData = await _firestoreService.hasUserData(userId);
      final localAlbums = await _dbHelper.getAllAlbums();
      final localCards = await _dbHelper.getAllCards();

      final hasLocalData = localAlbums.isNotEmpty || localCards.isNotEmpty;

      if (hasRemoteData && !hasLocalData) {
        // New device or fresh install: pull from cloud
        await pullFromCloud();
      } else if (hasLocalData && !hasRemoteData) {
        // First time login with existing local data: push to cloud
        await initialUpload();
      } else if (hasRemoteData && hasLocalData) {
        // Both exist: flush pending queue then pull updates
        await flushPendingQueue();
      }
      // If neither has data, nothing to do
    } catch (e) {
      debugPrint('Error during sync on login: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ============================================================
  // Push Single Change (called after local writes)
  // ============================================================

  Future<void> pushAlbumChange(AlbumModel album, String changeType) async {
    if (!await canSync()) {
      if (album.id != null) {
        await _dbHelper.addPendingSync('albums', album.id!, changeType);
      }
      return;
    }

    final userId = _userId;
    if (userId == null) return;

    try {
      switch (changeType) {
        case 'insert':
          final firestoreId = await _firestoreService.insertAlbum(userId, album);
          if (album.id != null) {
            await _dbHelper.updateFirestoreId('albums', album.id!, firestoreId);
          }
          break;
        case 'update':
          if (album.firestoreId != null) {
            await _firestoreService.updateAlbum(userId, album.firestoreId!, album);
          }
          break;
        case 'delete':
          if (album.firestoreId != null) {
            await _firestoreService.deleteAlbum(userId, album.firestoreId!);
          }
          break;
      }
    } catch (e) {
      debugPrint('Error pushing album change: $e');
      if (album.id != null) {
        await _dbHelper.addPendingSync('albums', album.id!, changeType);
      }
    }
  }

  Future<void> pushCardChange(CardModel card, String changeType) async {
    if (!await canSync()) {
      if (card.id != null) {
        await _dbHelper.addPendingSync('cards', card.id!, changeType);
      }
      return;
    }

    final userId = _userId;
    if (userId == null) return;

    try {
      switch (changeType) {
        case 'insert':
          // Get the album's firestoreId for the reference
          String? albumFirestoreId;
          if (card.albumId > 0) {
            albumFirestoreId = await _dbHelper.getFirestoreId('albums', card.albumId);
          }
          final firestoreId = await _firestoreService.insertCard(
            userId,
            card,
            albumFirestoreId: albumFirestoreId,
          );
          if (card.id != null) {
            await _dbHelper.updateFirestoreId('cards', card.id!, firestoreId);
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
            );
          }
          break;
        case 'delete':
          if (card.firestoreId != null) {
            await _firestoreService.deleteCard(userId, card.firestoreId!);
          }
          break;
      }
    } catch (e) {
      debugPrint('Error pushing card change: $e');
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
        case 'delete':
          if (firestoreId != null) {
            await _firestoreService.deleteDeck(userId, firestoreId);
          }
          break;
      }
    } catch (e) {
      debugPrint('Error pushing deck change: $e');
      await _dbHelper.addPendingSync('decks', deckId, changeType);
    }
  }

  Future<void> pushCollectionUnlock(String collectionKey) async {
    if (!await canSync()) return;
    final userId = _userId;
    if (userId == null) return;

    try {
      await _firestoreService.setCollectionUnlocked(userId, collectionKey, true);
    } catch (e) {
      debugPrint('Error pushing collection unlock: $e');
    }
  }

  // ============================================================
  // Flush Pending Queue
  // ============================================================

  Future<void> flushPendingQueue() async {
    if (!await canSync()) return;

    final pending = await _dbHelper.getPendingSync();
    if (pending.isEmpty) return;

    debugPrint('Flushing ${pending.length} pending sync operations');

    for (var item in pending) {
      try {
        final tableName = item['table_name'] as String;
        final localId = item['local_id'] as int;
        final changeType = item['change_type'] as String;

        switch (tableName) {
          case 'albums':
            final albums = await _dbHelper.getAllAlbums();
            final album = albums.where((a) => a.id == localId).firstOrNull;
            if (album != null) {
              await pushAlbumChange(album, changeType);
            }
            break;
          case 'cards':
            final cards = await _dbHelper.getAllCards();
            final card = cards.where((c) => c.id == localId).firstOrNull;
            if (card != null) {
              await pushCardChange(card, changeType);
            }
            break;
          case 'decks':
            await pushDeckChange(localId, changeType);
            break;
        }

        await _dbHelper.clearPendingSync(id: item['id'] as int);
      } catch (e) {
        debugPrint('Error flushing pending sync item ${item['id']}: $e');
        // Keep the item in the queue for next attempt
      }
    }
  }
}
