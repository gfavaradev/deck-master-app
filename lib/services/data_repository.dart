import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'sync_service.dart';
import 'auth_service.dart';
import '../constants/app_constants.dart';
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

  /// Check if catalog needs update
  /// Returns: { needsUpdate: bool, localVersion: int?, remoteVersion: int?, totalCards: int? }
  Future<Map<String, dynamic>> checkCatalogUpdates() async {
    if (kIsWeb) {
      // Web has no local SQLite catalog; catalog is always read directly from Firestore.
      return {'needsUpdate': false, 'totalCards': 0};
    }
    try {
      // Get remote metadata
      final remoteMetadata = await _firestoreService.getCatalogMetadata('yugioh');
      if (remoteMetadata == null) {
        return {'needsUpdate': false, 'error': 'Remote metadata not found'};
      }

      final remoteVersion = remoteMetadata['version'] as int? ?? 0;
      final remoteTotalCards = remoteMetadata['totalCards'] as int? ?? 0;

      // Get local metadata
      final localMetadata = await _dbHelper.getCatalogMetadata('yugioh');

      if (localMetadata == null) {
        // No local catalog - needs download
        return {
          'needsUpdate': true,
          'isFirstDownload': true,
          'remoteVersion': remoteVersion,
          'totalCards': remoteTotalCards,
        };
      }

      final localVersion = localMetadata['version'] as int? ?? 0;
      final localTotalCards = localMetadata['total_cards'] as int? ?? 0;

      // Compare versions
      if (remoteVersion > localVersion) {
        // Incremental update is only safe when exactly one version ahead and the
        // metadata contains the list of modified chunks from that single publish.
        final versionDiff = remoteVersion - localVersion;
        final modifiedChunks = remoteMetadata['modifiedChunks'] as List<dynamic>? ?? [];
        final canDoIncremental = versionDiff == 1 && modifiedChunks.isNotEmpty;
        return {
          'needsUpdate': true,
          'isFirstDownload': false,
          'localVersion': localVersion,
          'remoteVersion': remoteVersion,
          'localTotalCards': localTotalCards,
          'totalCards': remoteTotalCards,
          'canDoIncremental': canDoIncremental,
          'modifiedChunks': canDoIncremental ? modifiedChunks : [],
          'deletedCards': canDoIncremental
              ? (remoteMetadata['deletedCards'] as List<dynamic>? ?? [])
              : [],
        };
      }

      return {
        'needsUpdate': false,
        'localVersion': localVersion,
        'totalCards': localTotalCards,
        'lastUpdated': localMetadata['last_updated'],
      };
    } catch (e) {
      return {'needsUpdate': false, 'error': e.toString()};
    }
  }

  /// Converts a card from the new Firestore 'sets' format to the flat 'prints' format
  /// expected by [DatabaseHelper.insertYugiohCards].
  /// If the card already has 'prints' or no 'sets', it is returned unchanged.
  ///
  /// Localized sets are matched by derived set code (e.g. LOB-EN001 → LOB-IT001),
  /// not by array index, to avoid mismatches when arrays have different orderings.
  static Map<String, dynamic> _normalizeCardForSQLite(Map<String, dynamic> card) {
    if (card.containsKey('prints') || !card.containsKey('sets')) return card;
    final rawSets = card['sets'];
    if (rawSets is! Map) return card;

    List<Map<String, dynamic>> getSets(String l) {
      final s = rawSets[l];
      if (s is! List) return [];
      return s.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    final enSets = getSets('en');
    if (enSets.isEmpty) return card;

    // Build lookup maps keyed by "set_code\x00rarity" to correctly handle
    // cards that appear in the same set with multiple rarities (e.g. Common + Rare).
    // Using only set_code as key would cause later entries to overwrite earlier ones.
    Map<String, Map<String, dynamic>> buildLookup(List<Map<String, dynamic>> sets) =>
        {for (final s in sets)
          '${s['set_code']?.toString() ?? ''}\x00${s['rarity']?.toString() ?? ''}': s};

    final itLookup = buildLookup(getSets('it'));
    final frLookup = buildLookup(getSets('fr'));
    final deLookup = buildLookup(getSets('de'));
    final ptLookup = buildLookup(getSets('pt'));

    // Derives the localized set code from an EN set code.
    // e.g. LOB-EN001 → LOB-IT001  (2-letter prefix)
    //      LOB-E001  → LOB-I001   (1-letter prefix)
    // Returns null if the EN code has no recognisable language segment.
    String? toLocalCode(String enCode, String lang) {
      final match = RegExp(r'^([A-Z0-9]+)-(EN|E)(.+)$').firstMatch(enCode.toUpperCase());
      if (match == null) return null;
      final prefix = match.group(1)!;
      final isShort = match.group(2) == 'E';
      final num = match.group(3)!;
      return switch (lang) {
        'it' => '$prefix-${isShort ? 'I' : 'IT'}$num',
        'fr' => '$prefix-${isShort ? 'F' : 'FR'}$num',
        'de' => '$prefix-${isShort ? 'D' : 'DE'}$num',
        'pt' => '$prefix-${isShort ? 'P' : 'PT'}$num',
        _    => null,
      };
    }

    // Composite lookup key: "localizedSetCode\x00rarity"
    String lookupKey(String? code, String? rarity) =>
        '${code ?? ''}\x00${rarity ?? ''}';

    final fallbackArtworkUrl = 'https://images.ygoprodeck.com/images/cards/${card['id']}.jpg';

    final prints = enSets.map((en) {
      final enCode = en['set_code']?.toString() ?? '';
      final enRarity = en['rarity']?.toString() ?? '';
      final it = itLookup[lookupKey(toLocalCode(enCode, 'it'), enRarity)];
      final fr = frLookup[lookupKey(toLocalCode(enCode, 'fr'), enRarity)];
      final de = deLookup[lookupKey(toLocalCode(enCode, 'de'), enRarity)];
      final pt = ptLookup[lookupKey(toLocalCode(enCode, 'pt'), enRarity)];
      // Use per-set image_url if specified by admin, otherwise fall back to card-level artwork URL
      final artworkUrl = (en['image_url'] as String?)?.isNotEmpty == true
          ? en['image_url'] as String
          : fallbackArtworkUrl;
      return {
        'set_code':       en['set_code'],
        'set_name':       en['set_name'],
        'rarity':         en['rarity'],
        'rarity_code':    en['rarity_code'],
        'set_price':      en['set_price'],
        'artwork':        artworkUrl,
        'set_code_it':    it?['set_code'],  'set_name_it':    it?['set_name'],
        'rarity_it':      it?['rarity'],    'rarity_code_it': it?['rarity_code'],
        'set_price_it':   it?['set_price'],
        'set_code_fr':    fr?['set_code'],  'set_name_fr':    fr?['set_name'],
        'rarity_fr':      fr?['rarity'],    'rarity_code_fr': fr?['rarity_code'],
        'set_price_fr':   fr?['set_price'],
        'set_code_de':    de?['set_code'],  'set_name_de':    de?['set_name'],
        'rarity_de':      de?['rarity'],    'rarity_code_de': de?['rarity_code'],
        'set_price_de':   de?['set_price'],
        'set_code_pt':    pt?['set_code'],  'set_name_pt':    pt?['set_name'],
        'rarity_pt':      pt?['rarity'],    'rarity_code_pt': pt?['rarity_code'],
        'set_price_pt':   pt?['set_price'],
      };
    }).toList();

    // Prefer Firebase Storage URL (imageUrl) over the original API URL (image_url)
    final resolvedImageUrl = card['imageUrl'] as String? ?? card['image_url'] as String?;
    final updated = Map<String, dynamic>.from(card)
      ..remove('sets')
      ..['prints'] = prints
      ..['image_url'] = resolvedImageUrl;
    return updated;
  }

  Future<void> downloadYugiohCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
    Map<String, dynamic>? updateInfo,
  }) async {
    if (kIsWeb) return; // Web has no local SQLite catalog; reads from Firestore directly

    // Use incremental update when the update info confirms it is safe to do so
    if (updateInfo?['canDoIncremental'] == true) {
      final modifiedChunks = (updateInfo!['modifiedChunks'] as List<dynamic>)
          .cast<String>();
      final deletedCards = updateInfo['deletedCards'] as List<dynamic>? ?? [];
      await _applyIncrementalUpdate(
        modifiedChunks: modifiedChunks,
        deletedCardIds: deletedCards,
        onProgress: onProgress,
        onSaveProgress: onSaveProgress,
      );
      return;
    }

    // Full download
    final remoteMetadata = await _firestoreService.getCatalogMetadata('yugioh');

    final cards = await _firestoreService.fetchCatalog(
      CatalogConstants.yugioh,
      onProgress: onProgress,
    );

    if (cards.isEmpty) return;

    // Convert from new 'sets' format to flat 'prints' format expected by SQLite
    final normalizedCards = cards.map(_normalizeCardForSQLite).toList();

    await _dbHelper.insertYugiohCards(
      normalizedCards,
      onProgress: onSaveProgress,
    );

    // Save metadata after successful download.
    // A failure here is non-fatal: catalog data is intact; only version tracking
    // is lost, causing an unnecessary re-download on the next launch.
    if (remoteMetadata != null) {
      try {
        await _dbHelper.saveCatalogMetadata(
          catalogName: 'yugioh',
          version: remoteMetadata['version'] as int? ?? 1,
          totalCards: remoteMetadata['totalCards'] as int? ?? cards.length,
          totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
          lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
        );
      } catch (e) {
        debugPrint('Warning: failed to save catalog metadata: $e');
      }
    }
  }

  /// Applies an incremental catalog update: fetches only the modified chunks,
  /// deletes removed cards, upserts changed cards, and updates the local version.
  Future<void> _applyIncrementalUpdate({
    required List<String> modifiedChunks,
    required List<dynamic> deletedCardIds,
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    final remoteMetadata = await _firestoreService.getCatalogMetadata('yugioh');

    // Fetch only the chunks that changed
    final cards = await _firestoreService.fetchCatalogChunks(
      CatalogConstants.yugioh,
      modifiedChunks,
      onProgress: onProgress,
    );

    // Delete cards that were removed in this publish
    if (deletedCardIds.isNotEmpty) {
      final idsToDelete = deletedCardIds
          .whereType<num>()
          .map((id) => id.toInt())
          .toList();
      if (idsToDelete.isNotEmpty) {
        await _dbHelper.deleteYugiohCardsByIds(idsToDelete);
      }
    }

    // Upsert modified cards (INSERT OR REPLACE handles both add and edit)
    if (cards.isNotEmpty) {
      final normalizedCards = cards.map(_normalizeCardForSQLite).toList();
      await _dbHelper.insertYugiohCards(normalizedCards, onProgress: onSaveProgress);
    }

    // Update local metadata version so we don't re-download next time
    if (remoteMetadata != null) {
      try {
        await _dbHelper.saveCatalogMetadata(
          catalogName: 'yugioh',
          version: remoteMetadata['version'] as int? ?? 1,
          totalCards: remoteMetadata['totalCards'] as int? ?? 0,
          totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
          lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
        );
      } catch (e) {
        debugPrint('Warning: failed to save catalog metadata after incremental update: $e');
      }
    }
  }

  /// Cancella e riscarica il catalogo Yu-Gi-Oh da Firestore.
  ///
  /// La rete viene interrogata PRIMA di cancellare il catalogo locale:
  /// se il download fallisce, SQLite rimane intatto.
  Future<void> redownloadYugiohCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    if (kIsWeb) return; // Web has no local SQLite catalog

    // Step 1: fetch all data from Firestore while SQLite is still intact.
    final remoteMetadata = await _firestoreService.getCatalogMetadata('yugioh');
    final cards = await _firestoreService.fetchCatalog(
      CatalogConstants.yugioh,
      onProgress: onProgress,
    );
    if (cards.isEmpty) return;

    final normalizedCards = cards.map(_normalizeCardForSQLite).toList();

    // Step 2: clear old catalog and insert new data.
    // Both operations are individually atomic (SQLite transactions); if insert
    // fails it rolls back, leaving empty tables — but catalog_metadata was also
    // deleted by clearYugiohCatalog so the app will detect isFirstDownload=true
    // on the next launch and retry automatically.
    await _dbHelper.clearYugiohCatalog();
    await _dbHelper.insertYugiohCards(normalizedCards, onProgress: onSaveProgress);

    // Step 3: persist metadata (version number used for update detection).
    if (remoteMetadata != null) {
      try {
        await _dbHelper.saveCatalogMetadata(
          catalogName: 'yugioh',
          version: remoteMetadata['version'] as int? ?? 1,
          totalCards: remoteMetadata['totalCards'] as int? ?? cards.length,
          totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
          lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ??
              DateTime.now().toIso8601String(),
        );
      } catch (e) {
        // Catalog data is already saved; metadata failure only causes an
        // unnecessary re-download on the next launch — not a data-loss risk.
        debugPrint('Warning: failed to save catalog metadata: $e');
      }
    }
  }

  // ============================================================
  // Collections (read from SQLite, sync unlock to Firestore)
  // ============================================================

  // Static list of available collections (mirrors SQLite _onCreate seed)
  static const List<Map<String, String>> _staticCollections = [
    {'id': 'yugioh', 'name': 'Yu-Gi-Oh!'},
    {'id': 'pokemon', 'name': 'Pokémon'},
    {'id': 'magic', 'name': 'Magic: The Gathering'},
    {'id': 'onepiece', 'name': 'One Piece'},
  ];

  Future<List<CollectionModel>> getCollections() async {
    if (kIsWeb) {
      // Web has no SQLite: build list from hardcoded data + Firestore unlock status
      final userId = _authService.currentUserId;
      Set<String> unlockedKeys = {};
      if (userId != null) {
        try {
          final remote = await _firestoreService.getCollections(userId);
          unlockedKeys = remote.where((c) => c.isUnlocked).map((c) => c.key).toSet();
        } catch (e) {
          debugPrint('Web getCollections Firestore error: $e');
        }
      }
      return _staticCollections.map((c) => CollectionModel(
        key: c['id']!,
        name: c['name']!,
        isUnlocked: unlockedKeys.contains(c['id']!),
      )).toList();
    }
    return await _dbHelper.getCollections();
  }

  Future<void> unlockCollection(String collectionKey) async {
    if (!kIsWeb) {
      await _dbHelper.unlockCollection(collectionKey);
    }
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

  Future<CardModel?> findCardInAlbum(int albumId, String? catalogId, String serialNumber, String rarity) async {
    if (kIsWeb) return null;
    return await _dbHelper.findCardInAlbum(albumId, catalogId, serialNumber, rarity);
  }

  // ============================================================
  // Catalog Methods (read-only from SQLite, or Firestore on web)
  // ============================================================

  /// In-memory cache for web catalog, keyed by language code.
  static final Map<String, List<Map<String, dynamic>>> _webCatalogCache = {};

  Future<List<Map<String, dynamic>>> getCatalogCards(String collection, {String? query}) async {
    return await _dbHelper.getCatalogCards(collection, query: query);
  }

  Future<List<Map<String, dynamic>>> getYugiohCatalogCards({
    String? query,
    required String language,
    int limit = 60,
    int offset = 0,
  }) async {
    if (kIsWeb) {
      return _getYugiohCatalogCardsWeb(
        query: query, language: language, limit: limit, offset: offset,
      );
    }
    return await _dbHelper.getYugiohCatalogCards(
      query: query,
      language: language,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> _getYugiohCatalogCardsWeb({
    String? query,
    required String language,
    int limit = 60,
    int offset = 0,
  }) async {
    final lang = language.toLowerCase();

    // Build & cache rows for this language
    if (!_webCatalogCache.containsKey(lang)) {
      final firestoreCards = await _firestoreService.fetchCatalog('yugioh');
      _webCatalogCache[lang] = _buildWebCatalogRows(firestoreCards, lang);
    }

    var rows = _webCatalogCache[lang]!;

    // Apply search filter
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      rows = rows.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();
        final localizedName = (r['localizedName'] ?? '').toString().toLowerCase();
        final setCode = (r['localizedSetCode'] ?? r['setCode'] ?? '').toString().toLowerCase();
        return name.contains(q) || localizedName.contains(q) || setCode.contains(q);
      }).toList();
    }

    if (offset >= rows.length) return [];
    return rows.sublist(offset, (offset + limit).clamp(0, rows.length));
  }

  static List<Map<String, dynamic>> _buildWebCatalogRows(
    List<Map<String, dynamic>> cards,
    String lang,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final card in cards) {
      final rawSets = card['sets'];
      if (rawSets is! Map) continue;

      final langSets = rawSets[lang];
      final enSets = rawSets['en'];

      // Use target-language sets when available, fall back to EN
      final List<dynamic> setsToShow = (langSets is List && langSets.isNotEmpty)
          ? langSets
          : (enSets is List ? enSets : []);
      final bool isLocalized = langSets is List && langSets.isNotEmpty;

      final cardId = card['id'];
      final artworkUrl = 'https://images.ygoprodeck.com/images/cards/$cardId.jpg';

      for (final set in setsToShow.cast<Map<String, dynamic>>()) {
        rows.add({
          'id':                   cardId,
          'name':                 card['name'] ?? '',
          'localizedName':        card['name_$lang'] ?? card['name'] ?? '',
          'description':          card['description'] ?? '',
          'localizedDescription': card['description_$lang'] ?? card['description'] ?? '',
          'type':                 card['type'] ?? '',
          'humanReadableCardType': card['human_readable_type'] ?? card['type'] ?? '',
          'frameType':            card['frame_type'] ?? '',
          'race':                 card['race'] ?? '',
          'archetype':            card['archetype'],
          'attribute':            card['attribute'] ?? '',
          'atk': card['atk'], 'def': card['def'], 'level': card['level'],
          'scale': card['scale'], 'linkval': card['linkval'],
          'linkmarkers':          card['linkmarkers'],
          'ygoprodeck_url':       card['ygoprodeck_url'] ?? '',
          'printId':              null,
          'setCode':              set['set_code'] ?? '',
          'localizedSetCode':     set['set_code'] ?? '',
          'setName':              set['set_name'] ?? '',
          'localizedSetName':     set['set_name'] ?? '',
          'setRarity':            set['rarity'] ?? '',
          'localizedRarity':      set['rarity'] ?? '',
          'rarityCode':           set['rarity_code'] ?? '',
          'localizedRarityCode':  set['rarity_code'] ?? '',
          'setPrice':             set['set_price'],
          'localizedSetPrice':    set['set_price'],
          'artwork':              artworkUrl,
          'collection':           'yugioh',
          'isLocalizedPrint':     isLocalized ? 1 : 0,
          'isOwned':              0,
        });
      }
    }
    return rows;
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
    if (kIsWeb) {
      // On web there is no local SQLite cache; return zeroed stats.
      return {'totalCards': 0, 'totalValue': 0.0, 'unlockedCollections': 0};
    }
    return await _dbHelper.getGlobalStats();
  }

  // ============================================================
  // Decks (write-through: SQLite + Firestore)
  // ============================================================

  Future<int> insertDeck(String name, String collection) async {
    final localId = await _dbHelper.insertDeck(name, collection);
    // Push to Firestore
    try {
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
    } catch (e) {
      debugPrint('Error in deck sync flow: $e');
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

  Future<List<Map<String, dynamic>>> getDecksForCard(int cardId) async {
    return await _dbHelper.getDecksForCard(cardId);
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
