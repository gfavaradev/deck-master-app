import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'sync_service.dart';
import 'auth_service.dart';
import 'cardtrader_service.dart';
import 'language_service.dart';
import 'xp_service.dart';
import '../constants/app_constants.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';
import '../models/collection_model.dart';

// Top-level functions so compute() can spawn them in a background isolate.
List<Map<String, dynamic>> _normalizeYugiohBatch(List<Map<String, dynamic>> cards) =>
    cards.map(DataRepository._normalizeCardForSQLite).toList();

List<Map<String, dynamic>> _normalizePokemonBatch(List<Map<String, dynamic>> cards) =>
    cards.map(DataRepository._normalizePokemonCardForSQLite).toList();

/// Facade over DatabaseHelper + FirestoreService.
/// All pages should use this instead of DatabaseHelper directly.
/// Reads come from SQLite (fast, offline).
/// Writes go to SQLite first, then push to Firestore if online.
class DataRepository {
  static final DataRepository _instance = DataRepository._internal();
  factory DataRepository() => _instance;
  DataRepository._internal() {
    SyncService().registerCatalogPriceUpdateListener(_onCatalogPriceUpdate);
  }

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  // ── Pending catalog updates (persisted across sessions) ──────────────────

  static const kPendingCatalogUpdatesKey = 'pending_catalog_updates';

  static String _catalogDisplayName(String key) => switch (key) {
    'yugioh'   => 'Yu-Gi-Oh!',
    'pokemon'  => 'Pokémon',
    'onepiece' => 'One Piece TCG',
    _          => key,
  };

