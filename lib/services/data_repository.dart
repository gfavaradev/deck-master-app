import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'sync_service.dart';
import 'auth_service.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';
import '../models/collection_model.dart';

/// Facade over DatabaseHelper + FirestoreService.
/// All pages should use this instead of DatabaseHelper directly.
/// Reads come from SQLite (fast, offline).
/// Writes go to SQLite first, then push to Firestore if online.
class DataRepository {
  static final DataRepository _instance = DataRepository._internal();
  factory DataRepository() => _instance;
  DataRepository._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  // ============================================================
  // Yu-Gi-Oh Catalog (from Firestore)
  // ============================================================

  Future<void> downloadYugiohCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    final cards = await _firestoreService.fetchYugiohCatalog(
      onProgress: onProgress,
    );

    if (cards.isEmpty) return;

    await _dbHelper.insertYugiohCards(
      cards,
      onProgress: onSaveProgress,
    );
  }

  /// Cancella e riscarica il catalogo Yu-Gi-Oh da Firestore
  Future<void> redownloadYugiohCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    await _dbHelper.clearYugiohCatalog();
    await downloadYugiohCatalog(
      onProgress: onProgress,
      onSaveProgress: onSaveProgress,
    );
  }

  // ============================================================
  // Collections (read from SQLite, sync unlock to Firestore)
  // ============================================================

  Future<List<CollectionModel>> getCollections() async {
    return await _dbHelper.getCollections();
  }

  Future<void> unlockCollection(String collectionKey) async {
    await _dbHelper.unlockCollection(collectionKey);
    await _syncService.pushCollectionUnlock(collectionKey);
  }

  // ============================================================
  // Albums (write-through: SQLite + Firestore)
  // ============================================================

  Future<int> insertAlbum(AlbumModel album) async {
    final localId = await _dbHelper.insertAlbum(album);
    final savedAlbum = album.copyWith(id: localId);
    await _syncService.pushAlbumChange(savedAlbum, 'insert');
    return localId;
  }

  Future<List<AlbumModel>> getAlbumsByCollection(String collection) async {
    return await _dbHelper.getAlbumsByCollection(collection);
  }

  Future<int> updateAlbum(AlbumModel album) async {
    final result = await _dbHelper.updateAlbum(album);
    // Re-read to get firestoreId
    final albums = await _dbHelper.getAlbumsByCollection(album.collection);
    final updated = albums.firstWhere((a) => a.id == album.id, orElse: () => album);
    await _syncService.pushAlbumChange(updated, 'update');
    return result;
  }

  Future<int> deleteAlbum(int id) async {
    // Get firestoreId before deleting
    final firestoreId = await _dbHelper.getFirestoreId('albums', id);
    final result = await _dbHelper.deleteAlbum(id);
    if (firestoreId != null) {
      final placeholder = AlbumModel(id: id, firestoreId: firestoreId, name: '', collection: '', maxCapacity: 0);
      await _syncService.pushAlbumChange(placeholder, 'delete');
    }
    return result;
  }

  // ============================================================
  // Cards (write-through: SQLite + Firestore)
  // ============================================================

  Future<int> insertCard(CardModel card) async {
    final localId = await _dbHelper.insertCard(card);
    final savedCard = card.copyWith(id: localId);
    await _syncService.pushCardChange(savedCard, 'insert');
    return localId;
  }

  Future<int> updateCard(CardModel card) async {
    final result = await _dbHelper.updateCard(card);
    // Re-read to get firestoreId
    final firestoreId = card.id != null ? await _dbHelper.getFirestoreId('cards', card.id!) : null;
    final updatedCard = card.copyWith(firestoreId: firestoreId);
    await _syncService.pushCardChange(updatedCard, 'update');
    return result;
  }

  Future<int> deleteCard(int id) async {
    final firestoreId = await _dbHelper.getFirestoreId('cards', id);
    final result = await _dbHelper.deleteCard(id);
    if (firestoreId != null) {
      final placeholder = CardModel(
        id: id,
        firestoreId: firestoreId,
        name: '',
        serialNumber: '',
        collection: '',
        albumId: -1,
        type: '',
        rarity: '',
        description: '',
      );
      await _syncService.pushCardChange(placeholder, 'delete');
    }
    return result;
  }

  Future<List<CardModel>> getCardsByCollection(String collection) async {
    return await _dbHelper.getCardsByCollection(collection);
  }

  Future<List<CardModel>> getCardsWithCatalog(String collection) async {
    return await _dbHelper.getCardsWithCatalog(collection);
  }

  Future<List<CardModel>> findOwnedInstances(String collection, String name, String serialNumber) async {
    return await _dbHelper.findOwnedInstances(collection, name, serialNumber);
  }

  Future<int> getCardCountByAlbum(int albumId) async {
    return await _dbHelper.getCardCountByAlbum(albumId);
  }

  // ============================================================
  // Catalog Methods (read-only from SQLite)
  // ============================================================

  Future<List<Map<String, dynamic>>> getCatalogCards(String collection, {String? query}) async {
    return await _dbHelper.getCatalogCards(collection, query: query);
  }

  Future<List<Map<String, dynamic>>> getYugiohCatalogCards({
    String? query,
    required String language,
    int limit = 60,
    int offset = 0,
  }) async {
    return await _dbHelper.getYugiohCatalogCards(
      query: query,
      language: language,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> getYugiohCardPrints(int cardId, {required String language}) async {
    return await _dbHelper.getYugiohCardPrints(cardId, language: language);
  }

  Future<List<Map<String, dynamic>>> getCardSets(String cardId) async {
    return await _dbHelper.getCardSets(cardId);
  }

  Future<int> getCatalogCount(String collection) async {
    return await _dbHelper.getCatalogCount(collection);
  }

  Future<int> getYugiohCatalogCount() async {
    return await _dbHelper.getYugiohCatalogCount();
  }

  // ============================================================
  // Stats (read from SQLite)
  // ============================================================

  Future<Map<String, dynamic>> getGlobalStats() async {
    return await _dbHelper.getGlobalStats();
  }

  // ============================================================
  // Decks (write-through: SQLite + Firestore)
  // ============================================================

  Future<int> insertDeck(String name, String collection) async {
    final localId = await _dbHelper.insertDeck(name, collection);
    // Push to Firestore
    if (await _syncService.canSync()) {
      try {
        final userId = _authService.currentUserId;
        if (userId != null) {
          final firestoreId = await _firestoreService.insertDeck(userId, name, collection);
          await _dbHelper.updateFirestoreId('decks', localId, firestoreId);
        }
      } catch (e) {
        debugPrint('Error syncing deck insert: $e');
        await _dbHelper.addPendingSync('decks', localId, 'insert');
      }
    } else {
      await _dbHelper.addPendingSync('decks', localId, 'insert');
    }
    return localId;
  }

  Future<List<Map<String, dynamic>>> getDecksByCollection(String collection) async {
    return await _dbHelper.getDecksByCollection(collection);
  }

  Future<int> deleteDeck(int id) async {
    final firestoreId = await _dbHelper.getFirestoreId('decks', id);
    final result = await _dbHelper.deleteDeck(id);
    if (firestoreId != null) {
      await _syncService.pushDeckChange(id, 'delete');
    }
    return result;
  }

  Future<void> addCardToDeck(int deckId, int cardId, int quantity) async {
    await _dbHelper.addCardToDeck(deckId, cardId, quantity);
    // Sync deck card addition
    if (await _syncService.canSync()) {
      try {
        final userId = _authService.currentUserId;
        final firestoreId = await _dbHelper.getFirestoreId('decks', deckId);
        if (userId != null && firestoreId != null) {
          await _firestoreService.addCardToDeck(userId, firestoreId, cardId, quantity);
        }
      } catch (e) {
        debugPrint('Error syncing deck card add: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getDeckCards(int deckId) async {
    return await _dbHelper.getDeckCards(deckId);
  }

  Future<void> removeCardFromDeck(int deckId, int cardId) async {
    await _dbHelper.removeCardFromDeck(deckId, cardId);
    // Sync deck card removal
    if (await _syncService.canSync()) {
      try {
        final userId = _authService.currentUserId;
        final firestoreId = await _dbHelper.getFirestoreId('decks', deckId);
        if (userId != null && firestoreId != null) {
          await _firestoreService.removeCardFromDeck(userId, firestoreId, cardId);
        }
      } catch (e) {
        debugPrint('Error syncing deck card remove: $e');
      }
    }
  }

  // ============================================================
  // Sync Operations
  // ============================================================

  Future<void> syncOnLogin() async {
    await _syncService.syncOnLogin();
  }

  Future<void> fullSync() async {
    await _syncService.flushPendingQueue();
  }

  Future<void> insertYugiohCards(List<Map<String, dynamic>> cards, {Function(double)? onProgress}) async {
    await _dbHelper.insertYugiohCards(cards, onProgress: onProgress);
  }
}