  Future<void> savePendingCatalogUpdate(String catalog, Map<String, dynamic> updateInfo) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = loadPendingCatalogUpdatesFromPrefs(prefs);
    pending.removeWhere((u) => u['collectionKey'] == catalog);
    pending.add({...updateInfo, 'collectionKey': catalog, 'collectionName': _catalogDisplayName(catalog)});
    await prefs.setString(kPendingCatalogUpdatesKey, jsonEncode(pending));
  }

  static List<Map<String, dynamic>> loadPendingCatalogUpdatesFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(kPendingCatalogUpdatesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) { return []; }
  }

  Future<void> clearPendingCatalogUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPendingCatalogUpdatesKey);
  }

  // Called by SyncService when the admin has embedded new prices in Firestore
  // catalog chunks. Instead of auto-downloading, saves a pending flag so the
  // user can manually trigger the download via the cloud icon in the AppBar.
  Future<void> _onCatalogPriceUpdate(String catalog, List<String> chunkIds) async {
    try {
      if (_isDownloadingCatalog) return;
      final localMeta = await _dbHelper.getCatalogMetadata(catalog);
      if (localMeta == null) return; // catalogo non ancora scaricato su questo device
      await savePendingCatalogUpdate(catalog, {
        'canDoIncremental': true,
        'modifiedChunks': chunkIds,
        'deletedCards': <dynamic>[],
        'isFirstDownload': false,
      });
      _syncService.notifyLocalChange('catalog_update_pending');
    } catch (_) {}
  }

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
    } catch (e) { // ignore: empty_catches
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
    final spLookup = buildLookup(getSets('sp')); // BUG #13 fix: spagnolo YGO
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
        'sp' => '$prefix-${isShort ? 'S' : 'SP'}$num', // BUG #13 fix
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
      final sp = spLookup[lookupKey(toLocalCode(enCode, 'sp'), enRarity)]; // BUG #13
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
        'set_code_sp':    sp?['set_code'],  'set_name_sp':    sp?['set_name'],
        'rarity_sp':      sp?['rarity'],    'rarity_code_sp': sp?['rarity_code'],
        'set_price_sp':   sp?['set_price'],
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

  /// Converts a Pokémon card from the Firestore `sets`-map format to the flat
  /// `prints` list expected by [DatabaseHelper.insertPokemonCards].
  /// Cards already in the old `prints` format are passed through unchanged.
  static Map<String, dynamic> _normalizePokemonCardForSQLite(Map<String, dynamic> card) {
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

    // For Pokémon, all languages share the same set_code (api_id).
    final itByCode = {for (final s in getSets('it')) s['set_code']?.toString() ?? '': s};
    final frByCode = {for (final s in getSets('fr')) s['set_code']?.toString() ?? '': s};
    final deByCode = {for (final s in getSets('de')) s['set_code']?.toString() ?? '': s};
    final esByCode = {for (final s in getSets('es')) s['set_code']?.toString() ?? '': s};
    final ptByCode = {for (final s in getSets('pt')) s['set_code']?.toString() ?? '': s};

    final prints = enSets.map((en) {
      final code = en['set_code']?.toString() ?? '';
      final it = itByCode[code];
      final fr = frByCode[code];
      final de = deByCode[code];
      final es = esByCode[code];
      final pt = ptByCode[code];
      return {
        'set_code': code,
        'set_name': en['set_name'],
        'rarity':   en['rarity'],
        'set_price': en['set_price'],
        'artwork':   en['image_url'],
        'set_code_it': code, 'set_name_it': it?['set_name'], 'rarity_it': it?['rarity'], 'set_price_it': it?['set_price'],
        'set_code_fr': code, 'set_name_fr': fr?['set_name'], 'rarity_fr': fr?['rarity'], 'set_price_fr': fr?['set_price'],
        'set_code_de': code, 'set_name_de': de?['set_name'], 'rarity_de': de?['rarity'], 'set_price_de': de?['set_price'],
        'set_code_es': code, 'set_name_es': es?['set_name'], 'rarity_es': es?['rarity'], 'set_price_es': es?['set_price'],
        'set_code_pt': code, 'set_name_pt': pt?['set_name'], 'rarity_pt': pt?['rarity'], 'set_price_pt': pt?['set_price'],
      };
    }).toList();

    final resolvedImageUrl = card['imageUrl'] as String? ?? card['image_url'] as String?;
    return Map<String, dynamic>.from(card)
      ..remove('sets')
      ..['prints'] = prints
      ..['image_url'] = resolvedImageUrl;
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

    // Full download — stream one batch at a time to avoid OOM
    final remoteMetadata = await _firestoreService.getCatalogMetadata('yugioh');
    int totalDownloaded = 0;

    await _firestoreService.streamCatalog(
      CatalogConstants.yugioh,
      onBatch: (cards, chunksDone, chunksTotal) async {
        onProgress?.call(chunksDone, chunksTotal);
        await Future.delayed(Duration.zero); // yield UI frame before heavy work
        final normalized = await compute(_normalizeYugiohBatch, cards);
        await _dbHelper.insertYugiohCards(normalized);
        totalDownloaded += cards.length;
        onSaveProgress?.call(chunksDone / chunksTotal);
      },
    );

    if (totalDownloaded == 0) return;

    if (remoteMetadata != null) {
      try {
        await _dbHelper.saveCatalogMetadata(
          catalogName: 'yugioh',
          version: remoteMetadata['version'] as int? ?? 1,
          totalCards: remoteMetadata['totalCards'] as int? ?? totalDownloaded,
          totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
          lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
        );
      } catch (e) { // ignore: empty_catches
      }
    }

    try { await CardtraderService().applyLocalPricesToCollection('yugioh'); } catch (_) {}
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
      } catch (e) { // ignore: empty_catches

      }
    }

    try { await CardtraderService().applyLocalPricesToCollection('yugioh'); } catch (_) {}
  }

  Future<void> redownloadYugiohCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    if (kIsWeb) return;
    await _dbHelper.clearYugiohCatalog();
    await downloadYugiohCatalog(onProgress: onProgress, onSaveProgress: onSaveProgress);
    await _dbHelper.rebuildExpansionsAndRarities('yugioh');
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
        } catch (e) { // ignore: empty_catches

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
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return -1;
      final firestoreId = await _firestoreService.insertAlbum(userId, album);
      return _webGetAlbumLocalId(firestoreId);
    }
    final localId = await _dbHelper.insertAlbum(album);
    final savedAlbum = album.copyWith(id: localId);
    await _syncService.pushAlbumChange(savedAlbum, 'insert');
    _syncService.notifyLocalChange('albums');
    return localId;
  }

  Future<List<AlbumModel>> getAlbumsByCollection(String collection) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return [];
      final rawAlbums = await _firestoreService.getAlbums(userId);
      return rawAlbums
          .where((a) => a['collection'] == collection)
          .map((a) {
        final fid = a['firestoreId'] as String;
        return AlbumModel(
          id: _webGetAlbumLocalId(fid),
          firestoreId: fid,
          name: a['name'] ?? '',
          collection: a['collection'] ?? '',
          maxCapacity: a['maxCapacity'] ?? 100,
        );
      }).toList();
    }
    return await _dbHelper.getAlbumsByCollection(collection);
  }

  Future<int> updateAlbum(AlbumModel album) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return 0;
      final firestoreId = album.firestoreId ??
          (album.id != null ? _webAlbumFirestoreIdById[album.id!] : null);
      if (firestoreId != null) {
        await _firestoreService.updateAlbum(userId, firestoreId, album);
      }
      return 0;
    }
    final result = await _dbHelper.updateAlbum(album);
    _syncService.notifyLocalChange('albums');
    // Re-read to get firestoreId
    final albums = await _dbHelper.getAlbumsByCollection(album.collection);
    final updated = albums.firstWhere((a) => a.id == album.id, orElse: () => album);
    await _syncService.pushAlbumChange(updated, 'update');
    return result;
  }

  Future<int> deleteAlbum(int id) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return 0;
      final firestoreId = _webAlbumFirestoreIdById[id];
      if (firestoreId != null) {
        await _firestoreService.deleteAlbum(userId, firestoreId);
        _webAlbumFirestoreIdById.remove(id);
        _webAlbumIdByFirestoreId.remove(firestoreId);
      }
      return 0;
    }
    // Get firestoreId before deleting
    final firestoreId = await _dbHelper.getFirestoreId('albums', id);
    final result = await _dbHelper.deleteAlbum(id);
    _syncService.notifyLocalChange('albums');
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
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return -1;
      final albumFirestoreId = _webAlbumFirestoreIdById[card.albumId];
      final firestoreId = await _firestoreService.insertCard(
        userId, card, albumFirestoreId: albumFirestoreId,
      );
      return _webGetCardLocalId(firestoreId);
    }
    final localId = await _dbHelper.insertCard(card);
    final savedCard = card.copyWith(id: localId);
    await _syncService.pushCardChange(savedCard, 'insert');
    _syncService.notifyLocalChange('cards');
    return localId;
  }

  Future<int> updateCard(CardModel card) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return 0;
      final firestoreId = card.firestoreId ??
          (card.id != null ? _webCardFirestoreIdById[card.id!] : null);
      if (firestoreId != null) {
        final albumFirestoreId = _webAlbumFirestoreIdById[card.albumId];
        await _firestoreService.updateCard(
          userId, firestoreId, card, albumFirestoreId: albumFirestoreId,
        );
      }
      return 0;
    }
    final result = await _dbHelper.updateCard(card);
    // Re-read to get firestoreId
    _syncService.notifyLocalChange('cards');
    final firestoreId = card.id != null ? await _dbHelper.getFirestoreId('cards', card.id!) : null;
    final updatedCard = card.copyWith(firestoreId: firestoreId);
    await _syncService.pushCardChange(updatedCard, 'update');
    return result;
  }

  Future<int> deleteCard(int id) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return 0;
      final firestoreId = _webCardFirestoreIdById[id];
      if (firestoreId != null) {
        await _firestoreService.deleteCard(userId, firestoreId);
        _webCardFirestoreIdById.remove(id);
        _webCardIdByFirestoreId.remove(firestoreId);
      }
      return 0;
    }
    final firestoreId = await _dbHelper.getFirestoreId('cards', id);
    final result = await _dbHelper.deleteCard(id);
    _syncService.notifyLocalChange('cards');
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
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return [];
      final rawCards = await _firestoreService.getCards(userId);
      return rawCards
          .where((c) => c['collection'] == collection)
          .map((c) {
        final fid = c['firestoreId'] as String;
        final albumFid = c['albumFirestoreId'] as String?;
        final albumLocalId = (albumFid != null && albumFid.isNotEmpty)
            ? _webGetAlbumLocalId(albumFid)
            : (c['albumId'] as int? ?? -1);
        // For YuGiOh, Firebase Storage URLs fail CORS on web — use ygoprodeck CDN
        String? imageUrl = c['imageUrl'] as String?;
        if (collection == 'yugioh' &&
            (imageUrl == null ||
             imageUrl.isEmpty ||
             imageUrl.contains('cloudinary.com'))) {
          final cid = c['catalogId']?.toString();
          if (cid != null && cid.isNotEmpty) {
            imageUrl = 'https://images.ygoprodeck.com/images/cards/$cid.jpg';
          }
        }
        return CardModel(
          id: _webGetCardLocalId(fid),
          firestoreId: fid,
          catalogId: c['catalogId']?.toString(),
          name: c['name'] ?? '',
          serialNumber: c['serialNumber'] ?? '',
          collection: c['collection'] ?? '',
          albumId: albumLocalId,
          type: c['type'] ?? '',
          rarity: c['rarity'] ?? '',
          description: c['description'] ?? '',
          quantity: c['quantity'] as int? ?? 1,
          value: (c['value'] as num?)?.toDouble() ?? 0.0,
          imageUrl: imageUrl,
        );
      }).toList();
    }
    // Legge la lingua preferita dalla chiave corretta di LanguageService (per collezione).
    // LanguageService usa UPPERCASE (EN, IT, SP); il DB usa lowercase (en, it, es).
    // 'SP' → 'es': le colonne Pokémon usano _es, non _sp; il CT usa 'es' per lo spagnolo.
    // validLangs include le lingue YGO/Pokémon + lingue One Piece (jp/ko/zh).
    // 'sp' (LanguageConstants) → 'es' (CT/DB); 'jp' (LanguageService) → rimane 'jp'
    // perché onepiece_prints usa 'market_price' (base) per il giapponese.
    const validLangs = {'en', 'it', 'fr', 'de', 'es', 'pt', 'jp', 'ko', 'zh'};
    final rawLang = await LanguageService.getPreferredLanguageForCollection(collection);
    final lower = rawLang.toLowerCase();
    final mapped = lower == 'sp' ? 'es' : lower;
    final lang = validLangs.contains(mapped) ? mapped : 'en';
    return await _dbHelper.getCardsByCollection(collection, language: lang);
  }

  Future<Map<String, double>> getCollectionCompletions() async {
    if (kIsWeb) return {};
    return await _dbHelper.getCollectionCompletions();
  }

  Future<List<CardModel>> getCardsWithCatalog(String collection) async {
    if (kIsWeb) {
      // On web there is no local catalog to join against; return user cards directly.
      return getCardsByCollection(collection);
    }
    return await _dbHelper.getCardsWithCatalog(collection);
  }

  Future<List<CardModel>> findOwnedInstances(String collection, String name, String serialNumber, String rarity) async {
    if (kIsWeb) {
      final all = await getCardsByCollection(collection);
      return all.where((c) =>
        c.serialNumber.toLowerCase() == serialNumber.toLowerCase() &&
        c.rarity.toLowerCase() == rarity.toLowerCase()
      ).toList();
    }
    return await _dbHelper.findOwnedInstances(collection, name, serialNumber, rarity);
  }

  Future<int> getCardCountByAlbum(int albumId) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return 0;
      final albumFid = _webAlbumFirestoreIdById[albumId];
      if (albumFid == null) return 0;
      final rawCards = await _firestoreService.getCards(userId);
      return rawCards.where((c) => c['albumFirestoreId'] == albumFid).length;
    }
    return await _dbHelper.getCardCountByAlbum(albumId);
  }

  Future<CardModel?> findCardInAlbum(int albumId, String? catalogId, String serialNumber, String rarity) async {
    if (kIsWeb) return null;
    return await _dbHelper.findCardInAlbum(albumId, catalogId, serialNumber, rarity);
  }

  /// Returns the total number of cards in the local catalog DB for [collectionKey].
  /// Used to detect if the catalog has never been downloaded (count == 0).
  Future<int> getCatalogCardCount(String collectionKey) async {
    if (kIsWeb) return 1; // on web there's no local DB — treat as "present"
    return await _dbHelper.getCatalogCardCount(collectionKey);
  }

  // ============================================================
  // Card Business Logic
  // ============================================================

  /// Returns the ID of the "Doppioni" album for a collection, creating it if needed.
  Future<int> getOrCreateDoppioniAlbum(String collectionKey) async {
    final albums = await getAlbumsByCollection(collectionKey);
    final existing = albums.where((a) => a.name == 'Doppioni').toList();
    if (existing.isNotEmpty) return existing.first.id!;
    return await insertAlbum(AlbumModel(
      name: 'Doppioni',
      collection: collectionKey,
      maxCapacity: 1000,
    ));
  }

  /// Deletes a card. If [allRelated] is true, deletes all cards in the collection
  /// with the same serialNumber + rarity + catalogId (cross-album).
  /// Returns the list of deleted cards (for undo).
  Future<List<CardModel>> deleteCardWithRelated(
    CardModel card,
    String collectionKey, {
    bool allRelated = false,
  }) async {
    if (allRelated) {
      final allCards = await getCardsByCollection(collectionKey);
      final toDelete = allCards.where((c) =>
        c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
        c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
        (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId)
      ).toList();
      for (final c in toDelete) {
        await deleteCard(c.id!);
      }
      return toDelete;
    } else {
      await deleteCard(card.id!);
      return [card];
    }
  }

  /// Adjusts a card's quantity by [delta] with doppioni routing:
  /// - [+] on non-doppioni card with qty >= 1 → increment/create in Doppioni
  /// - [-] on non-doppioni card → drain Doppioni first (general view), floor at 1 (album view)
  Future<void> adjustCardQuantity(
    CardModel card,
    int delta, {
    required String collectionKey,
    bool isAlbumView = false,
  }) async {
    if (delta > 0) {
      XpService().awardXp(XpService.xpForRarity(card.rarity)).catchError((_) {});
    }

    final albums = await getAlbumsByCollection(collectionKey);
    final album = albums.firstWhere(
      (a) => a.id == card.albumId,
      orElse: () => AlbumModel(name: '', collection: collectionKey, maxCapacity: 0),
    );
    final isDoppioni = album.name == 'Doppioni';

    if (delta < 0 && !isDoppioni) {
      if (!isAlbumView) {
        final allCards = await getCardsByCollection(collectionKey);
        final doppioniIds = albums.where((a) => a.name == 'Doppioni').map((a) => a.id!).toSet();
        final doppioniMatch = allCards.where((c) =>
          doppioniIds.contains(c.albumId) &&
          c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
          c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
          (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId)
        ).toList();
        if (doppioniMatch.isNotEmpty) {
          final d = doppioniMatch.first;
          if (d.quantity - 1 <= 0) {
            await deleteCard(d.id!);
          } else {
            await updateCard(d.copyWith(quantity: d.quantity - 1));
          }
        }
        return; // floor main at 1, do nothing if no doppioni
      } else {
        if (card.quantity + delta < 1) return;
      }
    }

    if (delta > 0 && !isDoppioni && card.quantity >= 1) {
      final doppioniAlbumId = await getOrCreateDoppioniAlbum(collectionKey);
      final allCards = await getCardsByCollection(collectionKey);
      final existingInDoppioni = allCards.where((c) =>
        c.albumId == doppioniAlbumId &&
        c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
        c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
        (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId)
      ).toList();
      if (existingInDoppioni.isNotEmpty) {
        await updateCard(existingInDoppioni.first.copyWith(
          quantity: existingInDoppioni.first.quantity + delta,
        ));
      } else {
        await insertCard(card.copyWith(
          resetId: true,
          albumId: doppioniAlbumId,
          quantity: delta,
        ));
      }
      return;
    }

    final newQty = card.quantity + delta;
    if (newQty <= 0) {
      await deleteCard(card.id!);
    } else {
      await updateCard(card.copyWith(quantity: newQty));
    }
  }

  /// Adds a list of catalog cards to [album], routing duplicates to Doppioni.
  /// Returns {'added': int, 'updated': int, 'doppioni': int}.
  Future<Map<String, int>> addCatalogCardsToAlbum(
    List<Map<String, dynamic>> catalogCards,
    AlbumModel album,
    String collectionKey, {
    void Function(int done, int total)? onProgress,
  }) async {
    int added = 0, updated = 0, doppioni = 0;

    // Pre-load all existing cards for this collection in one query
    // instead of N×(findOwnedInstances + findCardInAlbum) queries.
    final existingCards = await getCardsByCollection(collectionKey);

    // "serialNumber|rarity" → any owned instance (for doppioni check)
    final Map<String, List<CardModel>> ownedByKey = {};
    // "catalogId|serialNumber|rarity" → card in target album (for update check)
    final Map<String, CardModel> inTargetAlbum = {};

    for (final c in existingCards) {
      final anyKey = '${c.serialNumber}|${c.rarity}';
      ownedByKey.putIfAbsent(anyKey, () => []).add(c);
      if (c.albumId == album.id) {
        inTargetAlbum['${c.catalogId}|${c.serialNumber}|${c.rarity}'] = c;
      }
    }

    // Pre-resolve doppioni album once if any card will need it
    int? doppioniAlbumId;
    final Map<String, CardModel> inDoppioniAlbum = {};
    final needsDoppioni = catalogCards.any((card) {
      final sn = card['localizedSetCode'] ?? card['setCode'] ?? '';
      final r = card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'] ?? '';
      return ownedByKey.containsKey('$sn|$r');
    });
    if (needsDoppioni) {
      doppioniAlbumId = await getOrCreateDoppioniAlbum(collectionKey);
      for (final c in existingCards) {
        if (c.albumId == doppioniAlbumId) {
          inDoppioniAlbum['${c.serialNumber}|${c.rarity}'] = c;
        }
      }
    }

    for (int i = 0; i < catalogCards.length; i++) {
      final card = catalogCards[i];
      try {
        final catalogId = (collectionKey == 'pokemon')
            ? (card['apiId'] ?? card['api_id'] ?? card['id']?.toString())?.toString()
            : card['id']?.toString();
        final name = card['localizedName'] ?? card['name'] ?? 'Unknown';
        final serialNumber = card['localizedSetCode'] ?? card['setCode'] ?? '';
        final rarity = card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'] ?? '';
        final anyKey = '$serialNumber|$rarity';

        if (ownedByKey.containsKey(anyKey)) {
          // Already owned somewhere → doppioni
          doppioniAlbumId ??= await getOrCreateDoppioniAlbum(collectionKey);
          final existingInDoppioni = inDoppioniAlbum[anyKey];
          if (existingInDoppioni != null) {
            final upd = existingInDoppioni.copyWith(quantity: existingInDoppioni.quantity + 1);
            await updateCard(upd);
            inDoppioniAlbum[anyKey] = upd;
          } else {
            final newCard = CardModel(
              catalogId: catalogId,
              name: name,
              serialNumber: serialNumber,
              collection: collectionKey,
              albumId: doppioniAlbumId,
              type: card['type'] ?? card['card_type'] ?? '',
              rarity: rarity,
              description: card['localizedDescription'] ?? card['description'] ?? '',
              imageUrl: card['artwork'] ?? card['imageUrl'],
              value: 0.0,
            );
            final newId = await insertCard(newCard);
            inDoppioniAlbum[anyKey] = newCard.copyWith(id: newId);
          }
          doppioni++;
          XpService().awardXp(XpService.xpForRarity(rarity)).catchError((_) {});
        } else {
          final albumKey = '$catalogId|$serialNumber|$rarity';
          final existingInAlbum = inTargetAlbum[albumKey];
          if (existingInAlbum != null) {
            final upd = existingInAlbum.copyWith(quantity: existingInAlbum.quantity + 1);
            await updateCard(upd);
            inTargetAlbum[albumKey] = upd;
            updated++;
          } else {
            final newCard = CardModel(
              catalogId: catalogId,
              name: name,
              serialNumber: serialNumber,
              collection: collectionKey,
              albumId: album.id!,
              type: card['type'] ?? card['card_type'] ?? '',
              rarity: rarity,
              description: card['localizedDescription'] ?? card['description'] ?? '',
              imageUrl: card['artwork'] ?? card['imageUrl'],
              value: 0.0,
            );
            final newId = await insertCard(newCard);
            final inserted = newCard.copyWith(id: newId);
            inTargetAlbum[albumKey] = inserted;
            ownedByKey[anyKey] = [inserted];
            added++;
          }
          XpService().awardXp(XpService.xpForRarity(rarity)).catchError((_) {});
        }
      } catch (e) { // ignore: empty_catches

      }
      onProgress?.call(i + 1, catalogCards.length);
    }
    return {'added': added, 'updated': updated, 'doppioni': doppioni};
  }

  /// Generic catalog update check, routes by [collectionKey].
  Future<Map<String, dynamic>> checkCollectionCatalogUpdates(String collectionKey) async {
    switch (collectionKey) {
      case 'onepiece': return checkOnepieceCatalogUpdates();
      case 'pokemon': return checkPokemonCatalogUpdates();
      default: return checkCatalogUpdates(); // yugioh
    }
  }

  /// Checks all unlocked supported collections for catalog updates (in parallel).
  /// Returns a list of update-info maps, each with 'collectionKey' and 'collectionName' added.
  Future<List<Map<String, dynamic>>> checkAllUnlockedCatalogUpdates() async {
    const supported = {'yugioh', 'pokemon', 'onepiece'};
    final collections = await getCollections();
    final unlocked = collections.where((c) => c.isUnlocked && supported.contains(c.key)).toList();
    final futures = unlocked.map((col) => checkCollectionCatalogUpdates(col.key)
        .then<Map<String, dynamic>?>((info) => info['needsUpdate'] == true
            ? {...info, 'collectionKey': col.key, 'collectionName': col.name}
            : null)
        .catchError((_) => null as Map<String, dynamic>?));
    return (await Future.wait(futures)).whereType<Map<String, dynamic>>().toList();
  }

  /// Lock globale: impedisce download paralleli sullo stesso catalogo.
  static bool _isDownloadingCatalog = false;

  /// Generic catalog download, routes by [collectionKey].
  Future<void> downloadCollectionCatalog(
    String collectionKey, {
    Map<String, dynamic>? updateInfo,
    void Function(int, int)? onProgress,
    void Function(double)? onSaveProgress,
  }) async {
    if (_isDownloadingCatalog) {

      return;
    }
    _isDownloadingCatalog = true;
    try {
      switch (collectionKey) {
        case 'onepiece':
          await downloadOnepieceCatalog(
            updateInfo: updateInfo,
            onProgress: onProgress,
            onSaveProgress: onSaveProgress,
          );
          break;
        case 'pokemon':
          await downloadPokemonCatalog(
            updateInfo: updateInfo,
            onProgress: onProgress,
            onSaveProgress: onSaveProgress,
          );
          break;
        default:
          await downloadYugiohCatalog(
            updateInfo: updateInfo,
            onProgress: onProgress,
            onSaveProgress: onSaveProgress,
          );
      }
    } finally {
      _isDownloadingCatalog = false;
    }
  }

  // ============================================================
  // Catalog Methods (read-only from SQLite, or Firestore on web)
  // ============================================================

  /// In-memory cache for web catalog, keyed by language code.
  static final Map<String, List<Map<String, dynamic>>> _webCatalogCache = {};

  /// Web-only in-memory mappings between Firestore doc IDs and fake local int IDs.
  /// These are session-scoped (reset on page refresh) and allow web paths to
  /// use the same int-keyed APIs as SQLite paths without touching the database.
  static final Map<String, int> _webAlbumIdByFirestoreId = {};
  static final Map<int, String> _webAlbumFirestoreIdById = {};
  static int _webAlbumIdCounter = 1;
  static final Map<String, int> _webCardIdByFirestoreId = {};
  static final Map<int, String> _webCardFirestoreIdById = {};
  static int _webCardIdCounter = 1;

  static int _webGetAlbumLocalId(String firestoreId) =>
      _webAlbumIdByFirestoreId.putIfAbsent(firestoreId, () {
        final id = _webAlbumIdCounter++;
        _webAlbumFirestoreIdById[id] = firestoreId;
        return id;
      });

  static int _webGetCardLocalId(String firestoreId) =>
      _webCardIdByFirestoreId.putIfAbsent(firestoreId, () {
        final id = _webCardIdCounter++;
        _webCardFirestoreIdById[id] = firestoreId;
        return id;
      });

  Future<List<Map<String, dynamic>>> getCatalogCards(String collection, {String? query}) async {
    if (kIsWeb) return [];
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

    // When browsing (no query) with a non-EN language, hide EN-only prints.
    // When searching, EN-only prints are included so the user can still find them.
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      rows = rows.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();
        final localizedName = (r['localizedName'] ?? '').toString().toLowerCase();
        final setCode = (r['localizedSetCode'] ?? r['setCode'] ?? '').toString().toLowerCase();
        return name.contains(q) || localizedName.contains(q) || setCode.contains(q);
      }).toList();
    } else if (lang != 'en') {
      rows = rows.where((r) => r['isLocalizedPrint'] == 1).toList();
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
      // Always use ygoprodeck CDN — Firebase Storage URLs fail CORS on web
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
    if (kIsWeb) return [];
    return await _dbHelper.getYugiohCardPrints(cardId, language: language);
  }

  Future<List<Map<String, dynamic>>> getOnepieceCardPrints(int cardId) async {
    if (kIsWeb) return [];
    return await _dbHelper.getOnepieceCardPrints(cardId);
  }

  Future<List<Map<String, dynamic>>> getPokemonCardPrints(int cardId, {required String language}) async {
    if (kIsWeb) return [];
    return await _dbHelper.getPokemonCardPrints(cardId, language: language);
  }

  Future<List<Map<String, dynamic>>> getCardSets(String cardId) async {
    if (kIsWeb) return [];
    return await _dbHelper.getCardSets(cardId);
  }

  Future<List<Map<String, dynamic>>> getSetStats(String collection, {String lang = 'en'}) async {
    if (kIsWeb) return [];
    return _dbHelper.getSetStats(collection, lang: lang);
  }

  Future<List<Map<String, dynamic>>> getSetDetail(String collection, String setIdentifier, {String lang = 'en'}) async {
    if (kIsWeb) return [];
    return _dbHelper.getSetDetail(collection, setIdentifier, lang: lang);
  }

  Future<Map<String, dynamic>?> checkSetCompletion(String collection, String serialNumber) async {
    if (kIsWeb) return null;
    return _dbHelper.checkSetCompletion(collection, serialNumber);
  }

  Future<void> moveSetCardsToAlbum(String collection, String setIdentifier, int albumId) async {
    if (kIsWeb) return;
    return _dbHelper.moveSetCardsToAlbum(collection, setIdentifier, albumId);
  }

  Future<int> getCatalogCount(String collection) async {
    if (kIsWeb) return 0;
    return await _dbHelper.getCatalogCount(collection);
  }

  Future<int> getYugiohCatalogCount() async {
    if (kIsWeb) return 0;
    return await _dbHelper.getYugiohCatalogCount();
  }

  Future<Set<String>> getAvailableCatalogLanguages(String collectionKey) async {
    if (kIsWeb) return {'EN'};
    return await _dbHelper.getAvailableCatalogLanguages(collectionKey);
  }

  // ============================================================
  // Stats (read from SQLite)
  // ============================================================

  Future<List<Map<String, dynamic>>> getStatsPerCollection() async {
    if (kIsWeb) return [];
    return await _dbHelper.getStatsPerCollection();
  }

  Future<List<Map<String, dynamic>>> getStatsPerRarity() async {
    if (kIsWeb) return [];
    return await _dbHelper.getStatsPerRarity();
  }

  Future<List<Map<String, dynamic>>> getAllCardsForExport() async {
    if (kIsWeb) return [];
    return await _dbHelper.getAllCardsForExport();
  }

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

  // Web-only deck ID mappings (session-scoped)
  static final Map<String, int> _webDeckIdByFirestoreId = {};
  static final Map<int, String> _webDeckFirestoreIdById = {};
  static int _webDeckIdCounter = 1;

  static int _webGetDeckLocalId(String firestoreId) =>
      _webDeckIdByFirestoreId.putIfAbsent(firestoreId, () {
        final id = _webDeckIdCounter++;
        _webDeckFirestoreIdById[id] = firestoreId;
        return id;
      });

  Future<int> insertDeck(String name, String collection) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return -1;
      final firestoreId = await _firestoreService.insertDeck(userId, name, collection);
      return _webGetDeckLocalId(firestoreId);
    }
    final localId = await _dbHelper.insertDeck(name, collection);
    _syncService.notifyLocalChange('decks');
    // Push to Firestore
    try {
      if (await _syncService.canSync()) {
        try {
          final userId = _authService.currentUserId;
          if (userId != null) {
            final firestoreId = await _firestoreService.insertDeck(userId, name, collection);
            await _dbHelper.updateFirestoreId('decks', localId, firestoreId);
          }
        } catch (e) { // ignore: empty_catches

          await _dbHelper.addPendingSync('decks', localId, 'insert');
        }
      } else {
        await _dbHelper.addPendingSync('decks', localId, 'insert');
      }
    } catch (e) { // ignore: empty_catches

    }
    return localId;
  }

  Future<List<Map<String, dynamic>>> getDecksByCollection(String collection) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return [];
      final rawDecks = await _firestoreService.getDecks(userId);
      return rawDecks
          .where((d) => d['collection'] == collection)
          .map((d) {
        final fid = d['firestoreId'] as String;
        return {
          'id': _webGetDeckLocalId(fid),
          'firestoreId': fid,
          'name': d['name'] ?? '',
          'collection': d['collection'] ?? '',
        };
      }).toList();
    }
    return await _dbHelper.getDecksByCollection(collection);
  }

  Future<int> deleteDeck(int id) async {
    if (kIsWeb) {
      final userId = _authService.currentUserId;
      if (userId == null) return 0;
      final firestoreId = _webDeckFirestoreIdById[id];
      if (firestoreId != null) {
        await _firestoreService.deleteDeck(userId, firestoreId);
        _webDeckFirestoreIdById.remove(id);
        _webDeckIdByFirestoreId.remove(firestoreId);
      }
      return 0;
    }
    final firestoreId = await _dbHelper.getFirestoreId('decks', id);
    final result = await _dbHelper.deleteDeck(id);
    _syncService.notifyLocalChange('decks');
    if (firestoreId != null) {
      await _syncService.pushDeckChange(id, 'delete');
    }
    return result;
  }

  Future<void> addCardToDeck(int deckId, int cardId, int quantity) async {
    if (kIsWeb) return; // Deck card editing not yet supported on web.
    await _dbHelper.addCardToDeck(deckId, cardId, quantity);
    // Sync deck card addition
    if (await _syncService.canSync()) {
      try {
        final userId = _authService.currentUserId;
        final firestoreId = await _dbHelper.getFirestoreId('decks', deckId);
        if (userId != null && firestoreId != null) {
          await _firestoreService.addCardToDeck(userId, firestoreId, cardId, quantity);
        }
      } catch (e) { // ignore: empty_catches

      }
    }
  }

  Future<List<Map<String, dynamic>>> getDeckCards(int deckId) async {
    if (kIsWeb) return [];
    return await _dbHelper.getDeckCards(deckId);
  }

  Future<List<Map<String, dynamic>>> getDecksForCard(int cardId) async {
    if (kIsWeb) return [];
    return await _dbHelper.getDecksForCard(cardId);
  }

  Future<Map<String, dynamic>?> getCardExtraInfo(
      String collection, String? catalogId) async {
    if (kIsWeb) return null;
    return _dbHelper.getCardExtraInfo(collection, catalogId);
  }

  Future<void> decrementCardInDeck(int deckId, int cardId) async {
    if (kIsWeb) return;
    await _dbHelper.decrementCardInDeck(deckId, cardId);
  }

  Future<void> removeCardFromDeck(int deckId, int cardId) async {
    if (kIsWeb) return; // Deck card editing not yet supported on web.
    await _dbHelper.removeCardFromDeck(deckId, cardId);
    // Sync deck card removal
    if (await _syncService.canSync()) {
      try {
        final userId = _authService.currentUserId;
        final firestoreId = await _dbHelper.getFirestoreId('decks', deckId);
        if (userId != null && firestoreId != null) {
          await _firestoreService.removeCardFromDeck(userId, firestoreId, cardId);
        }
      } catch (e) { // ignore: empty_catches

      }
    }
  }

  // ============================================================
  // Sync Operations
  // ============================================================

  Future<void> syncOnLogin() async {
    if (kIsWeb) return; // On web, data is always read directly from Firestore.
    await _syncService.syncOnLogin();
  }

  Future<void> fullSync() async {
    if (kIsWeb) return; // On web, data is always read directly from Firestore.
    // Push any local pending changes first, then restore the full cloud state.
    // Timeout totale 30s — se offline fallisce silenziosamente senza bloccare.
    await _syncService.flushPendingQueue()
        .timeout(const Duration(seconds: 15))
        .catchError((_) {});
    await _syncService.pullFromCloud()
        .timeout(const Duration(seconds: 15))
        .catchError((_) {});
  }

  /// Deduplicate local data, wipe Firestore, re-upload clean state.
  /// Use when the user sees doubled cards/albums/decks.
  Future<void> resetAndResync({void Function(String)? onStatus}) async {
    if (kIsWeb) return; // Not applicable on web.
    await _syncService.resetAndResync(onStatus: onStatus);
  }

  /// Backfill XP from all existing cards (one-time, idempotent via SharedPreferences flag).
  /// Necessary for users who had cards before the XP system was introduced.
  Future<void> backfillXpFromExistingCards() async {
    if (kIsWeb) return; // XP backfill uses SQLite; not applicable on web.
    const backfillKey = 'xp_backfill_done_v1';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(backfillKey) == true) return;

    final allCards = await _dbHelper.getAllCards();
    int totalXp = 0;
    for (final card in allCards) {
      totalXp += XpService.xpForRarity(card.rarity) * card.quantity;
    }

    await XpService().setXpIfHigher(totalXp);
    await prefs.setBool(backfillKey, true);
  }

  Future<void> insertYugiohCards(List<Map<String, dynamic>> cards, {Function(double)? onProgress}) async {
    await _dbHelper.insertYugiohCards(cards, onProgress: onProgress);
  }

  // ============================================================
  // One Piece Catalog (from Firestore)
  // ============================================================

  Future<Map<String, dynamic>> checkOnepieceCatalogUpdates() async {
    if (kIsWeb) return {'needsUpdate': false, 'totalCards': 0};
    try {
      final remoteMetadata = await _firestoreService.getCatalogMetadata('onepiece');
      if (remoteMetadata == null) {
        return {'needsUpdate': false, 'error': 'Remote metadata not found'};
      }

      final remoteVersion = remoteMetadata['version'] as int? ?? 0;
      final remoteTotalCards = remoteMetadata['totalCards'] as int? ?? 0;
      final localMetadata = await _dbHelper.getCatalogMetadata('onepiece');

      if (localMetadata == null) {
        return {
          'needsUpdate': true,
          'isFirstDownload': true,
          'remoteVersion': remoteVersion,
          'totalCards': remoteTotalCards,
        };
      }

      final localVersion = localMetadata['version'] as int? ?? 0;
      final localTotalCards = localMetadata['total_cards'] as int? ?? 0;

      if (remoteVersion > localVersion) {
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
    } catch (e) { // ignore: empty_catches
      return {'needsUpdate': false, 'error': e.toString()};
    }
  }

  Future<void> downloadOnepieceCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
    Map<String, dynamic>? updateInfo,
  }) async {
    if (kIsWeb) return;

    if (updateInfo?['canDoIncremental'] == true) {
      final modifiedChunks = (updateInfo!['modifiedChunks'] as List<dynamic>).cast<String>();
      final deletedCards = updateInfo['deletedCards'] as List<dynamic>? ?? [];
      await _applyOnepieceIncrementalUpdate(
        modifiedChunks: modifiedChunks,
        deletedCardIds: deletedCards,
        onProgress: onProgress,
        onSaveProgress: onSaveProgress,
      );
      return;
    }

    final remoteMetadata = await _firestoreService.getCatalogMetadata('onepiece');
    int totalDownloaded = 0;

    await _firestoreService.streamCatalog(
      CatalogConstants.onepiece,
      onBatch: (cards, chunksDone, chunksTotal) async {
        onProgress?.call(chunksDone, chunksTotal);
        await Future.delayed(Duration.zero); // yield UI frame before heavy work
        await _dbHelper.insertOnepieceCards(cards);
        totalDownloaded += cards.length;
        onSaveProgress?.call(chunksDone / chunksTotal);
      },
    );

    if (totalDownloaded == 0) return;

    if (remoteMetadata != null) {
      await _dbHelper.saveCatalogMetadata(
        catalogName: 'onepiece',
        version: remoteMetadata['version'] as int? ?? 1,
        totalCards: remoteMetadata['totalCards'] as int? ?? totalDownloaded,
        totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
        lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
      );
    }

    try { await CardtraderService().applyLocalPricesToCollection('onepiece'); } catch (_) {}
  }

  Future<void> _applyOnepieceIncrementalUpdate({
    required List<String> modifiedChunks,
    required List<dynamic> deletedCardIds,
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    final remoteMetadata = await _firestoreService.getCatalogMetadata('onepiece');
    final modifiedCards = await _firestoreService.fetchCatalogChunks(
      CatalogConstants.onepiece,
      modifiedChunks,
      onProgress: onProgress,
    );

    final deletedIds = deletedCardIds.map((e) => e as int).toList();
    if (deletedIds.isNotEmpty) await _dbHelper.deleteOnepieceCardsByIds(deletedIds);
    if (modifiedCards.isNotEmpty) {
      await _dbHelper.insertOnepieceCards(modifiedCards, onProgress: onSaveProgress);
    }

    if (remoteMetadata != null) {
      await _dbHelper.saveCatalogMetadata(
        catalogName: 'onepiece',
        version: remoteMetadata['version'] as int? ?? 1,
        totalCards: remoteMetadata['totalCards'] as int? ?? 0,
        totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
        lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
      );
    }

    try { await CardtraderService().applyLocalPricesToCollection('onepiece'); } catch (_) {}
  }

  Future<void> redownloadOnepieceCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    if (kIsWeb) return;
    await _dbHelper.clearOnepieceCatalog();
    await downloadOnepieceCatalog(onProgress: onProgress, onSaveProgress: onSaveProgress);
    await _dbHelper.rebuildExpansionsAndRarities('onepiece');
  }

  Future<List<Map<String, dynamic>>> getOnepieceCatalogCards({
    String? query,
    String language = 'EN',
    int limit = 60,
    int offset = 0,
  }) async {
    if (kIsWeb) {
      return _getOnepieceCatalogCardsWeb(query: query, limit: limit, offset: offset);
    }
    return await _dbHelper.getOnepieceCatalogCards(
        query: query, language: language, limit: limit, offset: offset);
  }

  Future<List<Map<String, dynamic>>> _getOnepieceCatalogCardsWeb({
    String? query,
    int limit = 60,
    int offset = 0,
  }) async {
    const cacheKey = 'onepiece';
    if (!_webCatalogCache.containsKey(cacheKey)) {
      final firestoreCards = await _firestoreService.fetchCatalog(CatalogConstants.onepiece);
      _webCatalogCache[cacheKey] = _buildOnepieceWebRows(firestoreCards);
    }

    var rows = _webCatalogCache[cacheKey]!;

    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      rows = rows.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();
        final setCode = (r['setCode'] ?? '').toString().toLowerCase();
        final setName = (r['setName'] ?? '').toString().toLowerCase();
        return name.contains(q) || setCode.contains(q) || setName.contains(q);
      }).toList();
    }

    if (offset >= rows.length) return [];
    return rows.sublist(offset, (offset + limit).clamp(0, rows.length));
  }

  static List<Map<String, dynamic>> _buildOnepieceWebRows(
    List<Map<String, dynamic>> cards,
  ) {
    final rows = <Map<String, dynamic>>[];
    int idCounter = 1;
    for (final card in cards) {
      final prints = card['prints'];
      final List<dynamic> printList = prints is List ? prints : [];
      final cardArtwork = card['imageUrl'] as String? ?? card['image_url'] as String?;

      if (printList.isEmpty) {
        rows.add({
          'id': idCounter++,
          'name': card['name'] ?? '',
          'card_type': card['card_type'] ?? '',
          'color': card['color'] ?? '',
          'cost': card['cost'],
          'power': card['power'],
          'setCode': '',
          'localizedSetCode': '',
          'setId': '',
          'setName': '',
          'localizedSetName': '',
          'rarity': '',
          'setRarity': '',
          'localizedRarity': '',
          'artwork': cardArtwork,
          'collection': 'onepiece',
          'isOwned': 0,
        });
        continue;
      }

      for (final p in printList.cast<Map<String, dynamic>>()) {
        final artwork = p['artwork'] as String? ?? cardArtwork;
        rows.add({
          'id': card['id'] ?? idCounter,
          'name': card['name'] ?? '',
          'card_type': card['card_type'] ?? '',
          'color': card['color'] ?? '',
          'cost': card['cost'],
          'power': card['power'],
          'setCode': p['card_set_id'] ?? '',
          'localizedSetCode': p['card_set_id'] ?? '',
          'setId': p['set_id'] ?? '',
          'setName': p['set_name'] ?? '',
          'localizedSetName': p['set_name'] ?? '',
          'rarity': p['rarity'] ?? card['rarity'] ?? '',
          'setRarity': p['rarity'] ?? '',
          'localizedRarity': p['rarity'] ?? '',
          'artwork': artwork,
          'collection': 'onepiece',
          'isOwned': 0,
        });
        idCounter++;
      }
    }
    return rows;
  }

  // ============================================================
  // Pokémon Catalog (from Firestore)
  // ============================================================

  Future<Map<String, dynamic>> checkPokemonCatalogUpdates() async {
    if (kIsWeb) return {'needsUpdate': false, 'totalCards': 0};
    try {
      final remoteMetadata = await _firestoreService.getCatalogMetadata('pokemon');
      if (remoteMetadata == null) {
        return {'needsUpdate': false, 'error': 'Remote metadata not found'};
      }
      final remoteVersion = remoteMetadata['version'] as int? ?? 0;
      final remoteTotalCards = remoteMetadata['totalCards'] as int? ?? 0;
      final localMetadata = await _dbHelper.getCatalogMetadata('pokemon');
      if (localMetadata == null) {
        return {
          'needsUpdate': true,
          'isFirstDownload': true,
          'remoteVersion': remoteVersion,
          'totalCards': remoteTotalCards,
        };
      }
      final localVersion = localMetadata['version'] as int? ?? 0;
      final localTotalCards = localMetadata['total_cards'] as int? ?? 0;
      if (remoteVersion > localVersion) {
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
    } catch (e) { // ignore: empty_catches
      return {'needsUpdate': false, 'error': e.toString()};
    }
  }

  Future<void> downloadPokemonCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
    Map<String, dynamic>? updateInfo,
  }) async {
    if (kIsWeb) return;
    if (updateInfo?['canDoIncremental'] == true) {
      final modifiedChunks = (updateInfo!['modifiedChunks'] as List<dynamic>).cast<String>();
      final deletedCards = updateInfo['deletedCards'] as List<dynamic>? ?? [];
      final remoteMetadata = await _firestoreService.getCatalogMetadata('pokemon');
      final modifiedCards = await _firestoreService.fetchCatalogChunks(
        CatalogConstants.pokemon, modifiedChunks, onProgress: onProgress,
      );
      final deletedIds = deletedCards.whereType<num>().map((e) => e.toInt()).toList();
      if (deletedIds.isNotEmpty) await _dbHelper.deletePokemonCardsByIds(deletedIds);
      if (modifiedCards.isNotEmpty) {
        final normalizedCards = modifiedCards.map(_normalizePokemonCardForSQLite).toList();
        await _dbHelper.insertPokemonCards(normalizedCards, onProgress: onSaveProgress);
      }
      if (remoteMetadata != null) {
        await _dbHelper.saveCatalogMetadata(
          catalogName: 'pokemon',
          version: remoteMetadata['version'] as int? ?? 1,
          totalCards: remoteMetadata['totalCards'] as int? ?? 0,
          totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
          lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
        );
      }
      try { await CardtraderService().applyLocalPricesToCollection('pokemon'); } catch (_) {}
      return;
    }

    final remoteMetadata = await _firestoreService.getCatalogMetadata('pokemon');
    int totalDownloaded = 0;

    await _firestoreService.streamCatalog(
      CatalogConstants.pokemon,
      onBatch: (cards, chunksDone, chunksTotal) async {
        onProgress?.call(chunksDone, chunksTotal);
        await Future.delayed(Duration.zero); // yield UI frame before heavy work
        final normalized = await compute(_normalizePokemonBatch, cards);
        await _dbHelper.insertPokemonCards(normalized);
        totalDownloaded += cards.length;
        onSaveProgress?.call(chunksDone / chunksTotal);
      },
    );

    if (totalDownloaded == 0) return;

    if (remoteMetadata != null) {
      await _dbHelper.saveCatalogMetadata(
        catalogName: 'pokemon',
        version: remoteMetadata['version'] as int? ?? 1,
        totalCards: remoteMetadata['totalCards'] as int? ?? totalDownloaded,
        totalChunks: remoteMetadata['totalChunks'] as int? ?? 0,
        lastUpdated: (remoteMetadata['lastUpdated'] as dynamic)?.toString() ?? DateTime.now().toIso8601String(),
      );
    }

    try { await CardtraderService().applyLocalPricesToCollection('pokemon'); } catch (_) {}
  }

  Future<void> redownloadPokemonCatalog({
    void Function(int current, int total)? onProgress,
    void Function(double progress)? onSaveProgress,
  }) async {
    if (kIsWeb) return;
    await _dbHelper.clearPokemonCatalog();
    await downloadPokemonCatalog(onProgress: onProgress, onSaveProgress: onSaveProgress);
    await _dbHelper.rebuildExpansionsAndRarities('pokemon');
  }

  Future<List<Map<String, dynamic>>> getPokemonCatalogCards({
    String? query,
    required String language,
    int limit = 60,
    int offset = 0,
  }) async {
    if (kIsWeb) {
      return _getPokemonCatalogCardsWeb(query: query, limit: limit, offset: offset);
    }
    return await _dbHelper.getPokemonCatalogCards(
      query: query,
      language: language,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> _getPokemonCatalogCardsWeb({
    String? query,
    int limit = 60,
    int offset = 0,
  }) async {
    const cacheKey = 'pokemon';
    if (!_webCatalogCache.containsKey(cacheKey)) {
      final firestoreCards = await _firestoreService.fetchCatalog(CatalogConstants.pokemon);
      _webCatalogCache[cacheKey] = _buildPokemonWebRows(firestoreCards);
    }

    var rows = _webCatalogCache[cacheKey]!;

    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      rows = rows.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();
        final setCode = (r['setCode'] ?? '').toString().toLowerCase();
        final setName = (r['setName'] ?? '').toString().toLowerCase();
        return name.contains(q) || setCode.contains(q) || setName.contains(q);
      }).toList();
    }

    if (offset >= rows.length) return [];
    return rows.sublist(offset, (offset + limit).clamp(0, rows.length));
  }

  static List<Map<String, dynamic>> _buildPokemonWebRows(
    List<Map<String, dynamic>> cards,
  ) {
    final rows = <Map<String, dynamic>>[];
    int idCounter = 1;
    for (final card in cards) {
      final prints = card['prints'];
      final List<dynamic> printList = prints is List ? prints : [];
      final cardArtwork = card['imageUrl'] as String? ?? card['image_url'] as String?;

      if (printList.isEmpty) {
        rows.add({
          'id': card['id'] ?? idCounter++,
          'apiId': card['api_id'] ?? '',
          'name': card['name'] ?? '',
          'type': card['supertype'] ?? '',
          'rarity': card['rarity'] ?? '',
          'setCode': '',
          'localizedSetCode': '',
          'setName': card['set_name'] ?? '',
          'localizedSetName': card['set_name'] ?? '',
          'setRarity': '',
          'localizedRarity': '',
          'artwork': cardArtwork,
          'collection': 'pokemon',
          'isOwned': 0,
        });
        continue;
      }

      for (final p in printList.cast<Map<String, dynamic>>()) {
        final artwork = p['artwork'] as String? ?? cardArtwork;
        final setCode = p['set_code'] ?? p['card_set_id'] ?? '';
        rows.add({
          'id': card['id'] ?? idCounter,
          'apiId': card['api_id'] ?? '',
          'name': card['name'] ?? '',
          'type': card['supertype'] ?? '',
          'rarity': card['rarity'] ?? '',
          'setCode': setCode,
          'localizedSetCode': setCode,
          'setName': p['set_name'] ?? card['set_name'] ?? '',
          'localizedSetName': p['set_name'] ?? card['set_name'] ?? '',
          'setRarity': p['rarity'] ?? card['rarity'] ?? '',
          'localizedRarity': p['rarity'] ?? card['rarity'] ?? '',
          'artwork': artwork,
          'collection': 'pokemon',
          'isOwned': 0,
        });
        idCounter++;
      }
    }
    return rows;
  }

  /// Metodo unificato: instrada alla query corretta in base alla collezione.
  /// Usare questo invece dei tre metodi separati nei widget.
  Future<List<Map<String, dynamic>>> getCatalogCardsByCollection(
    String collection, {
    String? query,
    String language = 'EN',
    int limit = 100,
    int offset = 0,
  }) async {
    if (collection == 'yugioh') {
      return getYugiohCatalogCards(
        query: query,
        language: language,
        limit: limit,
        offset: offset,
      );
    } else if (collection == 'onepiece') {
      return getOnepieceCatalogCards(
        query: query,
        language: language,
        limit: limit,
        offset: offset,
      );
    } else if (collection == 'pokemon') {
      return getPokemonCatalogCards(
        query: query,
        language: language,
        limit: limit,
        offset: offset,
      );
    } else {
      // Cataloghi generici: carica tutto (no paginazione)
      if (offset > 0) return [];
      return getCatalogCards(collection, query: query);
    }
  }
}
