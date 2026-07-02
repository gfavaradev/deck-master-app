import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'cardtrader_service.dart' show CardtraderService;
import 'package:http/http.dart' as http;
import 'package:deck_master/models/pending_catalog_change.dart';
import 'package:deck_master/services/database_helper.dart';
import 'dart:async';
import 'backblaze_service.dart';

/// Per-sync-run cache for [AdminCatalogService._resolveRealCardSerial], so the
/// TCGDex set list / OPTCG full card list are fetched once per run instead of
/// once per unresolved card.
class _SerialResolveCache {
  List<Map<String, dynamic>>? tcgdexSets;
  final Map<String, ({Map<String, dynamic> setInfo, List<Map<String, dynamic>> cards})>
      tcgdexSetData = {};
  List<dynamic>? optcgAllSetCards;
}

/// Bounded semaphore for limiting parallel async operations.
class _Semaphore {
  int _count;
  final _waiters = <Completer<void>>[];
  _Semaphore(this._count);

  Future<void> acquire() async {
    if (_count > 0) { _count--; return; }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _count++;
    }
  }
}

/// Service for managing admin catalog operations
class AdminCatalogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _pendingChangesKey = 'admin_pending_catalog_changes';
  static const int _chunkSize = 100;
  static const int _uploadConcurrency = 8;

  // ============================================================
  // Image Storage
  // ============================================================

  /// Returns true if [url] points to Backblaze B2 storage.
  /// Used to detect already-migrated images.
  static bool _isHostedImageUrl(String? url) =>
      url != null && url.contains('backblazeb2.com');

  // ============================================================
  // Real card serial resolution (CT → official game API fallback)
  // ============================================================

  /// True when [collectorNumber] is actually a CT-internal blueprint ID
  /// (≥5 raw digits) rather than a real card collector number (e.g. "001",
  /// "127540" vs "swsh1-1"). Callers must never persist a surrogate value as
  /// the card's official serial.
  static bool _isSurrogateCtId(String collectorNumber) =>
      RegExp(r'^\d{5,}$').hasMatch(collectorNumber);

  /// Cascading collector-number lookup: top-level field, then
  /// `fixed_properties`. Returns the raw CT blueprint ID as last resort —
  /// callers MUST check [_isSurrogateCtId] before trusting the result.
  static String _extractCtCollectorNumber(
    Map<String, dynamic> bp, {
    List<String> propKeys = const ['collector_number', 'number'],
  }) {
    final top = bp['collector_number'] ?? bp['number'];
    if (top != null && top.toString().trim().isNotEmpty) return top.toString().trim();
    final props = (bp['fixed_properties'] as Map<String, dynamic>?) ?? {};
    for (final key in propKeys) {
      final nested = props[key];
      if (nested != null && nested.toString().trim().isNotEmpty) {
        return nested.toString().trim();
      }
    }
    return bp['id']?.toString() ?? '';
  }

  static String _normalizeForMatch(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Resolves the REAL official serial + image for a card, never falling
  /// back to a CT-internal blueprint ID.
  ///
  /// 1. If [ctCollectorNumber] is a genuine collector number (not a
  ///    surrogate blueprint ID), trust it and build the serial from CT data.
  /// 2. Otherwise, look the card up in the official game API (TCGDex for
  ///    Pokémon, OPTCG for One Piece) by matching expansion + card name.
  /// 3. If neither source resolves a real serial, returns null — the caller
  ///    must log and discard the card rather than invent an id.
  Future<({String apiId, String? imageUrl, String source})?> _resolveRealCardSerial({
    required String catalog, // 'pokemon' | 'onepiece'
    required String nameEn,
    required String ctCollectorNumber,
    required String expCode,
    required String expName,
    String? ctImageUrl,
    required _SerialResolveCache cache,
  }) async {
    if (ctCollectorNumber.isNotEmpty && !_isSurrogateCtId(ctCollectorNumber)) {
      final apiId = catalog == 'pokemon'
          ? '${expCode.toLowerCase()}-$ctCollectorNumber'
          : (ctCollectorNumber.toUpperCase().startsWith(expCode.toUpperCase())
              ? ctCollectorNumber.toUpperCase()
              : '$expCode-${ctCollectorNumber.toUpperCase()}');
      return (apiId: apiId, imageUrl: ctImageUrl, source: 'ct');
    }

    if (catalog == 'pokemon') {
      return _resolvePokemonSerialFromTcgdex(nameEn: nameEn, expName: expName, cache: cache);
    }
    if (catalog == 'onepiece') {
      return _resolveOnepieceSerialFromOptcg(nameEn: nameEn, expCode: expCode, cache: cache);
    }
    return null;
  }

  Future<({String apiId, String? imageUrl, String source})?> _resolvePokemonSerialFromTcgdex({
    required String nameEn,
    required String expName,
    required _SerialResolveCache cache,
  }) async {
    cache.tcgdexSets ??= await _fetchTcgdexSets();
    final normExpName = _normalizeForMatch(expName);

    Map<String, dynamic>? matchedSet;
    for (final s in cache.tcgdexSets!) {
      if (_normalizeForMatch(s['name']?.toString() ?? '') == normExpName) {
        matchedSet = s;
        break;
      }
    }
    matchedSet ??= () {
      for (final s in cache.tcgdexSets!) {
        final n = _normalizeForMatch(s['name']?.toString() ?? '');
        if (n.isNotEmpty && (n.contains(normExpName) || normExpName.contains(n))) return s;
      }
      return null;
    }();
    final setId = matchedSet?['id']?.toString();
    if (setId == null || setId.isEmpty) return null;

    cache.tcgdexSetData[setId] ??= await _fetchTcgdexSetData(setId);
    final setData = cache.tcgdexSetData[setId]!;
    final normName = _normalizeForMatch(nameEn);

    Map<String, dynamic>? brief;
    for (final c in setData.cards) {
      if (_normalizeForMatch(c['name']?.toString() ?? '') == normName) {
        brief = c;
        break;
      }
    }
    final localId = brief?['localId']?.toString();
    if (localId == null || localId.isEmpty) return null;

    final detail = await _fetchTcgdexCardDetail(setId, localId, brief!);
    final transformed = _transformTcgdexCard(detail, setData.setInfo, '');
    final apiId = transformed['api_id'] as String?;
    if (apiId == null || apiId.isEmpty) return null;
    return (apiId: apiId, imageUrl: transformed['image_url'] as String?, source: 'tcgdex');
  }

  Future<({String apiId, String? imageUrl, String source})?> _resolveOnepieceSerialFromOptcg({
    required String nameEn,
    required String expCode,
    required _SerialResolveCache cache,
  }) async {
    cache.optcgAllSetCards ??= await _fetchOptcgEndpoint('allSetCards/');
    final normName = _normalizeForMatch(nameEn);

    for (final raw in cache.optcgAllSetCards!) {
      final m = raw as Map;
      final cardSetId = (m['card_set_id'] as String? ?? '').trim();
      if (cardSetId.isEmpty || !cardSetId.toUpperCase().startsWith(expCode.toUpperCase())) {
        continue;
      }
      final name = (m['card_name'] as String? ?? '').trim();
      if (_normalizeForMatch(name) != normName) continue;
      return (apiId: cardSetId, imageUrl: m['card_image']?.toString(), source: 'optcg');
    }
    return null;
  }

  /// Updates both camelCase and snake_case image URL fields on a One Piece card map.
  static void _setOnepieceCardImageUrl(Map<String, dynamic> card, String url) {
    card['imageUrl'] ??= url;
    if (card['image_url'] == null ||
        !_isHostedImageUrl(card['image_url'] as String?)) {
      card['image_url'] = url;
    }
  }

  /// Uploads a card image to Backblaze B2.
  /// [catalog] determines the folder prefix (e.g. 'yugioh', 'pokemon', 'onepiece').
  /// [cardId] can be an int (YuGiOh) or String (Pokémon api_id).
  /// Returns the Backblaze public URL, or null on failure.
  Future<String?> _uploadCardImageIfNeeded(
    String catalog,
    dynamic cardId,
    String? sourceUrl, {
    String? setCode,
  }) async {
    if (sourceUrl == null || sourceUrl.isEmpty) return null;
    final safeId = cardId.toString().replaceAll(RegExp(r'[/\s]'), '_');
    try {
      // Fast path: upload to Backblaze directly from remote URL — no local download needed.
      // Skipped for onepiece: OPTCG CDN blocks non-browser User-Agents and needs
      // a .webp → .png fallback that only works when we control the HTTP request.
      if (catalog != 'onepiece') {
        final url = await BackblazeService.uploadFromRemoteUrl(
          imageUrl: sourceUrl,
          catalog: catalog,
          cardId: cardId,
          setCode: setCode,
        );
        if (url != null) return url;
        debugPrint('[ImageUpload] Remote URL fallback per $sourceUrl (id=$safeId)');
      }

      // Byte-download path (onepiece CDN + fallback for unreachable URLs).
      final headers = {
        'User-Agent': 'Mozilla/5.0 (compatible; DeckMasterBot/1.0)',
        'Accept': 'image/webp,image/png,image/*,*/*;q=0.8',
      };
      String fetchUrl = sourceUrl;
      var response = await http.get(Uri.parse(fetchUrl), headers: headers);

      // OPTCG CDN may serve .webp → fallback .png
      if (response.statusCode == 404 && fetchUrl.endsWith('/high.webp')) {
        fetchUrl = fetchUrl.replaceFirst('/high.webp', '/high.png');
        response = await http.get(Uri.parse(fetchUrl), headers: headers);
      }

      if (response.statusCode != 200) {
        debugPrint('[ImageUpload] HTTP ${response.statusCode} per $fetchUrl (id=$safeId)');
        return null;
      }
      if (response.bodyBytes.isEmpty) {
        debugPrint('[ImageUpload] Body vuoto per $fetchUrl (id=$safeId)');
        return null;
      }

      // Compress before upload (same params as YuGiOh/Pokémon).
      // Guard: flutter_image_compress only works on Android/iOS.
      var uploadBytes = response.bodyBytes;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final compressed = await FlutterImageCompress.compressWithList(
            uploadBytes,
            minWidth: 400,
            quality: 78,
            format: CompressFormat.jpeg,
          );
          if (compressed.isNotEmpty) uploadBytes = compressed;
        } catch (_) {
          // Compression failed; upload original bytes.
        }
      }

      return await BackblazeService.uploadBytes(
        bytes: uploadBytes,
        catalog: catalog,
        cardId: cardId,
        setCode: setCode,
      );
    } catch (e) {
      debugPrint('[ImageUpload] Errore per $sourceUrl (id=$safeId): $e');
      return null;
    }
  }

  /// Processes a card before publishing:
  /// - uploads image to Firebase Storage
  /// - stores the Storage URL inside each EN set as `image_url`
  /// - removes the top-level `image_url` (ygoprodeck URL)
  Future<Map<String, dynamic>> _processCardForStorage(Map<String, dynamic> card) async {
    final catalog = card['catalog'] as String? ?? 'yugioh';
    final cardId = card['id'] ?? card['api_id'];
    if (cardId == null) return card;

    final sourceUrl = card['image_url'] as String?;
    final storageUrl = await _uploadCardImageIfNeeded(catalog, cardId, sourceUrl);

    final updatedCard = Map<String, dynamic>.from(card);

    // Remove the ygoprodeck top-level image_url
    updatedCard.remove('image_url');

    if (storageUrl != null) {
      // Store Backblaze URL at card level (backward compat for web / old clients)
      updatedCard['imageUrl'] = storageUrl;

      if (catalog == 'onepiece') {
        // One Piece: update artwork in each print entry
        final prints = updatedCard['prints'];
        if (prints is List) {
          updatedCard['prints'] = prints.map((p) {
            final print = Map<String, dynamic>.from(p as Map);
            final existingArtwork = print['artwork'] as String?;
            if (existingArtwork == null || existingArtwork.isEmpty ||
                !_isHostedImageUrl(existingArtwork)) {
              print['artwork'] = storageUrl;
            }
            return print;
          }).toList();
        }
      } else {
        // Other catalogs: add per-set image_url to each EN set entry
        final sets = updatedCard['sets'];
        if (sets is Map) {
          final updatedSets = Map<String, dynamic>.from(sets);
          final enSets = updatedSets['en'];
          if (enSets is List) {
            updatedSets['en'] = enSets.map((s) {
              final entry = Map<String, dynamic>.from(s as Map);
              final existingUrl = entry['image_url'] as String?;
              // Replace ygoprodeck URLs with Firebase Storage URL; preserve admin-set Storage URLs
              if (existingUrl == null || existingUrl.isEmpty ||
                  !_isHostedImageUrl(existingUrl)) {
                entry['image_url'] = storageUrl;
              }
              return entry;
            }).toList();
          }
          updatedCard['sets'] = updatedSets;
        }
      }
    }

    return updatedCard;
  }

  /// Runs _processCardForStorage for all add/edit changes in parallel
  /// (up to [_uploadConcurrency] concurrent uploads).
  /// Returns a map from changeId → processed card data.
  Future<Map<String, Map<String, dynamic>>> _preprocessChanges(
    List<PendingCatalogChange> changes,
  ) async {
    final sem = _Semaphore(_uploadConcurrency);
    final results = <String, Map<String, dynamic>>{};
    await Future.wait(
      changes
          .where((c) => c.type == ChangeType.add || c.type == ChangeType.edit)
          .map((change) async {
        await sem.acquire();
        try {
          results[change.changeId] = await _processCardForStorage(change.cardData);
        } finally {
          sem.release();
        }
      }),
    );
    return results;
  }

  // ============================================================
  // Pending Changes
  // ============================================================

  /// Get all pending changes from local storage
  Future<List<PendingCatalogChange>> getPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final changesJson = prefs.getString(_pendingChangesKey);

    if (changesJson == null) return [];

    final List<dynamic> changesList = json.decode(changesJson);
    return changesList
        .map((change) => PendingCatalogChange.fromMap(change as Map<String, dynamic>))
        .toList();
  }

  /// Save pending changes to local storage
  Future<void> _savePendingChanges(List<PendingCatalogChange> changes) async {
    final prefs = await SharedPreferences.getInstance();
    final changesJson = json.encode(changes.map((c) => c.toMap()).toList());
    await prefs.setString(_pendingChangesKey, changesJson);
  }

  /// Add a new pending change
  Future<void> addPendingChange(PendingCatalogChange change) async {
    final changes = await getPendingChanges();
    changes.add(change);
    await _savePendingChanges(changes);
  }

  /// Remove a pending change
  Future<void> removePendingChange(String changeId) async {
    final changes = await getPendingChanges();
    changes.removeWhere((c) => c.changeId == changeId);
    await _savePendingChanges(changes);
  }

  /// Clear all pending changes
  Future<void> clearPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingChangesKey);
  }

  /// Get count of pending changes
  Future<int> getPendingChangesCount() async {
    final changes = await getPendingChanges();
    return changes.length;
  }

  /// Publish all pending changes to Firestore.
  ///
  /// Uses surgical chunk updates: only the chunks that actually contain
  /// modified cards are rewritten, instead of the entire catalog.
  /// For 1 card edit among 13,000 cards across 70 chunks, this reduces
  /// writes from ~70 to 1, saving ~98% of write traffic.
  Future<void> publishChanges({
    required String adminUid,
    required Function(int current, int total) onProgress,
  }) async {
    final changes = await getPendingChanges();
    if (changes.isEmpty) return;

    // Group changes by catalog
    final changesByCatalog = <String, List<PendingCatalogChange>>{};
    for (final change in changes) {
      final catalog = change.cardData['catalog'] as String? ?? 'yugioh';
      changesByCatalog.putIfAbsent(catalog, () => []).add(change);
    }

    // Process each catalog with surgical chunk updates
    for (final catalogEntry in changesByCatalog.entries) {
      await _publishCatalogChangesSurgical(
        catalog: catalogEntry.key,
        changes: catalogEntry.value,
        adminUid: adminUid,
        onProgress: onProgress,
      );
    }

    await clearPendingChanges();
  }

  /// Surgical publish: uses the card_index to locate cards directly, then
  /// downloads and writes ONLY the affected chunks.
  /// Falls back to a full download if the card_index is missing or stale,
  /// and rebuilds the index as a side-effect so subsequent publishes are fast.
  Future<void> _publishCatalogChangesSurgical({
    required String catalog,
    required List<PendingCatalogChange> changes,
    required String adminUid,
    required Function(int, int) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';

    // 1. Load card index (cardId → chunkId) and metadata
    final cardIndex = await _loadCardIndex(catalogCollection);
    final metadataDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    if (!metadataDoc.exists) return;

    final totalChunks = metadataDoc.data()?['totalChunks'] as int? ?? 0;
    final currentVersion = metadataDoc.data()?['version'] as int? ?? 0;
    var currentTotalCards = metadataDoc.data()?['totalCards'] as int? ?? 0;

    // 2. Sort changes oldest-first
    final sortedChanges = List<PendingCatalogChange>.from(changes)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 3. Determine which chunks to fetch using the card index.
    //    If any edit/delete target is missing from the index, fall back to
    //    full download so the index can be rebuilt from a clean state.
    final chunksToFetch = <String>{};
    bool needsFallback = false;
    for (final change in sortedChanges) {
      if (change.type == ChangeType.edit || change.type == ChangeType.delete) {
        final targetId =
            (change.originalCardId ?? change.cardData['id'])?.toString();
        if (targetId == null) continue;
        final chunkId = cardIndex[targetId];
        if (chunkId != null) {
          chunksToFetch.add(chunkId);
        } else {
          needsFallback = true;
          break;
        }
      }
    }

    if (needsFallback) {
      // Card index is stale or missing: one or more edited/deleted cards are not
      // tracked in the index. Fall back to a full catalog download to locate them,
      // then rebuild and persist the index so subsequent publishes use the fast path.
      await _publishWithFullDownloadAndRebuildIndex(
        catalogCollection: catalogCollection,
        sortedChanges: sortedChanges,
        adminUid: adminUid,
        onProgress: onProgress,
      );
      return;
    }

    // For adds, fetch the last existing chunk (it may have room)
    String? lastChunkId;
    final hasAdds = sortedChanges.any((c) => c.type == ChangeType.add);
    if (hasAdds && totalChunks > 0) {
      lastChunkId = 'chunk_${totalChunks.toString().padLeft(3, '0')}';
      chunksToFetch.add(lastChunkId);
    }

    // 4. Download only the needed chunks
    final totalSteps = chunksToFetch.length + sortedChanges.length + 3;
    int step = 0;
    final chunkMap = <String, List<Map<String, dynamic>>>{};
    for (final chunkId in chunksToFetch) {
      final chunkDoc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      chunkMap[chunkId] = chunkDoc.exists
          ? (chunkDoc.data()?['cards'] as List<dynamic>? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map))
              .toList()
          : [];
      onProgress(++step, totalSteps);
    }

    // 5. Apply changes, track affected chunks and index mutations.
    // Pre-process all images in parallel before the sequential chunk-assignment loop.
    final preprocessed = await _preprocessChanges(sortedChanges);

    final affectedChunkIds = <String>{};
    final deletedCardIds = <dynamic>[];
    final updatedCardIndex = Map<String, String>.from(cardIndex);
    int chunksCreated = 0;
    int chunksRemoved = 0;

    for (final change in sortedChanges) {
      switch (change.type) {
        case ChangeType.edit:
        case ChangeType.delete:
          final targetId = change.originalCardId ?? change.cardData['id'];
          final targetIdStr = targetId?.toString();
          if (targetIdStr == null) break;
          final chunkId = cardIndex[targetIdStr];
          if (chunkId == null || !chunkMap.containsKey(chunkId)) break;
          final cards = chunkMap[chunkId]!;
          final idx = cards.indexWhere((c) => c['id'] == targetId);
          if (idx == -1) break;
          if (change.type == ChangeType.edit) {
            cards[idx] = preprocessed[change.changeId] ?? await _processCardForStorage(change.cardData);
          } else {
            cards.removeAt(idx);
            deletedCardIds.add(targetId);
            updatedCardIndex.remove(targetIdStr);
            currentTotalCards--;
            if (cards.isEmpty) chunksRemoved++;
          }
          affectedChunkIds.add(chunkId);
          break;

        case ChangeType.add:
          final processedCard = preprocessed[change.changeId] ?? await _processCardForStorage(change.cardData);
          final cardId = processedCard['id'];
          lastChunkId ??= totalChunks > 0
              ? 'chunk_${totalChunks.toString().padLeft(3, '0')}'
              : null;
          if (lastChunkId != null && chunkMap.containsKey(lastChunkId)) {
            final lastChunk = chunkMap[lastChunkId]!;
            if (lastChunk.length < _chunkSize) {
              lastChunk.add(processedCard);
              affectedChunkIds.add(lastChunkId);
              if (cardId != null) updatedCardIndex[cardId.toString()] = lastChunkId;
            } else {
              final newChunkNum = totalChunks + chunksCreated + 1;
              final newChunkId = 'chunk_${newChunkNum.toString().padLeft(3, '0')}';
              chunkMap[newChunkId] = [processedCard];
              affectedChunkIds.add(newChunkId);
              lastChunkId = newChunkId;
              chunksCreated++;
              if (cardId != null) updatedCardIndex[cardId.toString()] = newChunkId;
            }
          } else {
            // No existing chunks — create the first one
            const newChunkId = 'chunk_001';
            chunkMap[newChunkId] = [processedCard];
            affectedChunkIds.add(newChunkId);
            lastChunkId = newChunkId;
            chunksCreated++;
            if (cardId != null) updatedCardIndex[cardId.toString()] = newChunkId;
          }
          currentTotalCards++;
          break;
      }
      onProgress(++step, totalSteps);
    }

    // 6. Write only affected chunks
    for (final chunkId in affectedChunkIds) {
      final cards = chunkMap[chunkId]!;
      if (cards.isEmpty) {
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .delete();
      } else {
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .set({'cards': cards});
      }
    }

    // 7. Persist the updated card index
    await _saveCardIndex(catalogCollection, updatedCardIndex);
    onProgress(++step, totalSteps);

    // 8. Update metadata using tracked deltas (no need to recount all chunks)
    final newTotalChunks = totalChunks + chunksCreated - chunksRemoved;
    await _firestore.collection(catalogCollection).doc('metadata').set({
      'totalCards': currentTotalCards,
      'totalChunks': newTotalChunks,
      'chunkSize': _chunkSize,
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
      'updatedBy': adminUid,
      'modifiedChunks': affectedChunkIds.toList(),
      'deletedCards': deletedCardIds,
    });
    onProgress(totalSteps, totalSteps);
  }

  /// Fallback path: downloads ALL chunks, applies changes, then rebuilds and
  /// saves the card_index so subsequent publishes use the optimized path.
  Future<void> _publishWithFullDownloadAndRebuildIndex({
    required String catalogCollection,
    required List<PendingCatalogChange> sortedChanges,
    required String adminUid,
    required Function(int, int) onProgress,
  }) async {
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) return;

    final sortedChunkIds = chunkMap.keys.toList()..sort();
    final affectedChunkIds = <String>{};
    final deletedCardIds = <dynamic>[];

    // Pre-process all images in parallel before the sequential chunk-assignment loop.
    final preprocessed = await _preprocessChanges(sortedChanges);

    for (final change in sortedChanges) {
      switch (change.type) {
        case ChangeType.edit:
        case ChangeType.delete:
          final targetId = change.originalCardId ?? change.cardData['id'];
          for (final chunkId in sortedChunkIds) {
            final cards = chunkMap[chunkId]!;
            final idx = cards.indexWhere((c) => c['id'] == targetId);
            if (idx != -1) {
              if (change.type == ChangeType.edit) {
                cards[idx] = preprocessed[change.changeId] ?? await _processCardForStorage(change.cardData);
              } else {
                cards.removeAt(idx);
                deletedCardIds.add(targetId);
              }
              affectedChunkIds.add(chunkId);
              break;
            }
          }
          break;

        case ChangeType.add:
          final processedCard = preprocessed[change.changeId] ?? await _processCardForStorage(change.cardData);
          if (sortedChunkIds.isEmpty) {
            const newChunkId = 'chunk_001';
            chunkMap[newChunkId] = [processedCard];
            sortedChunkIds.add(newChunkId);
            affectedChunkIds.add(newChunkId);
            break;
          }
          final lastChunkId = sortedChunkIds.last;
          final lastChunk = chunkMap[lastChunkId]!;
          if (lastChunk.length < _chunkSize) {
            lastChunk.add(processedCard);
            affectedChunkIds.add(lastChunkId);
          } else {
            final newIndex = sortedChunkIds.length + 1;
            final newChunkId = 'chunk_${newIndex.toString().padLeft(3, '0')}';
            chunkMap[newChunkId] = [processedCard];
            sortedChunkIds.add(newChunkId);
            affectedChunkIds.add(newChunkId);
          }
          break;
      }
    }

    // Write affected chunks
    for (final chunkId in affectedChunkIds) {
      final cards = chunkMap[chunkId]!;
      if (cards.isEmpty) {
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .delete();
      } else {
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .set({'cards': cards});
      }
    }

    // Rebuild card index from the full (now-updated) chunk map
    final newIndex = <String, String>{};
    for (final entry in chunkMap.entries) {
      for (final card in entry.value) {
        final cardId = card['id'];
        if (cardId != null) newIndex[cardId.toString()] = entry.key;
      }
    }
    await _saveCardIndex(catalogCollection, newIndex);

    // Update metadata
    final nonEmptyChunks = chunkMap.values.where((c) => c.isNotEmpty).toList();
    final totalCards = nonEmptyChunks.fold(0, (acc, c) => acc + c.length);
    final metadataDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    final currentVersion = metadataDoc.exists
        ? (metadataDoc.data()?['version'] as int? ?? 0)
        : 0;
    await _firestore.collection(catalogCollection).doc('metadata').set({
      'totalCards': totalCards,
      'totalChunks': nonEmptyChunks.length,
      'chunkSize': _chunkSize,
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
      'updatedBy': adminUid,
      'modifiedChunks': affectedChunkIds.toList(),
      'deletedCards': deletedCardIds,
    });
  }

  /// Load the card index (cardId → chunkId) from Firestore.
  /// Returns an empty map if the index document doesn't exist yet.
  Future<Map<String, String>> _loadCardIndex(String catalogCollection) async {
    try {
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('card_index')
          .get();
      if (!doc.exists) return {};
      final data = doc.data()?['cards'];
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  /// Persist the card index to Firestore.
  Future<void> _saveCardIndex(
      String catalogCollection, Map<String, String> index) async {
    await _firestore
        .collection(catalogCollection)
        .doc('card_index')
        .set({'cards': index});
  }

  /// Downloads all chunks as an ordered map: `chunkId` → mutable list of cards.
  Future<Map<String, List<Map<String, dynamic>>>> _downloadChunksMap(
    String catalogCollection,
    Function(int, int) onProgress,
  ) async {
    final metadataDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();

    if (!metadataDoc.exists) return {};

    final totalChunks = metadataDoc.data()?['totalChunks'] as int? ?? 0;
    final chunkMap = <String, List<Map<String, dynamic>>>{};

    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final chunkDoc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();

      if (chunkDoc.exists) {
        final cards = chunkDoc.data()?['cards'] as List<dynamic>? ?? [];
        chunkMap[chunkId] = cards
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
      }

      onProgress(i + 1, totalChunks);
    }

    return chunkMap;
  }

  /// Download current catalog from Firestore (public method for admin UI).
  Future<List<Map<String, dynamic>>> downloadCurrentCatalog(
    String catalog, {
    required Function(int, int) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    return chunkMap.values.expand((cards) => cards).toList();
  }

  /// Migrates all catalog card images from external URLs to Firebase Storage.
  ///
  /// Only processes cards that have `image_url` (external source) but no
  /// `imageUrl` (Backblaze URL). Already-migrated cards are skipped.
  ///
  /// Returns `{migrated, failed, chunksUpdated}`.
  Future<Map<String, dynamic>> migrateAllImagesToStorage({
    required String catalog,
    required String adminUid,
    required Function(int current, int total) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';

    // 1. Download all chunks
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) {
      return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};
    }

    final sortedChunkIds = chunkMap.keys.toList()..sort();

    // 2. Collect ALL cards — ricostruisce la URL sorgente anche se image_url è già stato rimosso
    final toMigrate = <({String chunkId, int cardIndex, dynamic cardId, String sourceUrl})>[];
    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final cardId = card['id'] ?? card['api_id'];

        // Salta se l'immagine è già su Backblaze (o legacy Backblaze)
        final existingUrl = card['imageUrl'] as String?;
        if (existingUrl != null && _isHostedImageUrl(existingUrl)) continue;

        // 1. URL originale API ancora presente (non ancora migrata)
        String? sourceUrl = card['image_url'] as String?;

        // 2. Per YuGiOh: ricostruisce da ID numerico
        if ((sourceUrl == null || sourceUrl.isEmpty) && catalog == 'yugioh' && card['id'] != null) {
          sourceUrl = 'https://images.ygoprodeck.com/images/cards/${card['id']}.jpg';
        }

        if (sourceUrl != null && sourceUrl.isNotEmpty && cardId != null) {
          toMigrate.add((
            chunkId: chunkId,
            cardIndex: i,
            cardId: cardId,
            sourceUrl: sourceUrl,
          ));
        }
      }
    }

    if (toMigrate.isEmpty) {
      return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};
    }

    // 3. Upload each image and update in-memory chunk data
    int migrated = 0, failed = 0;
    final affectedChunkIds = <String>{};

    for (int i = 0; i < toMigrate.length; i++) {
      final item = toMigrate[i];
      onProgress(i + 1, toMigrate.length);

      final storageUrl = await _uploadCardImageIfNeeded(catalog, item.cardId, item.sourceUrl);
      if (storageUrl != null) {
        final card = chunkMap[item.chunkId]![item.cardIndex];
        final updatedCard = Map<String, dynamic>.from(card);
        updatedCard.remove('image_url');
        updatedCard['imageUrl'] = storageUrl;

        // Populate image_url on all language set entries, replacing ygoprodeck
        // URLs with Backblaze URL; existing Backblaze URLs are preserved
        final sets = updatedCard['sets'];
        if (sets is Map) {
          final updatedSets = Map<String, dynamic>.from(sets);
          for (final lang in _apiLangs) {
            final langSets = updatedSets[lang];
            if (langSets is List) {
              updatedSets[lang] = langSets.map((s) {
                final entry = Map<String, dynamic>.from(s as Map);
                final existingUrl = entry['image_url'] as String?;
                if (existingUrl == null || existingUrl.isEmpty ||
                    !_isHostedImageUrl(existingUrl)) {
                  entry['image_url'] = storageUrl;
                }
                return entry;
              }).toList();
            }
          }
          updatedCard['sets'] = updatedSets;
        }

        chunkMap[item.chunkId]![item.cardIndex] = updatedCard;
        affectedChunkIds.add(item.chunkId);
        migrated++;
      } else {
        failed++;
      }
    }

    // 4. Write only the modified chunks back to Firestore
    for (final chunkId in affectedChunkIds) {
      await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .set({'cards': chunkMap[chunkId]!});
    }

    // 5. Bump the catalog version in metadata
    final metadataDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    final currentVersion =
        metadataDoc.exists ? (metadataDoc.data()?['version'] as int? ?? 0) : 0;
    await _firestore.collection(catalogCollection).doc('metadata').set({
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    return {
      'migrated': migrated,
      'failed': failed,
      'chunksUpdated': affectedChunkIds.length,
    };
  }

  // ============================================================
  // YGOPRODeck API — Catalog Population
  // ============================================================

  static const String _ygoprodeckApiUrl =
      'https://db.ygoprodeck.com/api/v7/cardinfo.php';
  static const List<String> _apiLangs = ['en', 'it', 'fr', 'de', 'pt', 'sp'];

  /// Downloads the **full** catalog from YGOPRODeck API and replaces all
  /// Firestore chunks. Admin-modified cards and existing Firebase Storage
  /// imageUrls are preserved from the current catalog.
  Future<Map<String, dynamic>> downloadFullCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    // 1. Fetch EN (base catalog)
    onProgress('Scaricando catalogo EN da YGOPRODeck...', null);
    final enCards = await _fetchApiForLang('en');
    if (enCards.isEmpty) throw Exception('Nessuna carta ricevuta dall\'API EN');

    // 2. Fetch translations sequentially to avoid holding multiple large API
    //    responses in memory at the same time (~30 MB each).
    //    Each response is parsed into a compact id→{name,desc} map immediately
    //    so the raw JSON can be garbage-collected before the next fetch.
    onProgress('EN: ${enCards.length} carte. Scaricando IT...', null);
    final itMap = _buildTranslationMap(await _fetchApiForLangSafe('it'));

    onProgress('Scaricando FR...', null);
    final frMap = _buildTranslationMap(await _fetchApiForLangSafe('fr'));

    onProgress('Scaricando DE...', null);
    final deMap = _buildTranslationMap(await _fetchApiForLangSafe('de'));

    onProgress('Scaricando PT...', null);
    final ptMap = _buildTranslationMap(await _fetchApiForLangSafe('pt'));

    // 3. Load existing catalog: preserve admin edits + Storage imageUrls.
    //    Skip if catalog is empty (first download) to avoid downloading 60+ MB
    //    of chunks just to find zero admin-modified cards.
    onProgress('Recuperando dati esistenti da Firestore...', null);
    final catalogMeta = await _firestore
        .collection('yugioh_catalog')
        .doc('metadata')
        .get();
    final hasExistingCatalog =
        catalogMeta.exists && (catalogMeta.data()?['totalCards'] as int? ?? 0) > 0;

    Map<int, Map<String, dynamic>> existingMap = {};
    if (hasExistingCatalog) {
      try {
        existingMap = await _getExistingCardsMap('yugioh_catalog')
            .timeout(const Duration(seconds: 60));
      } catch (e) { // ignore: empty_catches

      }
    }

    final adminModified = Map<int, Map<String, dynamic>>.fromEntries(
      existingMap.entries.where((e) => e.value['_adminModified'] == true),
    );
    final imageUrlMap = <int, String>{};
    for (final entry in existingMap.entries) {
      final url = entry.value['imageUrl'] as String?;
      if (_isHostedImageUrl(url)) {
        imageUrlMap[entry.key] = url!;
      }
    }

    // 4. Transform API data into internal format
    onProgress('Processando ${enCards.length} carte...', null);
    final transformed = _transformYGOProDeckCards(
      enCards,
      itMap: itMap,
      frMap: frMap,
      deMap: deMap,
      ptMap: ptMap,
    );

    // 5. Merge: restore admin modifications; re-apply Storage imageUrls
    final mergedCards = transformed.map((card) {
      final id = card['id'] as int?;
      if (id == null) return card;
      if (adminModified.containsKey(id)) return adminModified[id]!;
      final imageUrl = imageUrlMap[id];
      if (imageUrl != null) {
        return Map<String, dynamic>.from(card)..['imageUrl'] = imageUrl;
      }
      return card;
    }).toList();

    // 6. Upload all chunks (full replace)
    await _uploadCatalogChunks(
      catalogCollection: 'yugioh_catalog',
      cards: mergedCards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {
      'totalCards': mergedCards.length,
      'preservedAdminCards': adminModified.length,
    };
  }

  /// Downloads **only new cards** (not already in Firestore) from YGOPRODeck
  /// and appends them to the existing catalog.
  Future<Map<String, dynamic>> downloadIncrementalCatalog({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando lista carte da YGOPRODeck (EN)...', null);
    final allCards = await _fetchApiForLang('en');

    onProgress('Verificando carte esistenti su Firestore...', null);
    final existingIds = await _getExistingCardIds('yugioh_catalog');

    final newRaw =
        allCards.where((c) => !existingIds.contains(c['id'] as int?)).toList();

    if (newRaw.isEmpty) return {'newCards': 0};

    onProgress('${newRaw.length} carte nuove. Elaborando...', null);
    final rawCards = _transformYGOProDeckCards(newRaw);

    // Upload images in parallel for new cards only.
    onProgress('Caricando immagini per ${rawCards.length} carte nuove...', 0);
    final sem = _Semaphore(_uploadConcurrency);
    int imagesOk = 0, imagesFail = 0;
    final newCards = await Future.wait(rawCards.asMap().entries.map((e) async {
      final card = Map<String, dynamic>.from(e.value);
      final sourceUrl = card['image_url'] as String?;
      final cardId = card['id'];
      if (sourceUrl != null && sourceUrl.isNotEmpty && cardId != null) {
        await sem.acquire();
        try {
          final url = await _uploadCardImageIfNeeded('yugioh', cardId, sourceUrl);
          if (url != null) {
            card.remove('image_url');
            card['imageUrl'] = url;
            imagesOk++;
          } else {
            imagesFail++;
          }
        } finally {
          sem.release();
        }
      }
      if (e.key % 50 == 0) {
        onProgress('Immagini: ${e.key + 1}/${rawCards.length}...', (e.key + 1) / rawCards.length);
      }
      return card;
    }));

    await _uploadCatalogChunks(
      catalogCollection: 'yugioh_catalog',
      cards: newCards,
      adminUid: adminUid,
      isIncremental: true,
      onProgress: (cur, tot) =>
          onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {'newCards': newCards.length, 'imagesOk': imagesOk, 'imagesFail': imagesFail};
  }

  /// Fills missing localized sets for all cards in the given catalog,
  /// using surgical per-chunk writes.
  /// Supported: 'yugioh', 'pokemon', 'onepiece'
  Future<Map<String, dynamic>> fillMissingLocalizedSets({
    required String catalog,
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';

    onProgress('Leggendo metadati...', null);
    final metadataDoc =
        await _firestore.collection(catalogCollection).doc('metadata').get();
    final totalChunks =
        metadataDoc.exists ? (metadataDoc.data()?['totalChunks'] as int? ?? 0) : 0;

    if (totalChunks == 0) throw Exception('Catalogo vuoto su Firestore');

    int processedChunks = 0;
    int modifiedChunks = 0;
    int modifiedCards = 0;

    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      processedChunks++;
      onProgress(
        'Chunk $processedChunks/$totalChunks'
        '${modifiedChunks > 0 ? " ($modifiedCards aggiornate)" : ""}...',
        processedChunks / totalChunks,
      );

      final chunkDoc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();

      if (!chunkDoc.exists) continue;

      final rawCards = chunkDoc.data()?['cards'] as List<dynamic>? ?? [];
      bool chunkModified = false;

      final updatedCards = rawCards.map((raw) {
        final card = Map<String, dynamic>.from(raw as Map);
        final updated = _fillMissingSets(card);
        if (!identical(updated, card)) {
          chunkModified = true;
          modifiedCards++;
        }
        return updated;
      }).toList();

      if (chunkModified) {
        modifiedChunks++;
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .set({'cards': updatedCards});
      }
    }

    if (modifiedChunks > 0) {
      final currentVersion = metadataDoc.exists
          ? (metadataDoc.data()?['version'] as int? ?? 0)
          : 0;
      await _firestore.collection(catalogCollection).doc('metadata').set({
        'version': currentVersion + 1,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
      }, SetOptions(merge: true));
    }

    return {
      'modifiedCards': modifiedCards,
      'modifiedChunks': modifiedChunks,
      'totalChunks': totalChunks,
    };
  }

  // ─── YGOPRODeck API helpers ──────────────────────────────────────────────

  Future<List<dynamic>> _fetchApiForLang(String lang) async {
    final url = lang == 'en'
        ? _ygoprodeckApiUrl
        : '$_ygoprodeckApiUrl?language=$lang';
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) {
      throw Exception('Errore API ($lang): HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return (data['data'] as List<dynamic>?) ?? [];
  }

  Future<List<dynamic>> _fetchApiForLangSafe(String lang) async {
    try {
      return await _fetchApiForLang(lang);
    } catch (e) { // ignore: empty_catches

      return [];
    }
  }

  Map<int, Map<String, String>> _buildTranslationMap(List<dynamic> cards) {
    final map = <int, Map<String, String>>{};
    for (final c in cards) {
      final id = c['id'] as int?;
      if (id == null) continue;
      final name = c['name']?.toString() ?? '';
      final desc = c['desc']?.toString() ?? '';
      if (name.isNotEmpty || desc.isNotEmpty) {
        map[id] = {'name': name, 'desc': desc};
      }
    }
    return map;
  }

  List<Map<String, dynamic>> _transformYGOProDeckCards(
    List<dynamic> apiCards, {
    Map<int, Map<String, String>> itMap = const {},
    Map<int, Map<String, String>> frMap = const {},
    Map<int, Map<String, String>> deMap = const {},
    Map<int, Map<String, String>> ptMap = const {},
  }) {
    return apiCards.map((card) {
      final cardId = card['id'] as int?;
      final cardSets = card['card_sets'] as List<dynamic>? ?? [];

      // Compute primary image URL first so it can be stored per-set
      // (image belongs to each individual set/print, not just at card level)
      final cardImages = card['card_images'] as List<dynamic>?;
      final imageUrl = cardImages != null && cardImages.isNotEmpty
          ? (cardImages[0] as Map)['image_url'] as String?
          : null;

      final setsByLang = <String, List<Map<String, dynamic>>>{
        for (final l in _apiLangs) l: [],
      };
      for (final set in cardSets) {
        final setCode = set['set_code']?.toString() ?? '';
        final lang = _detectSetLanguage(setCode);
        if (setsByLang.containsKey(lang)) {
          setsByLang[lang]!.add({
            'set_code': setCode,
            'set_name': set['set_name']?.toString() ?? '',
            'print_code': setCode,
            'rarity': set['set_rarity']?.toString() ?? '',
            'rarity_code': set['set_rarity_code']?.toString() ?? '',
            // set_price intentionally omitted — CardTrader is the price source
            if (imageUrl != null) 'image_url': imageUrl,
          });
        }
      }
      final setsMap = <String, dynamic>{};
      for (final entry in setsByLang.entries) {
        if (entry.value.isNotEmpty) setsMap[entry.key] = entry.value;
      }

      final it = cardId != null ? itMap[cardId] : null;
      final fr = cardId != null ? frMap[cardId] : null;
      final de = cardId != null ? deMap[cardId] : null;
      final pt = cardId != null ? ptMap[cardId] : null;

      return <String, dynamic>{
        'id': cardId,
        'type': card['type'] ?? '',
        'human_readable_type':
            card['humanReadableCardType'] ?? card['type'] ?? '',
        'frame_type': card['frameType'] ?? '',
        'race': card['race'] ?? '',
        'archetype': card['archetype'],
        'ygoprodeck_url': 'https://ygoprodeck.com/card/$cardId',
        'image_url': imageUrl,
        'atk': card['atk'],
        'def': card['def'],
        'level': card['level'],
        'attribute': card['attribute'],
        'scale': card['scale'],
        'linkval': card['linkval'],
        'linkmarkers': (card['linkmarkers'] as List<dynamic>?)?.join(','),
        'name': card['name'] ?? '',
        'description': card['desc'] ?? '',
        if (it?['name'] != null && it!['name']!.isNotEmpty) 'name_it': it['name'],
        if (it?['desc'] != null && it!['desc']!.isNotEmpty) 'description_it': it['desc'],
        if (fr?['name'] != null && fr!['name']!.isNotEmpty) 'name_fr': fr['name'],
        if (fr?['desc'] != null && fr!['desc']!.isNotEmpty) 'description_fr': fr['desc'],
        if (de?['name'] != null && de!['name']!.isNotEmpty) 'name_de': de['name'],
        if (de?['desc'] != null && de!['desc']!.isNotEmpty) 'description_de': de['desc'],
        if (pt?['name'] != null && pt!['name']!.isNotEmpty) 'name_pt': pt['name'],
        if (pt?['desc'] != null && pt!['desc']!.isNotEmpty) 'description_pt': pt['desc'],
        if (setsMap.isNotEmpty) 'sets': setsMap,
      };
    }).toList();
  }

  // ─── Localized set helpers ───────────────────────────────────────────────

  Map<String, String>? _parseSetCode(String setCode) {
    final match =
        RegExp(r'^([A-Z0-9]+)-(EN|IT|FR|DE|PT|SP|E|I|F|D|P|S)(.+)$')
            .firstMatch(setCode.toUpperCase());
    if (match == null) return null;
    return {
      'prefix': match.group(1)!,
      'lang': match.group(2)!,
      'num': match.group(3)!,
    };
  }

  String _detectSetLanguage(String setCode) {
    final parsed = _parseSetCode(setCode);
    if (parsed == null) return 'en';
    switch (parsed['lang']) {
      case 'IT':
      case 'I':
        return 'it';
      case 'FR':
      case 'F':
        return 'fr';
      case 'DE':
      case 'D':
        return 'de';
      case 'PT':
      case 'P':
        return 'pt';
      case 'SP':
      case 'S':
        return 'sp';
      default:
        return 'en';
    }
  }

  String? _generateLocalizedSetCode(String enSetCode, String targetLang) {
    final parsed = _parseSetCode(enSetCode);
    if (parsed == null) return null;
    final isShort = parsed['lang']!.length == 1;
    final String? targetCode = switch (targetLang) {
      'it' => isShort ? 'I' : 'IT',
      'fr' => isShort ? 'F' : 'FR',
      'de' => isShort ? 'D' : 'DE',
      'pt' => isShort ? 'P' : 'PT',
      'sp' => isShort ? 'S' : 'SP',
      _ => null,
    };
    if (targetCode == null) return null;
    return '${parsed['prefix']!}-$targetCode${parsed['num']!}';
  }

  bool _generateMissingSetsFromEn(
      Map<String, List<Map<String, dynamic>>> setsByLang) {
    final enSets = List<Map<String, dynamic>>.from(setsByLang['en'] ?? []);
    if (enSets.isEmpty) return false;
    bool changed = false;
    for (final lang in ['it', 'fr', 'de', 'pt', 'sp']) {
      final existingByCode = <String, Map<String, dynamic>>{};
      for (final s in List.from(setsByLang[lang] ?? [])) {
        final code = (s['set_code']?.toString() ?? '').toUpperCase();
        if (code.isNotEmpty) existingByCode.putIfAbsent(code, () => s);
      }
      final newList = <Map<String, dynamic>>[];
      for (final enSet in enSets) {
        final enCode = enSet['set_code']?.toString() ?? '';
        final localCode = _generateLocalizedSetCode(enCode, lang);
        // Skip EN codes that don't follow the YGO set-code pattern (e.g. Pokemon api_ids,
        // One Piece serials) — generating a localised copy would be wrong/useless.
        if (localCode == null) continue;
        final targetCode = localCode;
        final targetUpper = targetCode.toUpperCase();
        final enUpper = enCode.toUpperCase();
        final existing =
            existingByCode[targetUpper] ?? existingByCode[enUpper];
        if (existing != null) {
          final existingCode =
              (existing['set_code']?.toString() ?? '').toUpperCase();
          if (existingCode != targetUpper) {
            newList.add(Map<String, dynamic>.from(existing)
              ..['set_code'] = targetCode
              ..['print_code'] = targetCode);
            changed = true;
          } else {
            newList.add(existing);
          }
        } else {
          newList.add({
            'set_code': targetCode,
            'set_name': enSet['set_name'] ?? '',
            'print_code': targetCode,
            'rarity': enSet['rarity'] ?? '',
            'rarity_code': enSet['rarity_code'] ?? '',
            'set_price': null,
            if (enSet['image_url'] != null) 'image_url': enSet['image_url'],
          });
          changed = true;
        }
      }
      if (newList.length != (setsByLang[lang]?.length ?? 0)) changed = true;
      setsByLang[lang] = newList;
    }
    return changed;
  }

  Map<String, dynamic> _fillMissingSets(Map<String, dynamic> card) {
    final rawSets = card['sets'];
    final rawPrints = card['prints'];

    // One Piece cards use 'prints' list with 'card_set_id' entries (not 'set_code').
    // Converting them to a 'sets' map would destroy the print data used by insertOnepieceCards.
    if (rawPrints is List && rawPrints.isNotEmpty) {
      final first = rawPrints.first;
      if (first is Map && first.containsKey('card_set_id')) return card;
    }

    final setsByLang = <String, List<Map<String, dynamic>>>{
      for (final l in _apiLangs) l: [],
    };
    if (rawSets is Map) {
      for (final lang in _apiLangs) {
        final langSets = rawSets[lang];
        if (langSets is List) {
          setsByLang[lang] =
              langSets.map((s) => Map<String, dynamic>.from(s as Map)).toList();
        }
      }
    } else if (rawPrints is List) {
      for (final p in rawPrints) {
        final setCode = p['set_code']?.toString() ?? '';
        final lang = _detectSetLanguage(setCode);
        if (setsByLang.containsKey(lang)) {
          setsByLang[lang]!.add({
            'set_code': setCode,
            'set_name': p['set_name']?.toString() ?? '',
            'print_code': setCode,
            'rarity': p['rarity']?.toString() ?? '',
            'rarity_code': p['rarity_code']?.toString() ?? '',
            // set_price intentionally omitted — CardTrader is the price source
          });
        }
      }
    }
    final bool setsChanged = _generateMissingSetsFromEn(setsByLang);
    final bool changed = setsChanged || rawPrints != null;
    if (!changed) return card;
    final setsMap = <String, dynamic>{};
    for (final entry in setsByLang.entries) {
      if (entry.value.isNotEmpty) setsMap[entry.key] = entry.value;
    }
    final updated = Map<String, dynamic>.from(card);
    if (setsMap.isNotEmpty) updated['sets'] = setsMap;
    updated.remove('prints');
    if (updated['sets'] is Map) (updated['sets'] as Map).remove('es');
    return updated;
  }

  // ─── Firestore catalog upload helpers ───────────────────────────────────

  /// Returns all cards with `_adminModified == true` from the given catalog's chunks.
  /// On failure returns an empty list (best-effort; a failed load must not block the download).
  Future<List<Map<String, dynamic>>> _loadAdminModifiedCards(
      String catalogCollection) async {
    try {
      final snapshot = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .get();
      final result = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        for (final raw in (doc.data()['cards'] as List? ?? [])) {
          final card = Map<String, dynamic>.from(raw as Map);
          if (card['_adminModified'] == true) result.add(card);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<Map<int, Map<String, dynamic>>> _getExistingCardsMap(
      String catalogCollection) async {
    final metaDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final map = <int, Map<String, dynamic>>{};
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final raw in (doc.data()?['cards'] as List? ?? [])) {
        final card = Map<String, dynamic>.from(raw as Map);
        final id = card['id'];
        if (id is int) map[id] = card;
      }
    }
    return map;
  }

  Future<Set<int>> _getExistingCardIds(String catalogCollection) async {
    final metaDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final ids = <int>{};
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final card in (doc.data()?['cards'] as List? ?? [])) {
        final id = (card as Map)['id'];
        if (id != null) ids.add((id as num).toInt());
      }
    }
    return ids;
  }

  Future<Set<String>> _getExistingStringIds(String catalogCollection, String idField) async {
    final metaDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final ids = <String>{};
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final card in (doc.data()?['cards'] as List? ?? [])) {
        final id = (card as Map)[idField];
        if (id != null) ids.add(id.toString());
      }
    }
    return ids;
  }

  Future<({Set<String> groupKeys, int maxId})> _getExistingOnepieceState() async {
    final metaDoc = await _firestore.collection('onepiece_catalog').doc('metadata').get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final keys = <String>{};
    int maxId = 0;
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection('onepiece_catalog')
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final raw in (doc.data()?['cards'] as List? ?? [])) {
        final card = raw as Map;
        final id = card['id'];
        if (id is num && id.toInt() > maxId) maxId = id.toInt();
        final prints = card['prints'] as List?;
        if (prints == null || prints.isEmpty) continue;
        final firstCardSetId = (prints.first as Map)['card_set_id'] as String? ?? '';
        if (firstCardSetId.isEmpty) continue;
        final gk = firstCardSetId.contains('_') ? firstCardSetId.split('_')[0] : firstCardSetId;
        if (gk.isNotEmpty) keys.add(gk);
      }
    }
    return (groupKeys: keys, maxId: maxId);
  }

  /// Uploads [cards] to Firestore in chunks.
  /// If [isIncremental], appends to existing chunks; otherwise deletes all
  /// existing chunks first (full replace).
  Future<void> _uploadCatalogChunks({
    required String catalogCollection,
    required List<Map<String, dynamic>> cards,
    required String adminUid,
    required bool isIncremental,
    required Function(int current, int total) onProgress,
  }) async {
    // Read metadata once — used for both deletion and incremental numbering.
    final metaSnap = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    final existingChunkCount =
        metaSnap.exists ? (metaSnap.data()?['totalChunks'] as int? ?? 0) : 0;

    // Full replace: delete old chunks by constructing their IDs from metadata.
    // This avoids downloading the full chunk documents (~60 MB) just to get refs.
    if (!isIncremental) {
      for (int i = 0; i < existingChunkCount; i++) {
        final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
        try {
          await _firestore
              .collection(catalogCollection)
              .doc('chunks')
              .collection('items')
              .doc(chunkId)
              .delete();
        } catch (_) { // ignore: empty_catches
          // Ignore individual delete failures — the new set() will overwrite anyway
        }
      }
    }

    // For incremental: find where to start numbering
    int startChunkIndex = 0;
    int existingTotal = 0;
    if (isIncremental) {
      startChunkIndex = existingChunkCount;
      existingTotal = metaSnap.data()?['totalCards'] as int? ?? 0;
    }

    // Split into chunks of _chunkSize
    final chunks = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < cards.length; i += _chunkSize) {
      chunks.add(cards.sublist(
          i, (i + _chunkSize < cards.length) ? i + _chunkSize : cards.length));
    }

    // Build the new card index entries from the chunks being uploaded
    final newIndexEntries = <String, String>{};
    for (int i = 0; i < chunks.length; i++) {
      final chunkId =
          'chunk_${(startChunkIndex + i + 1).toString().padLeft(3, '0')}';
      // Retry individual writes with exponential backoff to handle
      // transient deadline-exceeded errors on slow connections
      await _writeWithRetry(
        _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId),
        {'cards': chunks[i]},
      );
      for (final card in chunks[i]) {
        final cardId = card['id'];
        if (cardId != null) newIndexEntries[cardId.toString()] = chunkId;
      }
      onProgress(i + 1, chunks.length);
      // Throttle every 10 chunks to avoid saturating the Firestore write stream
      // (RESOURCE_EXHAUSTED: "Write stream exhausted maximum allowed queued writes")
      if ((i + 1) % 10 == 0) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    // Update card index: for incremental, merge with existing; for full replace, overwrite.
    // Wrapped in try-catch: for large catalogs (e.g. Magic ~30k UUID keys) the index
    // can exceed Firestore's 1 MB document limit — the catalog works fine without it,
    // incremental updates fall back to scanning all chunks via _getExistingStringIds.
    try {
      if (isIncremental) {
        final existingIndex = await _loadCardIndex(catalogCollection);
        existingIndex.addAll(newIndexEntries);
        await _saveCardIndex(catalogCollection, existingIndex);
      } else {
        await _saveCardIndex(catalogCollection, newIndexEntries);
      }
    } catch (_) {}

    // Update metadata — reuse the snapshot already fetched above (no extra read)
    final currentVersion =
        metaSnap.exists ? (metaSnap.data()?['version'] as int? ?? 0) : 0;
    await _writeWithRetry(
      _firestore.collection(catalogCollection).doc('metadata'),
      {
        'totalCards':
            isIncremental ? existingTotal + cards.length : cards.length,
        'totalChunks':
            isIncremental ? startChunkIndex + chunks.length : chunks.length,
        'chunkSize': _chunkSize,
        'lastUpdated': FieldValue.serverTimestamp(),
        'version': currentVersion + 1,
        'updatedBy': adminUid,
      },
    );
  }

  /// Merges [cards] into the existing catalog: cards whose key (api_id for
  /// pokemon, the One Piece print group key for onepiece) already exists are
  /// updated IN PLACE in their current chunk (preserving position/id and
  /// avoiding duplicate entries); cards with a brand-new key are appended as
  /// new chunks via [_uploadCatalogChunks]. Used by incremental CardTrader
  /// sync, where [cards] only contains new/incomplete entries.
  Future<({int newCount, int updatedCount})> _upsertCatalogCards({
    required String catalogCollection,
    required String catalog, // 'pokemon' | 'onepiece' | generic catalogKey
    required List<Map<String, dynamic>> cards,
    required String adminUid,
    required Function(int current, int total) onProgress,
  }) async {
    String keyOf(Map<String, dynamic> card) {
      if (catalog == 'onepiece') {
        final prints = card['prints'] as List?;
        final cardSetId = (prints != null && prints.isNotEmpty)
            ? (prints.first as Map)['card_set_id']?.toString() ?? ''
            : '';
        return cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;
      }
      return card['api_id']?.toString() ?? '';
    }

    final chunkMap = await _downloadChunksMap(catalogCollection, (_, _) {});
    final keyIndex = <String, ({String chunkId, int cardIndex})>{};
    for (final chunkId in chunkMap.keys) {
      final list = chunkMap[chunkId]!;
      for (int i = 0; i < list.length; i++) {
        final k = keyOf(list[i]);
        if (k.isNotEmpty) keyIndex[k] = (chunkId: chunkId, cardIndex: i);
      }
    }

    final newCards = <Map<String, dynamic>>[];
    final affectedChunkIds = <String>{};
    int updatedCount = 0;

    for (final card in cards) {
      final key = keyOf(card);
      if (key.isEmpty) continue;
      final loc = keyIndex[key];
      if (loc == null) {
        newCards.add(card);
        continue;
      }
      final merged = Map<String, dynamic>.from(card);
      if (catalog != 'pokemon' && chunkMap[loc.chunkId]![loc.cardIndex]['id'] != null) {
        // Preserve the existing numeric id — don't reuse the freshly assigned one.
        merged['id'] = chunkMap[loc.chunkId]![loc.cardIndex]['id'];
      }
      chunkMap[loc.chunkId]![loc.cardIndex] = merged;
      affectedChunkIds.add(loc.chunkId);
      updatedCount++;
    }

    final totalSteps = affectedChunkIds.length + (newCards.isEmpty ? 0 : 1);
    int done = 0;
    onProgress(0, totalSteps);
    for (final chunkId in affectedChunkIds) {
      await _writeWithRetry(
        _firestore.collection(catalogCollection).doc('chunks').collection('items').doc(chunkId),
        {'cards': chunkMap[chunkId]!},
      );
      onProgress(++done, totalSteps);
    }

    if (newCards.isNotEmpty) {
      await _uploadCatalogChunks(
        catalogCollection: catalogCollection,
        cards: newCards,
        adminUid: adminUid,
        isIncremental: true,
        onProgress: (cur, tot) => onProgress(done + cur, totalSteps - 1 + tot),
      );
    } else if (affectedChunkIds.isNotEmpty) {
      // Bump version even when only in-place updates happened (no new chunks).
      final metaDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
      final currentVersion = metaDoc.exists ? (metaDoc.data()?['version'] as int? ?? 0) : 0;
      await _writeWithRetry(
        _firestore.collection(catalogCollection).doc('metadata'),
        {
          'lastUpdated': FieldValue.serverTimestamp(),
          'version': currentVersion + 1,
          'updatedBy': adminUid,
        },
      );
    }

    return (newCount: newCards.length, updatedCount: updatedCount);
  }

  /// Writes [data] to [ref] with up to 4 attempts and exponential back-off.
  /// Handles transient deadline-exceeded and resource-exhausted errors.
  Future<void> _writeWithRetry(
    DocumentReference ref,
    Map<String, dynamic> data, {
    int maxAttempts = 4,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await ref.set(data);
        return;
      } catch (e) { // ignore: empty_catches
        if (attempt == maxAttempts - 1) rethrow;
        // Exponential back-off: 2s, 4s, 8s
        await Future.delayed(Duration(seconds: 2 << attempt));
      }
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  // ============================================================
  // OPTCG API — One Piece Catalog Population
  // ============================================================

  static const String _optcgBaseUrl = 'https://www.optcgapi.com/api';

  Future<List<dynamic>> _fetchOptcgEndpoint(String endpoint, {bool optional = false}) async {
    final response = await http
        .get(Uri.parse('$_optcgBaseUrl/$endpoint'))
        .timeout(const Duration(minutes: 3));
    if (response.statusCode == 404 && optional) {
      return [];
    }
    if (response.statusCode != 200) throw Exception('OPTCG API error $endpoint: ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    return [];
  }

  /// Downloads the full One Piece catalog from OPTCG API and uploads to Firestore.
  Future<Map<String, dynamic>> downloadOnepieceCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando carte dai set...', null);
    final setCards = await _fetchOptcgEndpoint('allSetCards/');

    final allRaw = [...setCards];
    onProgress('${allRaw.length} stampe ricevute. Elaborando...', null);

    // Carica catalog esistente per preservare Firebase Storage URLs
    final existingCards = await _getExistingCardsMap('onepiece_catalog').timeout(
      const Duration(seconds: 60),
      onTimeout: () => {},
    );
    final existingImageUrls = <String, String>{};
    for (final entry in existingCards.entries) {
      final prints = entry.value['prints'] as List<dynamic>? ?? [];
      for (final p in prints) {
        final pm = Map<String, dynamic>.from(p as Map);
        final artwork = pm['artwork'] as String?;
        final cardSetId = pm['card_set_id'] as String?;
        if (artwork != null && _isHostedImageUrl(artwork) && cardSetId != null) {
          existingImageUrls[cardSetId] = artwork;
        }
      }
    }

    // Build admin-modified map keyed by groupKey so they survive re-downloads.
    final existingAdminModified = <String, Map<String, dynamic>>{};
    for (final card in existingCards.values) {
      if (card['_adminModified'] != true) continue;
      final prints = card['prints'] as List?;
      if (prints == null || prints.isEmpty) continue;
      final firstCardSetId = (prints.first as Map)['card_set_id'] as String? ?? '';
      final gk = firstCardSetId.contains('_')
          ? firstCardSetId.split('_')[0]
          : firstCardSetId;
      if (gk.isNotEmpty) existingAdminModified[gk] = card;
    }

    // Raggruppa stampe in card base
    final Map<String, Map<String, dynamic>> cardMap = {};
    final Map<String, int> cardIdMap = {};
    int nextId = 1;

    for (final raw in allRaw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final name = (m['card_name'] as String? ?? '').trim();
      final type = (m['card_type'] as String? ?? '').trim();
      final color = (m['card_color'] as String? ?? '').trim();
      final cost = m['card_cost'];
      final power = m['card_power'];
      final life = m['life'];
      final cardSetId = (m['card_set_id'] as String? ?? '').trim();
      if (cardSetId.isEmpty || name.isEmpty) continue;

      // Use the base card_set_id as group key (strip variant suffix like _p1, _alt, etc.)
      // e.g. "OP01-001_p1" → "OP01-001", so alternate arts are grouped as prints.
      // This is more stable than a name+stats tuple which breaks on multi-color/errata cards.
      final groupKey = cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;

      if (!cardIdMap.containsKey(groupKey)) {
        cardIdMap[groupKey] = nextId++;
        cardMap[groupKey] = {
          'id': cardIdMap[groupKey],
          'name': name,
          'card_type': type,
          'color': color,
          'cost': cost is num ? cost.toInt() : int.tryParse(cost?.toString() ?? ''),
          'power': power is num ? power.toInt() : int.tryParse(power?.toString() ?? ''),
          'life': life is num ? life.toInt() : int.tryParse(life?.toString() ?? ''),
          'sub_types': (m['sub_types'] is List)
              ? jsonEncode(m['sub_types'])
              : m['sub_types']?.toString(),
          'counter_amount': m['counter_amount'] is num
              ? (m['counter_amount'] as num).toInt()
              : int.tryParse(m['counter_amount']?.toString() ?? ''),
          'attribute': m['attribute']?.toString(),
          'card_text': m['card_text']?.toString(),
          'image_url': m['card_image']?.toString(),
          'prints': <Map<String, dynamic>>[],
        };
      }

      final existingArtwork = existingImageUrls[cardSetId];
      (cardMap[groupKey]!['prints'] as List<Map<String, dynamic>>).add({
        'card_set_id': cardSetId,
        'set_id': m['set_id']?.toString(),
        'set_name': m['set_name']?.toString(),
        'rarity': m['rarity']?.toString(),
        'inventory_price': _parseDouble(m['inventory_price']),
        'market_price': _parseDouble(m['market_price']),
        // URL provvisorio: verrà sostituito con la Firebase Storage URL nel passaggio successivo.
        // Se esiste già un'URL Storage (catalogo precedente) la preserviamo subito.
        'artwork': existingArtwork ?? m['card_image']?.toString(),
      });
    }

    // Restore admin-modified cards (preserves manual edits across re-downloads).
    if (existingAdminModified.isNotEmpty) {
      for (final gk in existingAdminModified.keys) {
        if (cardMap.containsKey(gk)) cardMap[gk] = existingAdminModified[gk]!;
      }
    }

    final mergedCards = cardMap.values.toList();

    // Protezione anti-wipe: se l'API non ha restituito nulla non sovrascrivere
    // il catalogo esistente (un clear + upload di 0 carte lo cancellerebbe).
    if (mergedCards.isEmpty) {
      throw Exception(
        'Nessuna carta ricevuta dall\'OPTCG API — '
        'catalogo non modificato per sicurezza. '
        'Verifica che l\'API $_optcgBaseUrl sia raggiungibile.',
      );
    }

    // Preserve existing Backblaze URLs at card level from existing prints.
    // New prints keep their raw artwork URL for the separate "Migra Immagini" step.
    for (final card in mergedCards) {
      final prints = card['prints'] as List<Map<String, dynamic>>? ?? [];
      for (final print in prints) {
        final artwork = print['artwork'] as String?;
        if (artwork != null && _isHostedImageUrl(artwork)) {
          card['imageUrl'] = artwork;
          card.remove('image_url');
          break;
        }
      }
    }

    onProgress('${mergedCards.length} carte pronte. Caricando su Firestore...', null);
    await _uploadCatalogChunks(
      catalogCollection: 'onepiece_catalog',
      cards: mergedCards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {
      'totalCards': mergedCards.length,
      'totalPrints': allRaw.length,
    };
  }

  /// Downloads **only new cards** (not already in Firestore) from OPTCG API
  /// and appends them to the existing One Piece catalog, preserving all existing price data.
  Future<Map<String, dynamic>> downloadIncrementalOnepieceCatalog({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando carte dall\'OPTCG API...', null);
    final setCards = await _fetchOptcgEndpoint('allSetCards/');

    onProgress('Verificando carte esistenti su Firestore...', null);
    final existingState = await _getExistingOnepieceState();
    final existingGroupKeys = existingState.groupKeys;
    int nextId = existingState.maxId + 1;

    onProgress('Elaborando carte nuove...', null);

    final Map<String, Map<String, dynamic>> cardMap = {};
    final Map<String, int> cardIdMap = {};

    for (final raw in setCards) {
      final m = Map<String, dynamic>.from(raw as Map);
      final name = (m['card_name'] as String? ?? '').trim();
      final type = (m['card_type'] as String? ?? '').trim();
      final color = (m['card_color'] as String? ?? '').trim();
      final cost = m['card_cost'];
      final power = m['card_power'];
      final life = m['life'];
      final cardSetId = (m['card_set_id'] as String? ?? '').trim();
      if (cardSetId.isEmpty || name.isEmpty) continue;

      final groupKey = cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;

      if (existingGroupKeys.contains(groupKey)) continue;

      if (!cardIdMap.containsKey(groupKey)) {
        cardIdMap[groupKey] = nextId++;
        cardMap[groupKey] = {
          'id': cardIdMap[groupKey],
          'name': name,
          'card_type': type,
          'color': color,
          'cost': cost is num ? cost.toInt() : int.tryParse(cost?.toString() ?? ''),
          'power': power is num ? power.toInt() : int.tryParse(power?.toString() ?? ''),
          'life': life is num ? life.toInt() : int.tryParse(life?.toString() ?? ''),
          'sub_types': (m['sub_types'] is List)
              ? jsonEncode(m['sub_types'])
              : m['sub_types']?.toString(),
          'counter_amount': m['counter_amount'] is num
              ? (m['counter_amount'] as num).toInt()
              : int.tryParse(m['counter_amount']?.toString() ?? ''),
          'attribute': m['attribute']?.toString(),
          'card_text': m['card_text']?.toString(),
          'image_url': m['card_image']?.toString(),
          'prints': <Map<String, dynamic>>[],
        };
      }

      (cardMap[groupKey]!['prints'] as List<Map<String, dynamic>>).add({
        'card_set_id': cardSetId,
        'set_id': m['set_id']?.toString(),
        'set_name': m['set_name']?.toString(),
        'rarity': m['rarity']?.toString(),
        'inventory_price': _parseDouble(m['inventory_price']),
        'market_price': _parseDouble(m['market_price']),
        'artwork': m['card_image']?.toString(),
      });
    }

    if (cardMap.isEmpty) return {'newCards': 0};

    final newCards = cardMap.values.toList();

    // Le immagini NON vengono caricate qui — restano come URL raw dell'OPTCG API.
    // Usare il passo "Migra Immagini" separato per caricarle su Firebase Storage.

    onProgress('Salvando ${newCards.length} carte nuove su Firestore...', null);
    await _uploadCatalogChunks(
      catalogCollection: 'onepiece_catalog',
      cards: newCards,
      adminUid: adminUid,
      isIncremental: true,
      onProgress: (cur, tot) => onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {'newCards': newCards.length};
  }

  /// Migra le immagini One Piece su Firebase Storage aggiornando il campo `artwork` nei prints.
  /// [force] = true salta il controllo sull'URL esistente e ri-verifica ogni file su Storage.
  Future<Map<String, dynamic>> migrateOnepieceImagesToStorage({
    required String adminUid,
    required Function(int current, int total) onProgress,
    bool force = false,
  }) async {
    const catalogCollection = 'onepiece_catalog';
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    final sortedChunkIds = chunkMap.keys.toList()..sort();

    // Raccoglie tutti i print che necessitano migrazione
    final toMigrate = <({
      String chunkId,
      int cardIndex,
      int printIndex,
      int cardId,
      String cardSetId,
      String sourceUrl,
      String? fallbackUrl,
    })>[];

    // Diagnostic counters
    int diagTotalCards = 0;
    int diagNoPrints = 0;
    int diagNoCardSetId = 0;
    int diagSurrogate = 0;
    int diagAlreadyMigrated = 0;

    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        diagTotalCards++;
        final card = cards[i];
        final prints = card['prints'] as List<dynamic>? ?? [];
        if (prints.isEmpty) { diagNoPrints++; continue; }
        for (int j = 0; j < prints.length; j++) {
          final p = Map<String, dynamic>.from(prints[j] as Map);
          final cardSetId = (p['card_set_id'] as String?)?.trim() ?? '';
          if (cardSetId.isEmpty) { diagNoCardSetId++; continue; }

          // Skip surrogate IDs (CT blueprint IDs, pure numeric strings, or anything
          // that doesn't match the OPTCG format: e.g. OP01-001, OP01-EN001, ST01-JP001a).
          if (!RegExp(r'^[A-Z]{2,5}\d{1,2}-([A-Z]{2})?\d{3,4}[a-z]?$').hasMatch(cardSetId)) {
            diagSurrogate++;
            continue;
          }

          final artwork = p['artwork'] as String?;
          final alreadyMigrated = artwork != null && _isHostedImageUrl(artwork);
          if (alreadyMigrated && !force) { diagAlreadyMigrated++; continue; }

          final sourceUrl = (artwork != null && !_isHostedImageUrl(artwork))
              ? artwork
              : 'https://en.onepiece-cardgame.com/images/cardlist/card/$cardSetId.png';

          toMigrate.add((
            chunkId: chunkId,
            cardIndex: i,
            printIndex: j,
            cardId: (card['id'] as num).toInt(),
            cardSetId: cardSetId,
            sourceUrl: sourceUrl,
            fallbackUrl: null,
          ));
        }
      }
    }

    if (toMigrate.isEmpty) {
      final diagMsg = 'cards=$diagTotalCards noPrints=$diagNoPrints '
          'noId=$diagNoCardSetId surrogate=$diagSurrogate '
          'alreadyDone=$diagAlreadyMigrated';
      debugPrint('[OPMigration] Niente da migrare — $diagMsg');
      final metadataDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
      final currentVersion = metadataDoc.exists ? (metadataDoc.data()?['version'] as int? ?? 0) : 0;
      await _firestore.collection(catalogCollection).doc('metadata').set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'version': currentVersion + 1,
        'updatedBy': adminUid,
        'modifiedChunks': [],
      }, SetOptions(merge: true));
      return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0, 'diagMsg': diagMsg};
    }

    int migrated = 0, failed = 0;
    final affectedChunkIds = <String>{};

    for (int i = 0; i < toMigrate.length; i++) {
      final item = toMigrate[i];
      onProgress(i + 1, toMigrate.length);

      try {
        // Prova prima sourceUrl (artwork del print), poi fallbackUrl (image_url della card).
        // _uploadCardImageIfNeeded include User-Agent headers (necessario per OPTCG CDN).
        String? storageUrl;
        final candidates = [item.sourceUrl, if (item.fallbackUrl != null) item.fallbackUrl!];
        for (final url in candidates) {
          storageUrl = await _uploadCardImageIfNeeded('onepiece', item.cardId, url, setCode: item.cardSetId);
          if (storageUrl != null) break;
        }

        if (storageUrl != null) {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          final prints = List<dynamic>.from(card['prints'] as List);
          final print = Map<String, dynamic>.from(prints[item.printIndex] as Map);
          print['artwork'] = storageUrl;
          prints[item.printIndex] = print;
          card['prints'] = prints;
          _setOnepieceCardImageUrl(card, storageUrl);
          chunkMap[item.chunkId]![item.cardIndex] = card;
          affectedChunkIds.add(item.chunkId);
          migrated++;
        } else {
          failed++;
        }
      } catch (_) { // ignore: empty_catches
        failed++;
      }
    }

    for (final chunkId in affectedChunkIds) {
      await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .set({'cards': chunkMap[chunkId]!});
    }

    final metadataDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
    final currentVersion = metadataDoc.exists ? (metadataDoc.data()?['version'] as int? ?? 0) : 0;
    await _firestore.collection(catalogCollection).doc('metadata').set({
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
      'updatedBy': adminUid,
      'modifiedChunks': affectedChunkIds.toList(),
    }, SetOptions(merge: true));

    // Verify a sample of uploaded URLs to confirm they're actually on Backblaze.
    final uploadedUrls = affectedChunkIds
        .expand((id) => chunkMap[id]!)
        .map((c) => (c['prints'] as List?)?.firstOrNull)
        .whereType<Map>()
        .map((p) => p['artwork'] as String?)
        .where((u) => _isHostedImageUrl(u))
        .cast<String>()
        .take(5)
        .toList();
    int verified = 0;
    for (final url in uploadedUrls) {
      if (await BackblazeService.verifyUrl(url)) verified++;
    }

    return {
      'migrated': migrated,
      'failed': failed,
      'chunksUpdated': affectedChunkIds.length,
      'verified': verified,
      'verifiedOf': uploadedUrls.length,
    };
  }

  // ============================================================
  // TCGDex API — Pokémon Catalog Population
  // ============================================================
  //
  // TCGDex is a free, open-source API with no API key required.
  // Base: https://api.tcgdex.net/v2
  // GET /en/sets          → list of all sets
  // GET /en/sets/{setId}  → full set with cards array (id, localId, name, image)
  // Images: {card.image}.png  (e.g. https://assets.tcgdex.net/en/swsh/swsh1/1.png)

  static const String _tcgdexBase = 'https://api.tcgdex.net/v2';
  // SharedPreferences key to persist download progress between app restarts
  static const String _pokemonProgressKey = 'pokemon_download_progress_v2';

  /// Robust GET with retry+backoff for TCGDex list/set endpoints (no API key needed).
  Future<dynamic> _tcgdexGet(String url) async {
    const backoffs = [5, 15, 30];
    const maxAttempts = 4;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          return json.decode(response.body);
        }

        if (attempt == maxAttempts) {
          throw Exception('TCGDex errore permanente: HTTP ${response.statusCode} — $url');
        }
        await Future.delayed(Duration(seconds: backoffs[attempt - 1]));
      } catch (e) { // ignore: empty_catches
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(seconds: backoffs[attempt - 1]));
      }
    }
    throw Exception('TCGDex: tutti i tentativi falliti per $url');
  }

  /// Fast single-attempt GET for card detail endpoints.
  /// Returns null on any failure so the caller can use fallback data immediately.
  Future<dynamic> _tcgdexGetFast(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) return json.decode(response.body);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the list of all Pokémon sets from TCGDex.
  Future<List<Map<String, dynamic>>> _fetchTcgdexSets() async {
    final data = await _tcgdexGet('$_tcgdexBase/en/sets');
    if (data is! List) return [];
    return data.map((s) => Map<String, dynamic>.from(s as Map)).toList();
  }

  /// Fetches full set data (including cards array) for a single set from TCGDex.
  /// Returns a map with 'set' (set info) and 'cards' (list of card briefs).
  Future<({Map<String, dynamic> setInfo, List<Map<String, dynamic>> cards})>
      _fetchTcgdexSetData(String setId) async {
    final data = await _tcgdexGet('$_tcgdexBase/en/sets/$setId');
    if (data is! Map) return (setInfo: <String, dynamic>{}, cards: <Map<String, dynamic>>[]);
    final setInfo = Map<String, dynamic>.from(data);
    final cardList = (setInfo['cards'] as List<dynamic>? ?? [])
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    return (setInfo: setInfo, cards: cardList);
  }

  /// Saves the download progress (completed set IDs + downloaded card count) to SharedPreferences.
  Future<void> _savePokemonProgress(Set<String> completedSetIds, int cardCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pokemonProgressKey, json.encode({
      'completedSets': completedSetIds.toList(),
      'cardCount': cardCount,
    }));
  }

  /// Loads previously saved progress. Returns null if no progress saved.
  Future<({Set<String> completedSetIds, int cardCount})?> _loadPokemonProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pokemonProgressKey);
    if (raw == null) return null;
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return (
        completedSetIds: Set<String>.from(map['completedSets'] as List),
        cardCount: map['cardCount'] as int? ?? 0,
      );
    } catch (_) { // ignore: empty_catches
      return null;
    }
  }

  /// Clears saved progress.
  Future<void> _clearPokemonProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pokemonProgressKey);
  }

  /// Fetches full card data from TCGDex EN endpoint (rarity, hp, types, pricing).
  /// Falls back to the brief [fallback] map if the request fails (e.g. 404 for promos).
  Future<Map<String, dynamic>> _fetchTcgdexCardDetail(
      String setId, String localId, Map<String, dynamic> fallback) async {
    final data = await _tcgdexGetFast('$_tcgdexBase/en/sets/$setId/$localId');
    if (data is Map) return Map<String, dynamic>.from(data);
    return fallback;
  }

  /// Fetches card data for a non-EN language with 2 attempts.
  /// Returns null if the card/set is not available in that language (404 or errors).
  Future<Map<String, dynamic>?> _fetchTcgdexCardDetailLang(
      String lang, String setId, String localId) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await http
            .get(Uri.parse('$_tcgdexBase/$lang/sets/$setId/$localId'))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map) return Map<String, dynamic>.from(data);
          return null;
        }
        if (response.statusCode == 404) return null; // set/card not in this language
        // Transient error (5xx): retry once
        if (attempt == 2) return null;
        await Future.delayed(const Duration(seconds: 3));
      } catch (_) {
        if (attempt == 2) return null;
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    return null;
  }

  /// Fetches full card data for EN + IT + FR + DE + ES + PT sequentially per language
  /// (not all in parallel) to avoid rate-limiting TCGDex.
  /// Language fields (name_it, rarity_it, set_name_it, set_price_it, …) are
  /// merged into the returned map alongside the base EN data.
  Future<Map<String, dynamic>> _fetchTcgdexCardAllLangs(
      String setId, String localId, Map<String, dynamic> fallback) async {
    // EN is always fetched first (required); other languages are best-effort.
    final enCard = await _fetchTcgdexCardDetail(setId, localId, fallback);
    final merged = Map<String, dynamic>.from(enCard);

    // Fetch the 5 non-EN languages in parallel (2 retries each, 15s timeout).
    // Keeping it parallel per-card but with retries reduces total time while
    // being gentler than 30 simultaneous requests (old: 5 cards × 6 langs).
    const otherLangs = ['it', 'fr', 'de', 'es', 'pt'];
    final langResults = await Future.wait(
      otherLangs.map((l) => _fetchTcgdexCardDetailLang(l, setId, localId)),
    );

    for (int i = 0; i < otherLangs.length; i++) {
      final langData = langResults[i];
      if (langData == null) continue;
      final lang = otherLangs[i];
      final name = langData['name']?.toString();
      final rarity = langData['rarity']?.toString();
      final setName = (langData['set'] as Map?)?['name']?.toString();
      final cm = (langData['pricing'] as Map?)?['cardmarket'] as Map?;
      final price = (cm?['avg'] as num?)?.toDouble();
      // Only merge fields that are actually non-null so EN fallback stays clean
      if (name != null)    merged['name_$lang']     = name;
      if (rarity != null)  merged['rarity_$lang']   = rarity;
      if (setName != null) merged['set_name_$lang']  = setName;
      if (price != null)   merged['set_price_$lang'] = price;
    }
    return merged;
  }

  /// Fetches ALL Pokémon cards from TCGDex with full card details (rarity, hp, types,
  /// Cardmarket pricing). Each set requires one request for the card list, then
  /// per-card detail requests fetched in parallel batches of [_detailConcurrency].
  /// Supports resuming an interrupted download via SharedPreferences progress.
  // 2 card × 5 lingue = 10 richieste simultànee — compromesso tra velocità e gentilezza
  static const int _detailConcurrency = 2;

  Future<List<Map<String, dynamic>>> _fetchAllPokemonCards(
      Function(String, double?) onProgress) async {
    onProgress('Recupero lista espansioni da TCGDex...', null);
    final sets = await _fetchTcgdexSets();
    final total = sets.length;
    final allCards = <Map<String, dynamic>>[];

    // Load previous progress (if any)
    final savedProgress = await _loadPokemonProgress();
    final completedSetIds = savedProgress?.completedSetIds ?? <String>{};
    final skippedCount = completedSetIds.length;

    if (skippedCount > 0) {
      onProgress('Riprendo download: $skippedCount/$total set già completati...', skippedCount / total);
    }

    for (int i = 0; i < sets.length; i++) {
      final setId = sets[i]['id'] as String? ?? '';
      final setName = sets[i]['name'] as String? ?? setId;

      if (setId.isEmpty || completedSetIds.contains(setId)) continue;

      onProgress(
        'Set ${i + 1}/$total — $setName (${allCards.length + (savedProgress?.cardCount ?? 0)} carte)...',
        (i + 1) / total,
      );

      // Small pause between sets to be polite to the server
      if (allCards.isNotEmpty) await Future.delayed(const Duration(milliseconds: 200));

      final result = await _fetchTcgdexSetData(setId);
      final serieId = (result.setInfo['serie'] as Map?)?['id']?.toString() ?? '';
      final briefs = result.cards;

      // Fetch full card details for all 6 languages in parallel batches.
      // Each card fires 6 simultaneous requests (EN + IT + FR + DE + ES + PT).
      for (int j = 0; j < briefs.length; j += _detailConcurrency) {
        final batch = briefs.sublist(j, (j + _detailConcurrency).clamp(0, briefs.length));
        final details = await Future.wait(
          batch.map((brief) => _fetchTcgdexCardAllLangs(
            setId, brief['localId']?.toString() ?? '', brief)),
        );
        for (final detail in details) {
          allCards.add(_transformTcgdexCard(detail, result.setInfo, serieId));
        }
      }

      completedSetIds.add(setId);

      // Persist progress after every set so we can resume on failure
      await _savePokemonProgress(
          completedSetIds, allCards.length + (savedProgress?.cardCount ?? 0));
    }
    return allCards;
  }

  /// Transforms a TCGDex full card detail + set info into the Firestore storage format.
  /// Populates: rarity, hp, types, supertype, and Cardmarket EUR pricing.
  Map<String, dynamic> _transformTcgdexCard(
      Map<String, dynamic> card,
      Map<String, dynamic> setInfo,
      String serieId) {
    final localId = card['localId']?.toString() ?? card['id']?.toString() ?? '';
    final setId = setInfo['id']?.toString() ?? '';
    final apiId = card['id']?.toString() ?? '$setId-$localId';

    // TCGDex image URL pattern: {image}/high.webp
    final imageBase = card['image']?.toString();
    final imageUrl = imageBase != null ? '$imageBase/high.webp' : null;

    final setName = setInfo['name']?.toString();
    final serieName = (setInfo['serie'] as Map?)?['name']?.toString();

    // Types: list → comma-separated string (e.g. ["Grass","Colorless"] → "Grass,Colorless")
    final typesList = card['types'] as List?;
    final types = typesList != null && typesList.isNotEmpty
        ? typesList.map((t) => t.toString()).join(',')
        : null;

    // Cardmarket EUR pricing from TCGDex full card endpoint
    final pricing = card['pricing'] as Map?;
    final cm = pricing?['cardmarket'] as Map?;
    final cmAvg = (cm?['avg'] as num?)?.toDouble();

    return {
      'api_id': apiId,
      'name': card['name']?.toString() ?? '',
      'supertype': card['category']?.toString(),
      'subtype': card['suffix']?.toString(),
      'hp': card['hp'] as int?,
      'types': types,
      'rarity': card['rarity']?.toString(),
      'set_id': setId,
      'set_name': setName,
      'set_series': serieName,
      'number': localId,
      // Multilingual card names (Pokémon names are usually identical across languages)
      'name_it': card['name_it']?.toString(),
      'name_fr': card['name_fr']?.toString(),
      'name_de': card['name_de']?.toString(),
      'name_es': card['name_es']?.toString(),
      'name_pt': card['name_pt']?.toString(),
      if (imageUrl != null) 'image_url': imageUrl,
      'sets': {
        'en': [
          {
            'set_code': apiId,
            'set_name': setName,
            'rarity': card['rarity']?.toString(),
            'set_price': cmAvg,
            if (imageUrl != null) 'image_url': imageUrl,
          }
        ],
        if (card['set_name_it'] != null || card['rarity_it'] != null)
          'it': [
            {
              'set_code': apiId,
              'set_name': card['set_name_it'],
              'rarity': card['rarity_it'],
              'set_price': card['set_price_it'],
            }
          ],
        if (card['set_name_fr'] != null || card['rarity_fr'] != null)
          'fr': [
            {
              'set_code': apiId,
              'set_name': card['set_name_fr'],
              'rarity': card['rarity_fr'],
              'set_price': card['set_price_fr'],
            }
          ],
        if (card['set_name_de'] != null || card['rarity_de'] != null)
          'de': [
            {
              'set_code': apiId,
              'set_name': card['set_name_de'],
              'rarity': card['rarity_de'],
              'set_price': card['set_price_de'],
            }
          ],
        if (card['set_name_es'] != null || card['rarity_es'] != null)
          'es': [
            {
              'set_code': apiId,
              'set_name': card['set_name_es'],
              'rarity': card['rarity_es'],
              'set_price': card['set_price_es'],
            }
          ],
        if (card['set_name_pt'] != null || card['rarity_pt'] != null)
          'pt': [
            {
              'set_code': apiId,
              'set_name': card['set_name_pt'],
              'rarity': card['rarity_pt'],
              'set_price': card['set_price_pt'],
            }
          ],
      },
    };
  }

  /// Downloads the **full** Pokémon catalog from TCGDex, uploads every image to
  /// Firebase Storage (compressing to ~80 KB JPEG), then saves metadata to Firestore.
  /// Images already present in Storage are skipped (getDownloadURL check).
  ///
  /// Supports resuming an interrupted download: if a previous run was interrupted
  /// after saving progress, this call will skip already-completed sets and append
  /// the remaining cards to Firestore (incremental upload).
  Future<Map<String, dynamic>> downloadPokemonCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    // Check for saved progress BEFORE clearing it, so we can resume if interrupted.
    final savedProgress = await _loadPokemonProgress();
    final isResuming = savedProgress != null && savedProgress.completedSetIds.isNotEmpty;
    if (!isResuming) {
      // Fresh start — discard any stale state
      await _clearPokemonProgress();
    }

    // 1. Fetch + transform all cards from TCGDex
    var cards = await _fetchAllPokemonCards(onProgress);
    var effectiveResuming = isResuming;

    // If resuming caused ALL sets to be skipped (stale/complete progress with no
    // new cards to fetch), the result is empty — auto-clear and retry fresh.
    if (cards.isEmpty && isResuming) {
      onProgress('Progresso precedente obsoleto — riavvio download da zero...', 0);
      await _clearPokemonProgress();
      effectiveResuming = false;
      cards = await _fetchAllPokemonCards(onProgress);
    }

    if (cards.isEmpty) throw Exception('Nessuna carta ricevuta da TCGDex');

    onProgress('${cards.length} carte ricevute. Preservando URL esistenti...', null);

    // Preserve existing Backblaze URLs for cards already migrated.
    // New cards keep their raw image_url for the separate "Migrate Images" step.
    final existingImageUrls = <String, String>{};
    if (!effectiveResuming) {
      try {
        final existingMap = await _getExistingCardsMap('pokemon_catalog')
            .timeout(const Duration(seconds: 60));
        for (final entry in existingMap.entries) {
          final url = entry.value['imageUrl'] as String?;
          if (_isHostedImageUrl(url)) {
            existingImageUrls[entry.key.toString()] = url!;
          }
        }
      } catch (_) {}
    }

    final processedCards = cards.map((rawCard) {
      final card = Map<String, dynamic>.from(rawCard);
      final apiId = card['api_id'] as String?;
      if (apiId == null) return card;
      final existing = existingImageUrls[apiId];
      if (existing != null) {
        card.remove('image_url');
        card['imageUrl'] = existing;
        final rawSets = card['sets'] as Map<String, dynamic>?;
        if (rawSets != null) {
          final enList = rawSets['en'] as List?;
          if (enList != null && enList.isNotEmpty) {
            final enEntry = Map<String, dynamic>.from(enList[0] as Map)..['image_url'] = existing;
            card['sets'] = {...rawSets, 'en': [enEntry]};
          }
        }
      }
      return card;
    }).toList();

    onProgress('Salvataggio catalogo su Firestore...', null);

    // Preserve admin-modified cards from the existing catalog.
    if (!effectiveResuming) {
      final adminModifiedList = await _loadAdminModifiedCards('pokemon_catalog');
      if (adminModifiedList.isNotEmpty) {
        final adminMap = <String, Map<String, dynamic>>{
          for (final c in adminModifiedList)
            if ((c['api_id'] as String?)?.isNotEmpty == true) c['api_id'] as String: c,
        };
        for (int i = 0; i < processedCards.length; i++) {
          final apiId = processedCards[i]['api_id'] as String?;
          if (apiId != null && adminMap.containsKey(apiId)) {
            processedCards[i] = adminMap[apiId]!;
          }
        }
      }
    }

    // 3. Upload chunks to Firestore.
    // When resuming an interrupted run, append the new cards to the existing catalog
    // (the completed sets are already in Firestore from the previous run).
    await _uploadCatalogChunks(
      catalogCollection: 'pokemon_catalog',
      cards: processedCards,
      adminUid: adminUid,
      isIncremental: effectiveResuming,
      onProgress: (cur, tot) =>
          onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    await _clearPokemonProgress();

    return {'totalCards': processedCards.length};
  }

  /// Downloads **only new cards** (not already in Firestore) from pokemontcg.io
  /// and appends them to the existing Pokémon catalog, preserving all existing price data.
  Future<Map<String, dynamic>> downloadIncrementalPokemonCatalog({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando lista carte da pokemontcg.io...', null);
    final allCards = await _fetchAllPokemonCards(onProgress);

    onProgress('Verificando carte esistenti su Firestore...', null);
    final existingIds = await _getExistingStringIds('pokemon_catalog', 'api_id');

    final newCards = allCards
        .where((c) => !existingIds.contains(c['api_id'] as String? ?? ''))
        .toList();

    if (newCards.isEmpty) return {'newCards': 0};

    onProgress('Caricando immagini per ${newCards.length} carte nuove...', 0);
    final sem = _Semaphore(_uploadConcurrency);
    int imagesOk = 0, imagesFail = 0;
    final processedCards = await Future.wait(newCards.asMap().entries.map((e) async {
      final card = Map<String, dynamic>.from(e.value);
      final apiId = card['api_id'] as String?;
      final sourceUrl = card['image_url'] as String?;
      if (apiId != null && sourceUrl != null && sourceUrl.isNotEmpty) {
        await sem.acquire();
        try {
          final url = await _uploadCardImageIfNeeded('pokemon', apiId, sourceUrl);
          if (url != null) {
            card.remove('image_url');
            card['imageUrl'] = url;
            final rawSets = card['sets'] as Map<String, dynamic>?;
            if (rawSets != null) {
              final enList = rawSets['en'] as List?;
              if (enList != null && enList.isNotEmpty) {
                final enEntry = Map<String, dynamic>.from(enList[0] as Map)..['image_url'] = url;
                card['sets'] = {...rawSets, 'en': [enEntry]};
              }
            }
            imagesOk++;
          } else {
            imagesFail++;
          }
        } finally {
          sem.release();
        }
      }
      return card;
    }));

    onProgress('Salvando ${processedCards.length} carte nuove su Firestore...', null);
    await _uploadCatalogChunks(
      catalogCollection: 'pokemon_catalog',
      cards: processedCards,
      adminUid: adminUid,
      isIncremental: true,
      onProgress: (cur, tot) => onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {'newCards': processedCards.length, 'imagesOk': imagesOk, 'imagesFail': imagesFail};
  }

  /// Migrates Pokémon card images to Firebase Storage,
  /// updating `imageUrl` on the card and `artwork` on each print.
  Future<Map<String, dynamic>> migratePokemonImagesToStorage({
    required String adminUid,
    required Function(int current, int total) onProgress,
    bool force = false,
  }) async {
    const catalogCollection = 'pokemon_catalog';
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    final sortedChunkIds = chunkMap.keys.toList()..sort();

    final toMigrate = <({String chunkId, int cardIndex, String apiId, String sourceUrl})>[];
    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final storageUrl = card['imageUrl'] as String?;
        final apiId = card['api_id'] as String? ?? '';
        if (apiId.isEmpty) continue;
        if (storageUrl != null && _isHostedImageUrl(storageUrl) && !force) continue;

        // Prefer stored CT URL; fall back to pokemontcg.io (reconstructed from api_id).
        // CT download with uploadImages:false stores image_url only when the blueprint
        // has an image — if it's absent we need the API fallback to have something to migrate.
        String? rawSource = (card['image_url'] ?? card['imageUrl']) as String?;
        if (rawSource == null || rawSource.isEmpty || _isHostedImageUrl(rawSource)) {
          // apiId format: 'swsh1-1'  →  set='swsh1', number='1'
          final dash = apiId.lastIndexOf('-');
          if (dash > 0) {
            final setCode = apiId.substring(0, dash);
            final num = apiId.substring(dash + 1);
            rawSource = 'https://images.pokemontcg.io/$setCode/${num}_hires.png';
          }
        }
        if (rawSource == null || rawSource.isEmpty) continue;

        toMigrate.add((
          chunkId: chunkId,
          cardIndex: i,
          apiId: apiId,
          sourceUrl: rawSource,
        ));
      }
    }

    if (toMigrate.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    int migrated = 0, failed = 0;
    final affectedChunkIds = <String>{};

    for (int i = 0; i < toMigrate.length; i++) {
      final item = toMigrate[i];
      onProgress(i + 1, toMigrate.length);
      try {
        final storageUrl = await _uploadCardImageIfNeeded('pokemon', item.apiId, item.sourceUrl);
        if (storageUrl != null) {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          card.remove('image_url');
          card['imageUrl'] = storageUrl;
          // Update image_url in the 'en' set entry (new sets-map format)
          final rawSets = card['sets'] as Map<String, dynamic>?;
          if (rawSets != null) {
            final enList = rawSets['en'] as List?;
            if (enList != null && enList.isNotEmpty) {
              final enEntry = Map<String, dynamic>.from(enList[0] as Map)..['image_url'] = storageUrl;
              card['sets'] = {...rawSets, 'en': [enEntry]};
            }
          } else {
            // Backward compat: old flat prints format
            final prints = (card['prints'] as List<dynamic>?)
                ?.map((p) => Map<String, dynamic>.from(p as Map)..['artwork'] = storageUrl)
                .toList();
            if (prints != null) card['prints'] = prints;
          }
          chunkMap[item.chunkId]![item.cardIndex] = card;
          affectedChunkIds.add(item.chunkId);
          migrated++;
        } else {
          failed++;
        }
      } catch (_) { // ignore: empty_catches
        failed++;
      }
    }

    for (final chunkId in affectedChunkIds) {
      await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .set({'cards': chunkMap[chunkId]!});
    }

    final metadataDoc =
        await _firestore.collection(catalogCollection).doc('metadata').get();
    final currentVersion =
        metadataDoc.exists ? (metadataDoc.data()?['version'] as int? ?? 0) : 0;
    await _firestore.collection(catalogCollection).doc('metadata').set({
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    // Verify a sample of uploaded URLs.
    final uploadedUrls = affectedChunkIds
        .expand((id) => chunkMap[id]!)
        .map((c) => c['imageUrl'] as String?)
        .where((u) => _isHostedImageUrl(u))
        .cast<String>()
        .take(5)
        .toList();
    int verified = 0;
    for (final url in uploadedUrls) {
      if (await BackblazeService.verifyUrl(url)) verified++;
    }

    return {
      'migrated': migrated,
      'failed': failed,
      'chunksUpdated': affectedChunkIds.length,
      'verified': verified,
      'verifiedOf': uploadedUrls.length,
    };
  }

  // ============================================================
  // Dirty serial repair (pre-existing CT blueprint-id leftovers)
  // ============================================================

  /// Scans the existing [catalog] ('pokemon' or 'onepiece') for entries whose
  /// serial is a leftover CT-internal blueprint id (from before the
  /// official-API fallback in [_resolveRealCardSerial] existed) and
  /// re-resolves them via the same fallback, updating `api_id`/`card_set_id`
  /// and image in place. Cards that still can't be resolved are listed in
  /// `unresolvedSample` for manual admin review — they are never deleted or
  /// left with a fake id. Pass [dryRun]: true to preview the report without
  /// writing to Firestore.
  Future<Map<String, dynamic>> repairDirtySerials({
    required String catalog, // 'pokemon' | 'onepiece'
    required String adminUid,
    required Function(int current, int total) onProgress,
    bool dryRun = false,
  }) async {
    if (catalog != 'pokemon' && catalog != 'onepiece') {
      throw Exception('repairDirtySerials: solo pokemon e onepiece');
    }
    final catalogCollection = '${catalog}_catalog';
    final chunkMap = await _downloadChunksMap(catalogCollection, (_, _) {});
    if (chunkMap.isEmpty) {
      return {'repaired': 0, 'unresolved': 0, 'chunksUpdated': 0, 'unresolvedSample': <String>[]};
    }

    final cache = _SerialResolveCache();
    final sortedChunkIds = chunkMap.keys.toList()..sort();

    final toResolve = <({
      String chunkId,
      int cardIndex,
      int? printIndex,
      String nameEn,
      String dirtyCollectorNumber,
      String dirtyFullId,
      String expCode,
      String expName,
    })>[];

    if (catalog == 'pokemon') {
      for (final chunkId in sortedChunkIds) {
        final cards = chunkMap[chunkId]!;
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          final apiId = card['api_id']?.toString() ?? '';
          if (apiId.isEmpty) continue;
          final dash = apiId.lastIndexOf('-');
          final collNumPart = dash > 0 ? apiId.substring(dash + 1) : apiId;
          final expCodePart = dash > 0 ? apiId.substring(0, dash) : '';
          if (!_isSurrogateCtId(collNumPart)) continue; // already a real serial
          final setsEn = (card['sets'] as Map?)?['en'] as List?;
          final setName = (setsEn != null && setsEn.isNotEmpty)
              ? (setsEn.first as Map)['set_name']?.toString()
              : null;
          toResolve.add((
            chunkId: chunkId,
            cardIndex: i,
            printIndex: null,
            nameEn: card['name']?.toString() ?? '',
            dirtyCollectorNumber: collNumPart,
            dirtyFullId: apiId,
            expCode: expCodePart,
            expName: setName ?? expCodePart,
          ));
        }
      }
    } else {
      for (final chunkId in sortedChunkIds) {
        final cards = chunkMap[chunkId]!;
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          final prints = card['prints'] as List?;
          if (prints == null) continue;
          for (int j = 0; j < prints.length; j++) {
            final print = prints[j] as Map;
            final cardSetId = print['card_set_id']?.toString() ?? '';
            if (cardSetId.isEmpty) continue;
            final dash = cardSetId.indexOf('-');
            final collNumPart = dash > 0 ? cardSetId.substring(dash + 1) : cardSetId;
            final expCodePart =
                dash > 0 ? cardSetId.substring(0, dash) : (print['set_id']?.toString() ?? '');
            if (!_isSurrogateCtId(collNumPart)) continue; // already a real serial
            toResolve.add((
              chunkId: chunkId,
              cardIndex: i,
              printIndex: j,
              nameEn: card['name']?.toString() ?? '',
              dirtyCollectorNumber: collNumPart,
              dirtyFullId: cardSetId,
              expCode: expCodePart,
              expName: print['set_name']?.toString() ?? expCodePart,
            ));
          }
        }
      }
    }

    int repaired = 0;
    int unresolved = 0;
    final unresolvedSample = <String>[];
    final affectedChunkIds = <String>{};

    for (int idx = 0; idx < toResolve.length; idx++) {
      final item = toResolve[idx];
      onProgress(idx + 1, toResolve.length);

      final resolved = await _resolveRealCardSerial(
        catalog: catalog,
        nameEn: item.nameEn,
        ctCollectorNumber: item.dirtyCollectorNumber,
        expCode: item.expCode,
        expName: item.expName,
        cache: cache,
      );
      if (resolved == null) {
        unresolved++;
        if (unresolvedSample.length < 30) {
          unresolvedSample.add('${item.expName}: ${item.nameEn} (id sporco: ${item.dirtyFullId})');
        }
        continue;
      }

      if (!dryRun) {
        String? storageUrl;
        if (resolved.imageUrl != null) {
          storageUrl = await _uploadCardImageIfNeeded(catalog, resolved.apiId, resolved.imageUrl!);
        }

        if (catalog == 'pokemon') {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          card['api_id'] = resolved.apiId;
          if (storageUrl != null) card['imageUrl'] = storageUrl;
          final realCollectorNumber = resolved.apiId.contains('-')
              ? resolved.apiId.substring(resolved.apiId.indexOf('-') + 1)
              : resolved.apiId;
          final sets = card['sets'] as Map<String, dynamic>?;
          if (sets != null) {
            final updatedSets = <String, dynamic>{};
            for (final entry in sets.entries) {
              updatedSets[entry.key] = (entry.value as List).map((s) {
                final m = Map<String, dynamic>.from(s as Map);
                m['set_code'] = realCollectorNumber;
                if (storageUrl != null) m['artwork'] = storageUrl;
                return m;
              }).toList();
            }
            card['sets'] = updatedSets;
          }
          chunkMap[item.chunkId]![item.cardIndex] = card;
        } else {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          final prints =
              (card['prints'] as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
          final print = prints[item.printIndex!];
          print['card_set_id'] = resolved.apiId;
          if (storageUrl != null) print['artwork'] = storageUrl;
          prints[item.printIndex!] = print;
          card['prints'] = prints;
          chunkMap[item.chunkId]![item.cardIndex] = card;
        }
        affectedChunkIds.add(item.chunkId);
      }
      repaired++;
    }

    if (!dryRun && affectedChunkIds.isNotEmpty) {
      for (final chunkId in affectedChunkIds) {
        await _writeWithRetry(
          _firestore.collection(catalogCollection).doc('chunks').collection('items').doc(chunkId),
          {'cards': chunkMap[chunkId]!},
        );
      }
      final metaDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
      final currentVersion = metaDoc.exists ? (metaDoc.data()?['version'] as int? ?? 0) : 0;
      await _writeWithRetry(
        _firestore.collection(catalogCollection).doc('metadata'),
        {
          'lastUpdated': FieldValue.serverTimestamp(),
          'version': currentVersion + 1,
          'updatedBy': adminUid,
        },
      );
    }

    return {
      'repaired': dryRun ? 0 : repaired,
      'wouldRepair': dryRun ? repaired : 0,
      'unresolved': unresolved,
      'unresolvedSample': unresolvedSample,
      'chunksUpdated': dryRun ? 0 : affectedChunkIds.length,
      'dryRun': dryRun,
    };
  }

  // ============================================================
  // CardTrader price → Firestore catalog sync
  // ============================================================

  /// Sincronizza i prezzi CardTrader nei chunk Firestore del catalogo,
  /// così TUTTI gli utenti vedono i prezzi aggiornati al prossimo download.
  ///
  /// Legge i prezzi già salvati nella tabella SQLite locale [cardtrader_prices],
  /// scarica i chunk Firestore uno per volta, aggiorna i campi
  /// [set_price] / [market_price] e riscrive solo i chunk effettivamente
  /// modificati. Infine incrementa [version] nei metadati per forzare il
  /// re-download sui client.
  ///
  /// Deve essere chiamato DOPO che i prezzi CT sono stati salvati in SQLite.
  Future<Map<String, dynamic>> syncCatalogPricesToFirestore({
    required String catalog,
    required String adminUid,
    required void Function(String msg, double? progress) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';

    // ── 1. Carica tutti i prezzi CT locali in memoria ─────────────────────────
    onProgress('Caricamento prezzi CT locali…', null);
    final allPrices = await _dbHelper.getAllCardtraderPrices(catalog);

    if (allPrices.isEmpty) {
      throw Exception(
        'Nessun prezzo CT trovato localmente per $catalog. '
        'Esegui prima il sync CardTrader.',
      );
    }

    // Costruisci lookup maps:
    //   priceByNameLang: '$expCode|$nameEnLower|$lang' → prezzo più basso in €
    //   priceByCNLang:   '$expCode|$cnLower|$lang'     → prezzo più basso in €
    final priceByNameLang = <String, double>{};
    final priceByCNLang   = <String, double>{};

    for (final row in allPrices) {
      final priceCents =
          (row['min_price_nm_cents'] as int?) ?? (row['min_price_any_cents'] as int?);
      if (priceCents == null || priceCents <= 0) continue;
      final price = double.parse((priceCents / 100.0).toStringAsFixed(2));

      final expCode = (row['expansion_code'] as String).toLowerCase();
      final nameEn  = (row['card_name_en']   as String).toLowerCase();
      final lang    = (row['language']        as String).toLowerCase();
      final cn      = (row['collector_number'] as String? ?? '').toLowerCase();

      final nameKey = '$expCode|$nameEn|$lang';
      if (price < (priceByNameLang[nameKey] ?? double.infinity)) {
        priceByNameLang[nameKey] = price;
      }
      if (cn.isNotEmpty) {
        final cnKey = '$expCode|$cn|$lang';
        if (price < (priceByCNLang[cnKey] ?? double.infinity)) {
          priceByCNLang[cnKey] = price;
        }
      }
    }

    // ── 2. Legge metadati Firestore ───────────────────────────────────────────
    onProgress('Lettura metadati catalogo Firestore…', null);
    final metadataDoc =
        await _firestore.collection(catalogCollection).doc('metadata').get();
    final totalChunks =
        metadataDoc.exists ? (metadataDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    if (totalChunks == 0) throw Exception('Catalogo vuoto su Firestore');

    int processedChunks = 0;
    int modifiedChunks  = 0;
    int updatedPrices   = 0;
    final modifiedChunkIds = <String>[];

    // ── 3. Itera i chunk, aggiorna prezzi, riscrivi solo quelli modificati ────
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      processedChunks++;
      onProgress(
        'Chunk $processedChunks/$totalChunks'
        '${updatedPrices > 0 ? " ($updatedPrices aggiornati)" : ""}…',
        processedChunks / totalChunks,
      );

      final chunkDoc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();

      if (!chunkDoc.exists) continue;

      final rawCards = chunkDoc.data()?['cards'] as List<dynamic>? ?? [];
      bool chunkModified = false;

      final updatedCards = rawCards.map((raw) {
        final card = Map<String, dynamic>.from(raw as Map);
        bool cardModified = false;

        switch (catalog) {
          // ── Yu-Gi-Oh! ────────────────────────────────────────────────────
          case 'yugioh':
            final nameEn  = (card['name'] as String? ?? '').toLowerCase();
            final rawSets = card['sets'] as Map<dynamic, dynamic>?;
            if (rawSets == null) break;

            final newSets = <String, dynamic>{};
            for (final langEntry in rawSets.entries) {
              final lang   = langEntry.key.toString().toLowerCase();
              // CardTrader usa 'es' per lo spagnolo, il catalogo usa 'sp'
              final ctLang = lang == 'sp' ? 'es' : lang;
              final sets   = (langEntry.value as List)
                  .map((s) => Map<String, dynamic>.from(s as Map))
                  .toList();

              final updatedSets = sets.map((s) {
                final rawCode = (s['set_code'] as String? ?? '').toUpperCase();
                // expansion_code = prefisso prima del primo '-' (es. 'LOB' da 'LOB-EN001')
                final expCode = rawCode.contains('-')
                    ? rawCode.split('-')[0].toLowerCase()
                    : rawCode.toLowerCase();

                // Per YGO ogni stampa ha un CN univoco (es. "LOB-EN001" → "en001")
                // che identifica anche la rarità — usato come lookup primario.
                // Il nome è usato come fallback per blueprint con CN assente.
                final cn = rawCode.contains('-')
                    ? rawCode.split('-').last.toLowerCase()
                    : '';
                double? price = cn.isNotEmpty
                    ? priceByCNLang['$expCode|$cn|$ctLang']
                    : null;
                price ??= priceByNameLang['$expCode|$nameEn|$ctLang'];

                if (price != null) {
                  cardModified = true;
                  updatedPrices++;
                  return {...s, 'set_price': price};
                }
                return s;
              }).toList();

              newSets[langEntry.key.toString()] = updatedSets;
            }
            if (cardModified) {
              card['sets'] = newSets;
              chunkModified = true;
            }

          // ── Pokémon ──────────────────────────────────────────────────────
          case 'pokemon':
            final nameEn = (card['name'] as String? ?? '').toLowerCase();
            // New format: sets map keyed by language
            final rawSetsPok = card['sets'] as Map<dynamic, dynamic>?;
            if (rawSetsPok != null) {
              final newSets = <String, dynamic>{};
              for (final langEntry in rawSetsPok.entries) {
                final lang = langEntry.key.toString().toLowerCase();
                final setsList = (langEntry.value as List)
                    .map((s) => Map<String, dynamic>.from(s as Map))
                    .toList();
                newSets[langEntry.key.toString()] = setsList.map((s) {
                  // set_code for Pokémon is the api_id (e.g. "swsh1-1").
                  // CT expansion_code is the set-level code ("swsh1").
                  // Extract by stripping the last "-NNN" segment.
                  final rawCode = (s['set_code'] as String? ?? '').toLowerCase();
                  final expCode = rawCode.contains('-')
                      ? rawCode.substring(0, rawCode.lastIndexOf('-'))
                      : rawCode;
                  if (expCode.isEmpty) return s;
                  final price = priceByNameLang['$expCode|$nameEn|$lang'];
                  if (price != null) {
                    cardModified = true;
                    updatedPrices++;
                    return {...s, 'set_price': price};
                  }
                  return s;
                }).toList();
              }
              if (cardModified) {
                card['sets'] = newSets;
                chunkModified = true;
              }
            } else {
              // Backward compat: old flat prints format
              final rawPrints = card['prints'] as List<dynamic>?;
              if (rawPrints != null) {
                // BUG #5 fix: aggiunto 'es' per Pokémon spagnolo
                const pokeLangCols = <String, String>{
                  'en': 'set_price', 'it': 'set_price_it', 'fr': 'set_price_fr',
                  'de': 'set_price_de', 'es': 'set_price_es', 'pt': 'set_price_pt',
                };
                final updatedPrintsList = rawPrints.map((raw) {
                  final p = Map<String, dynamic>.from(raw as Map);
                  final expCode = (p['set_code'] as String? ?? '').toLowerCase();
                  if (expCode.isEmpty) return p;
                  bool printModified = false;
                  for (final le in pokeLangCols.entries) {
                    final price = priceByNameLang['$expCode|$nameEn|${le.key}'];
                    if (price != null) { p[le.value] = price; printModified = true; updatedPrices++; }
                  }
                  if (printModified) cardModified = true;
                  return p;
                }).toList();
                if (cardModified) { card['prints'] = updatedPrintsList; chunkModified = true; }
              }
            }

          // ── One Piece ────────────────────────────────────────────────────
          case 'onepiece':
            // Una sola stampa per carta (JP base). Embed prezzi per tutte le lingue
            // nei rispettivi campi: market_price (JA), market_price_en, _fr, _ko, _zh.
            final nameEn = (card['name'] as String? ?? '').toLowerCase();
            final rawPrintsField = card['prints'];
            if (rawPrintsField is! List) break;
            final rawPrints = rawPrintsField;

            const opLangFields = <String, String>{
              'ja': 'market_price',
              'en': 'market_price_en',
              'fr': 'market_price_fr',
              'ko': 'market_price_ko',
              'zh': 'market_price_zh',
            };

            final updatedPrintsList = rawPrints.map((raw) {
              final p       = Map<String, dynamic>.from(raw as Map);
              final expCode = (p['set_id'] as String? ?? '').toLowerCase();
              if (expCode.isEmpty) return p;

              bool printModified = false;
              final updated = Map<String, dynamic>.from(p);

              for (final entry in opLangFields.entries) {
                final lang  = entry.key;
                final field = entry.value;
                double? price = priceByNameLang['$expCode|$nameEn|$lang'];
                if (price != null) {
                  updated[field] = price;
                  printModified = true;
                  updatedPrices++;
                }
              }

              if (printModified) { cardModified = true; return updated; }
              return p;
            }).toList();

            if (cardModified) {
              card['prints'] = updatedPrintsList;
              chunkModified = true;
            }
        }

        return card;
      }).toList();

      if (chunkModified) {
        modifiedChunkIds.add(chunkId);
        modifiedChunks++;
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .set({'cards': updatedCards});
      }
    }

    // ── 4. Aggiorna metadati prezzi senza bumpare 'version' ──────────────────
    // BUG #2 fix: 'version' viene bumped solo dai publish di carte (non di prezzi).
    // Se bumpassimo version qui, checkCatalogUpdates vedrebbe un aggiornamento,
    // leggerebbe 'modifiedChunks' (vuoto o sbagliato), e farebbe un download
    // incrementale con i chunk sbagliati o un redownload full non necessario.
    // I client ricevono i prezzi embedded tramite 'priceModifiedChunks' +
    // 'pricesSyncedAt' letti da getCatalogPriceSyncInfo → _onCatalogPriceUpdate.
    if (modifiedChunks > 0) {
      await _firestore.collection(catalogCollection).doc('metadata').set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
        'pricesSyncedAt': FieldValue.serverTimestamp(),
        'priceModifiedChunks': modifiedChunkIds,
      }, SetOptions(merge: true));
    }

    return {
      'modifiedChunks': modifiedChunks,
      'totalChunks': totalChunks,
      'updatedPrices': updatedPrices,
    };
  }

  // ============================================================
  // CardTrader Catalog Download (Pokemon & One Piece)
  // ============================================================

  /// Downloads the catalog for [catalog] ('pokemon' or 'onepiece') from
  /// CardTrader blueprints API and uploads to Firestore. Real card serials
  /// are resolved with an official-API fallback (never a CT blueprint id —
  /// see [_resolveRealCardSerial]) and images are uploaded to Backblaze
  /// immediately. When [incremental] is true (default), only new or
  /// previously-incomplete cards are fetched/written — existing complete
  /// entries are left untouched. Pass `incremental: false` to force a full
  /// rebuild (also deletes/replaces the entire catalog).
  Future<Map<String, dynamic>> downloadCatalogFromCardtrader({
    required String catalog,
    required String adminUid,
    required void Function(String status, double? progress) onProgress,
    bool uploadImages = true,
    bool incremental = true,
  }) async {
    if (catalog != 'pokemon' && catalog != 'onepiece') {
      throw Exception('downloadCatalogFromCardtrader: solo pokemon e onepiece');
    }

    final ctService = CardtraderService();

    onProgress('Caricamento espansioni da CardTrader…', null);
    final expansions = await ctService.fetchExpansionsForCatalog(catalog);
    if (expansions.isEmpty) {
      throw Exception('Nessuna espansione trovata per $catalog su CardTrader');
    }
    onProgress('${expansions.length} espansioni trovate.', null);

    final List<Map<String, dynamic>> resultCards;
    final int discarded;
    final List<String> discardedSample;
    final int skippedExisting;
    if (catalog == 'pokemon') {
      final result = await _buildPokemonCatalogFromCT(
        expansions: expansions,
        ctService: ctService,
        onProgress: onProgress,
        uploadImages: uploadImages,
        incremental: incremental,
      );
      resultCards = result.cards;
      discarded = result.discarded;
      discardedSample = result.discardedSample;
      skippedExisting = result.skippedExisting;
    } else {
      final result = await _buildOnepieceCatalogFromCT(
        expansions: expansions,
        ctService: ctService,
        onProgress: onProgress,
        uploadImages: uploadImages,
        incremental: incremental,
      );
      resultCards = result.cards;
      discarded = result.discarded;
      discardedSample = result.discardedSample;
      skippedExisting = result.skippedExisting;
    }

    if (resultCards.isEmpty) {
      return {
        'totalCards': 0,
        'newCards': 0,
        'updatedCards': 0,
        'totalExpansions': expansions.length,
        'skippedExisting': skippedExisting,
        'discarded': discarded,
        'discardedSample': discardedSample,
      };
    }

    int newCount;
    int updatedCount;
    if (!incremental) {
      // Full rebuild: preserve admin-modified cards from the existing catalog.
      final adminModifiedList = await _loadAdminModifiedCards('${catalog}_catalog');
      if (adminModifiedList.isNotEmpty) {
        final adminMap = <String, Map<String, dynamic>>{};
        for (final card in adminModifiedList) {
          if (catalog == 'pokemon') {
            final apiId = card['api_id'] as String?;
            if (apiId != null && apiId.isNotEmpty) adminMap[apiId] = card;
          } else {
            final prints = card['prints'] as List?;
            if (prints == null || prints.isEmpty) continue;
            final cardSetId = (prints.first as Map)['card_set_id'] as String? ?? '';
            final gk = cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;
            if (gk.isNotEmpty) adminMap[gk] = card;
          }
        }
        for (int i = 0; i < resultCards.length; i++) {
          final String? key;
          if (catalog == 'pokemon') {
            key = resultCards[i]['api_id'] as String?;
          } else {
            final prints = resultCards[i]['prints'] as List?;
            final cardSetId = prints != null && prints.isNotEmpty
                ? (prints.first as Map)['card_set_id'] as String? ?? ''
                : '';
            key = cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;
          }
          if (key != null && key.isNotEmpty && adminMap.containsKey(key)) {
            resultCards[i] = adminMap[key]!;
          }
        }
      }

      onProgress('Caricamento ${resultCards.length} carte su Firestore…', null);
      await _uploadCatalogChunks(
        catalogCollection: '${catalog}_catalog',
        cards: resultCards,
        adminUid: adminUid,
        isIncremental: false,
        onProgress: (cur, tot) =>
            onProgress('Chunk $cur/$tot caricato', tot > 0 ? cur / tot : null),
      );
      newCount = resultCards.length;
      updatedCount = 0;
    } else {
      onProgress('Aggiornamento ${resultCards.length} carte su Firestore…', null);
      final upsert = await _upsertCatalogCards(
        catalogCollection: '${catalog}_catalog',
        catalog: catalog,
        cards: resultCards,
        adminUid: adminUid,
        onProgress: (cur, tot) =>
            onProgress('Chunk $cur/$tot aggiornato', tot > 0 ? cur / tot : null),
      );
      newCount = upsert.newCount;
      updatedCount = upsert.updatedCount;
    }

    return {
      'totalCards': resultCards.length,
      'newCards': newCount,
      'updatedCards': updatedCount,
      'totalExpansions': expansions.length,
      'skippedExisting': skippedExisting,
      'discarded': discarded,
      'discardedSample': discardedSample,
    };
  }

  /// Returns the set of `"<api_id>|<rarity>"` keys already present in the
  /// Pokémon catalog WITH a hosted (Backblaze) image — used to skip complete
  /// entries during incremental CT sync.
  Future<Set<String>> _getExistingPokemonResolvedKeys() async {
    final metaDoc = await _firestore.collection('pokemon_catalog').doc('metadata').get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final keys = <String>{};
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection('pokemon_catalog')
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final raw in (doc.data()?['cards'] as List? ?? [])) {
        final card = raw as Map;
        final apiId = card['api_id']?.toString() ?? '';
        if (apiId.isEmpty) continue;
        final rarity = card['rarity']?.toString() ?? '';
        if (_isHostedImageUrl(card['imageUrl'] as String?)) keys.add('$apiId|$rarity');
      }
    }
    return keys;
  }

  /// Builds Pokemon catalog cards from CT blueprints.
  /// Output format: Firestore `sets` map (compatible with _normalizePokemonCardForSQLite).
  ///
  /// Never trusts a CT-internal blueprint ID as the card's serial: when CT
  /// doesn't expose a real collector number, falls back to TCGDex (the same
  /// official API used by [downloadIncrementalPokemonCatalog]) via
  /// [_resolveRealCardSerial]. Cards that resolve nowhere are discarded
  /// (reported in `discardedSample`) rather than stored with a fake id.
  /// When [incremental] is true, cards already complete (real serial +
  /// hosted image) in the existing catalog are skipped entirely.
  Future<({
    List<Map<String, dynamic>> cards,
    int discarded,
    List<String> discardedSample,
    int skippedExisting,
  })> _buildPokemonCatalogFromCT({
    required List<Map<String, dynamic>> expansions,
    required CardtraderService ctService,
    required void Function(String, double?) onProgress,
    bool uploadImages = true,
    bool incremental = true,
  }) async {
    final allCards = <Map<String, dynamic>>[];
    final errors = <String>[];
    final discardedSample = <String>[];
    int discarded = 0;
    int skippedEmpty = 0;
    int skippedExisting = 0;
    final cache = _SerialResolveCache();
    final existingResolvedKeys =
        incremental ? await _getExistingPokemonResolvedKeys() : <String>{};

    for (int i = 0; i < expansions.length; i++) {
      final exp = expansions[i];
      final expId = exp['id'] as int;
      final expCode = (exp['code'] as String? ?? '').toLowerCase();
      final expName = exp['name'] as String? ?? expCode;

      onProgress(
        'Pokémon — $expName (${i + 1}/${expansions.length})',
        (i + 1) / expansions.length,
      );

      try {
        final rawBlueprints = await ctService.fetchBlueprintsForExpansion(expId);
        final blueprints = rawBlueprints.where(_isCardBlueprint).toList();
        if (blueprints.isEmpty) { skippedEmpty++; continue; }

        // Helper: extract a field checking top-level first, then fixed_properties
        Map<String, dynamic> bpProps(Map<String, dynamic> bp) =>
            (bp['fixed_properties'] as Map<String, dynamic>?) ?? {};

        String bpLang(Map<String, dynamic> bp) {
          // CT may expose language as top-level 'language' or inside fixed_properties
          final top = bp['language']?.toString() ?? '';
          if (top.isNotEmpty) return CardtraderService.normalizeLang(top);
          final p = bpProps(bp);
          return CardtraderService.normalizeLang(
              (p['pokemon_language'] ?? p['language'])?.toString() ?? 'en');
        }

        String bpRarityFn(Map<String, dynamic> bp, String fallback) {
          final top = bp['rarity']?.toString() ?? '';
          if (top.isNotEmpty) return top;
          final p = bpProps(bp);
          return (p['pokemon_rarity'] ?? p['rarity'])?.toString() ?? fallback;
        }

        // Group blueprints by raw CT collector number — same number = same card across languages.
        // This may still be a surrogate blueprint ID at this point; resolved properly below.
        final byNumber = <String, List<Map<String, dynamic>>>{};
        for (final bp in blueprints) {
          final num = _extractCtCollectorNumber(bp);
          if (num.isEmpty) continue;
          byNumber.putIfAbsent(num, () => []).add(bp);
        }

        for (final entry in byNumber.entries) {
          final ctCollectorNumber = entry.key;
          final langBps = entry.value;

          // EN blueprint as base; fallback to first available
          final enBp = langBps.firstWhere(
            (bp) => bpLang(bp) == 'en',
            orElse: () => langBps.first,
          );

          final nameEn = (enBp['name_en'] as String?)?.trim() ??
              (enBp['name'] as String?)?.trim() ?? '';
          if (nameEn.isEmpty) continue;
          final rarity = bpRarityFn(enBp, '');

          final ctImageUrl = uploadImages ? CardtraderService.extractBlueprintImageUrl(enBp) : null;

          final resolved = await _resolveRealCardSerial(
            catalog: 'pokemon',
            nameEn: nameEn,
            ctCollectorNumber: ctCollectorNumber,
            expCode: expCode,
            expName: expName,
            ctImageUrl: ctImageUrl,
            cache: cache,
          );
          if (resolved == null) {
            discarded++;
            if (discardedSample.length < 20) {
              discardedSample.add('$expName: $nameEn (nessun seriale ufficiale risolvibile)');
            }
            continue;
          }
          final apiId = resolved.apiId;

          if (incremental && existingResolvedKeys.contains('$apiId|$rarity')) {
            skippedExisting++;
            continue;
          }

          String? storageUrl;
          if (resolved.imageUrl != null) {
            storageUrl = await _uploadCardImageIfNeeded('pokemon', apiId, resolved.imageUrl!);
          }

          final realCollectorNumber =
              apiId.contains('-') ? apiId.substring(apiId.indexOf('-') + 1) : apiId;

          // Build sets map: one entry per language
          final setsMap = <String, dynamic>{};
          for (final bp in langBps) {
            final lang = bpLang(bp);
            final bpRarity = bpRarityFn(bp, rarity);
            setsMap[lang] = [
              {
                'set_code': realCollectorNumber,
                'set_name': expName,
                'rarity': bpRarity,
                if (storageUrl != null) 'artwork': storageUrl,
              }
            ];
          }
          setsMap.putIfAbsent('en', () => [
            {
              'set_code': realCollectorNumber,
              'set_name': expName,
              'rarity': rarity,
              if (storageUrl != null) 'artwork': storageUrl,
            }
          ]);

          allCards.add({
            'api_id': apiId,
            'name': nameEn,
            'catalog': 'pokemon',
            'rarity': rarity,
            if (storageUrl != null) 'imageUrl': storageUrl,
            'sets': setsMap,
          });
        }
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        errors.add('$expName: $e');
      }
    }

    if (allCards.isEmpty && skippedExisting == 0) {
      final detail = [
        if (skippedEmpty > 0) '$skippedEmpty/${expansions.length} espansioni con 0 blueprint',
        if (discarded > 0) '$discarded carte scartate (seriale non risolvibile)',
        if (errors.isNotEmpty) 'errori: ${errors.take(3).join(' | ')}',
        if (skippedEmpty == 0 && discarded == 0 && errors.isEmpty) 'tutte le espansioni erano vuote',
      ].join('; ');
      throw Exception('Nessuna carta Pokémon estratta da CT. $detail');
    }
    return (
      cards: allCards,
      discarded: discarded,
      discardedSample: discardedSample,
      skippedExisting: skippedExisting,
    );
  }

  /// Returns the set of `"<groupKey>|<rarity>"` keys already present in the
  /// One Piece catalog WITH a hosted (Backblaze) artwork — used to skip
  /// complete entries during incremental CT sync.
  Future<Set<String>> _getExistingOnepieceResolvedKeys() async {
    final metaDoc = await _firestore.collection('onepiece_catalog').doc('metadata').get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final keys = <String>{};
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection('onepiece_catalog')
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final raw in (doc.data()?['cards'] as List? ?? [])) {
        final card = raw as Map;
        final rarity = card['rarity']?.toString() ?? '';
        for (final p in (card['prints'] as List? ?? [])) {
          final print = p as Map;
          final cardSetId = (print['card_set_id'] as String?)?.trim() ?? '';
          if (cardSetId.isEmpty) continue;
          final gk = cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;
          if (_isHostedImageUrl(print['artwork'] as String?)) keys.add('$gk|$rarity');
        }
      }
    }
    return keys;
  }

  /// Builds One Piece catalog cards from CT blueprints.
  /// Output format: flat `prints` list (compatible with insertOnepieceCards).
  ///
  /// Never trusts a CT-internal blueprint ID as the card's serial: when CT
  /// doesn't expose a real collector number, falls back to OPTCG (the same
  /// official API used by [downloadIncrementalOnepieceCatalog]) via
  /// [_resolveRealCardSerial]. Cards that resolve nowhere are discarded
  /// rather than stored with a fake `card_set_id`. When [incremental] is
  /// true, cards already complete (real serial + hosted artwork) are skipped.
  Future<({
    List<Map<String, dynamic>> cards,
    int discarded,
    List<String> discardedSample,
    int skippedExisting,
  })> _buildOnepieceCatalogFromCT({
    required List<Map<String, dynamic>> expansions,
    required CardtraderService ctService,
    required void Function(String, double?) onProgress,
    bool uploadImages = true,
    bool incremental = true,
  }) async {
    final allCards = <Map<String, dynamic>>[];
    final errors = <String>[];
    final discardedSample = <String>[];
    int discarded = 0;
    int skippedEmpty = 0;
    int skippedNoName = 0;
    int skippedExisting = 0;
    final cache = _SerialResolveCache();

    final existingState = incremental ? await _getExistingOnepieceState() : null;
    int nextId = (existingState?.maxId ?? 0) + 1;
    final existingResolvedKeys =
        incremental ? await _getExistingOnepieceResolvedKeys() : <String>{};

    for (int i = 0; i < expansions.length; i++) {
      final exp = expansions[i];
      final expId = exp['id'] as int;
      final expCodeRaw = (exp['code'] as String? ?? '');
      final expCode = expCodeRaw.toUpperCase(); // e.g. "OP01"
      final expName = exp['name'] as String? ?? expCodeRaw;

      onProgress(
        'One Piece — $expName (${i + 1}/${expansions.length})',
        (i + 1) / expansions.length,
      );

      try {
        final rawBlueprints = await ctService.fetchBlueprintsForExpansion(expId);
        final blueprints = rawBlueprints.where(_isCardBlueprint).toList();
        if (blueprints.isEmpty) { skippedEmpty++; continue; }

        // Helpers: check top-level field first, then fixed_properties
        Map<String, dynamic> bpProps(Map<String, dynamic> bp) =>
            (bp['fixed_properties'] as Map<String, dynamic>?) ?? {};

        String bpLang(Map<String, dynamic> bp) {
          final top = bp['language']?.toString() ?? '';
          if (top.isNotEmpty) return CardtraderService.normalizeLang(top);
          final p = bpProps(bp);
          return CardtraderService.normalizeLang(
              (p['onepiece_language'] ?? p['language'])?.toString() ?? 'ja');
        }

        String bpRarityFn(Map<String, dynamic> bp, String fallback) {
          final top = bp['rarity']?.toString() ?? '';
          if (top.isNotEmpty) return top;
          final p = bpProps(bp);
          return (p['onepiece_rarity'] ?? p['rarity'])?.toString() ?? fallback;
        }

        // Group by name_en — same card printed in different languages
        final byNameEn = <String, List<Map<String, dynamic>>>{};
        for (final bp in blueprints) {
          final nameEn = (bp['name_en'] as String?)?.trim() ??
              (bp['name'] as String?)?.trim() ?? '';
          if (nameEn.isEmpty) { skippedNoName++; continue; }
          byNameEn.putIfAbsent(nameEn, () => []).add(bp);
        }

        for (final entry in byNameEn.entries) {
          final nameEn = entry.key;
          final langBps = entry.value;

          // JA blueprint as base (OP is Japanese-origin); fallback to first
          final jaBp = langBps.firstWhere(
            (bp) => bpLang(bp) == 'ja',
            orElse: () => langBps.first,
          );
          final rarity = bpRarityFn(jaBp, '');
          final jaName = (jaBp['name'] as String?)?.trim() ?? nameEn;

          final ctCollNum = _extractCtCollectorNumber(
            jaBp,
            propKeys: const ['collector_number', 'number', 'onepiece_number'],
          );

          String? ctImageUrl;
          if (uploadImages) {
            ctImageUrl = CardtraderService.extractBlueprintImageUrl(jaBp);
            if (ctImageUrl == null) {
              for (final bp in langBps) {
                ctImageUrl = CardtraderService.extractBlueprintImageUrl(bp);
                if (ctImageUrl != null) break;
              }
            }
          }

          final resolved = await _resolveRealCardSerial(
            catalog: 'onepiece',
            nameEn: nameEn,
            ctCollectorNumber: ctCollNum,
            expCode: expCode,
            expName: expName,
            ctImageUrl: ctImageUrl,
            cache: cache,
          );
          if (resolved == null) {
            discarded++;
            if (discardedSample.length < 20) {
              discardedSample.add('$expName: $nameEn (nessun seriale ufficiale risolvibile)');
            }
            continue;
          }
          final cardSetId = resolved.apiId; // e.g. "OP01-001"
          final groupKey = cardSetId.contains('_') ? cardSetId.split('_')[0] : cardSetId;

          if (incremental && existingResolvedKeys.contains('$groupKey|$rarity')) {
            skippedExisting++;
            continue;
          }

          String? artworkUrl;
          if (resolved.imageUrl != null) {
            artworkUrl = await _uploadCardImageIfNeeded('onepiece', groupKey, resolved.imageUrl!);
          }

          allCards.add({
            'id': nextId++,
            'name': nameEn,
            if (jaName != nameEn) 'name_ja': jaName,
            'catalog': 'onepiece',
            'rarity': rarity,
            'prints': [
              {
                'card_set_id': cardSetId,
                'set_id': expCode,
                'set_name': expName,
                'rarity': rarity,
                if (artworkUrl != null) 'artwork': artworkUrl,
              }
            ],
          });
        }
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        errors.add('$expName: $e');
      }
    }

    if (allCards.isEmpty && skippedExisting == 0) {
      final detail = [
        if (skippedEmpty > 0) '$skippedEmpty/${expansions.length} espansioni con 0 blueprint dopo filtro',
        if (skippedNoName > 0) '$skippedNoName blueprint senza nome',
        if (discarded > 0) '$discarded carte scartate (seriale non risolvibile)',
        if (errors.isNotEmpty) 'errori: ${errors.take(3).join(' | ')}',
        if (skippedEmpty == 0 && skippedNoName == 0 && discarded == 0 && errors.isEmpty)
          'tutte le espansioni erano vuote o filtrate',
      ].join('; ');
      throw Exception('Nessuna carta One Piece estratta da CT. $detail');
    }
    return (
      cards: allCards,
      discarded: discarded,
      discardedSample: discardedSample,
      skippedExisting: skippedExisting,
    );
  }

  // ============================================================
  // Blueprint card-type filter
  // ============================================================

  /// Returns true if [bp] is a single trading card (not a sealed product,
  /// accessory, or other non-card item). Uses name-based matching since CT
  /// blueprints don't expose a reliable category_id at the top level.
  static bool _isCardBlueprint(Map<String, dynamic> bp) {
    final name = ((bp['name_en'] ?? bp['name']) as String? ?? '').toLowerCase();
    const nonCardPatterns = [
      'booster box', 'booster pack', 'booster bundle', 'booster case',
      'booster display',
      'elite trainer box', 'trainer box', 'trainer kit', ' etb',
      'playmat', 'play mat',
      ' sleeves', 'card sleeve', 'deck sleeve', 'sleeve pack',
      'deck box', 'deck case', 'deck shield',
      'blister pack', 'blister box', 'blister bundle',
      'gift box', 'gift set', 'collection box', 'collector chest',
      'theme deck', 'starter deck', 'battle deck', 'league deck',
      'pre-release pack', 'prerelease pack', 'prerelease kit',
      'tin box', 'collection tin', 'promo tin',
      'binder', 'card portfolio',
      'dice set', 'coin set', 'coin bundle',
      'display box',
    ];
    return !nonCardPatterns.any((p) => name.contains(p));
  }

  // ============================================================
  // Collection list
  // ============================================================

  // ============================================================
  // Scryfall — Magic: The Gathering Catalog
  // ============================================================

  /// Scarica l'intero catalogo Magic da Scryfall (bulk data "oracle_cards"),
  /// carica le immagini su Backblaze e pubblica su Firestore come magic_catalog.
  Future<Map<String, dynamic>> downloadMagicCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Recupero URL bulk data da Scryfall...', null);
    final cards = await _fetchAllMagicCards(onProgress);
    if (cards.isEmpty) throw Exception('Nessuna carta ricevuta da Scryfall');

    onProgress('${cards.length} carte ricevute. Preservando URL esistenti...', null);

    // Preserve existing Backblaze URLs; new cards keep image_url for migration step.
    final existingImageUrls = <String, String>{};
    try {
      final existingMap = await _getExistingCardsMap('magic_catalog')
          .timeout(const Duration(seconds: 60));
      for (final entry in existingMap.entries) {
        final url = entry.value['imageUrl'] as String?;
        if (_isHostedImageUrl(url)) {
          existingImageUrls[entry.key.toString()] = url!;
        }
      }
    } catch (_) {}

    var processedCards = cards.map((rawCard) {
      final card = Map<String, dynamic>.from(rawCard);
      final apiId = card['api_id'] as String?;
      if (apiId == null) return card;
      final existing = existingImageUrls[apiId];
      if (existing != null) {
        card.remove('image_url');
        card['imageUrl'] = existing;
      }
      return card;
    }).toList();

    // Preserve admin-modified cards from the existing catalog.
    final adminModifiedList = await _loadAdminModifiedCards('magic_catalog');
    if (adminModifiedList.isNotEmpty) {
      final adminMap = <String, Map<String, dynamic>>{
        for (final c in adminModifiedList)
          if ((c['api_id'] as String?)?.isNotEmpty == true) c['api_id'] as String: c,
      };
      processedCards = [
        for (final card in processedCards)
          adminMap[card['api_id'] as String? ?? ''] ?? card,
      ];
    }

    onProgress('Salvando ${processedCards.length} carte su Firestore...', null);
    await _uploadCatalogChunks(
      catalogCollection: 'magic_catalog',
      cards: processedCards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) => onProgress('Chunk $cur/$tot caricato', tot > 0 ? cur / tot : null),
    );

    return {'totalCards': processedCards.length};
  }

  /// Scarica solo le carte nuove (non già presenti) e le aggiunge al catalogo Magic.
  Future<Map<String, dynamic>> downloadIncrementalMagicCatalog({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando lista carte da Scryfall...', null);
    final allCards = await _fetchAllMagicCards(onProgress);

    onProgress('Verificando carte esistenti su Firestore...', null);
    final existingIds = await _getExistingStringIds('magic_catalog', 'api_id');
    final newCards = allCards
        .where((c) => !existingIds.contains(c['api_id'] as String? ?? ''))
        .toList();

    if (newCards.isEmpty) return {'newCards': 0};

    onProgress('Caricando immagini per ${newCards.length} carte nuove...', 0);
    final sem = _Semaphore(_uploadConcurrency);
    int imagesOk = 0, imagesFail = 0;
    final processedCards = await Future.wait(newCards.asMap().entries.map((e) async {
      final card = Map<String, dynamic>.from(e.value);
      final apiId = card['api_id'] as String?;
      final sourceUrl = card['image_url'] as String?;
      if (apiId != null && sourceUrl != null && sourceUrl.isNotEmpty) {
        await sem.acquire();
        try {
          final url = await _uploadCardImageIfNeeded('magic', apiId, sourceUrl);
          if (url != null) {
            card.remove('image_url');
            card['imageUrl'] = url;
            final rawSets = card['sets'] as Map<String, dynamic>?;
            if (rawSets != null) {
              final enList = rawSets['en'] as List?;
              if (enList != null && enList.isNotEmpty) {
                final enEntry = Map<String, dynamic>.from(enList[0] as Map)..['image_url'] = url;
                card['sets'] = {...rawSets, 'en': [enEntry]};
              }
            }
            imagesOk++;
          } else {
            imagesFail++;
          }
        } finally {
          sem.release();
        }
      }
      return card;
    }));

    onProgress('Salvando ${processedCards.length} carte nuove su Firestore...', null);
    await _uploadCatalogChunks(
      catalogCollection: 'magic_catalog',
      cards: processedCards,
      adminUid: adminUid,
      isIncremental: true,
      onProgress: (cur, tot) => onProgress('Chunk $cur/$tot caricato', tot > 0 ? cur / tot : null),
    );

    return {'newCards': processedCards.length, 'imagesOk': imagesOk, 'imagesFail': imagesFail};
  }

  /// Migrates Magic card images to Backblaze,
  /// updating `imageUrl` on the card and `image_url` in the sets['en'] entry.
  Future<Map<String, dynamic>> migrateMagicImagesToStorage({
    required String adminUid,
    required Function(int current, int total) onProgress,
    bool force = false,
  }) async {
    const catalogCollection = 'magic_catalog';
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    final sortedChunkIds = chunkMap.keys.toList()..sort();
    final toMigrate = <({String chunkId, int cardIndex, String apiId, String sourceUrl})>[];

    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final imageUrl = card['imageUrl'] as String?;
        final apiId = card['api_id'] as String? ?? '';
        if (apiId.isEmpty) continue;
        if (imageUrl != null && _isHostedImageUrl(imageUrl) && !force) continue;

        final rawSource = card['image_url'] as String?;
        if (rawSource == null || rawSource.isEmpty) continue;

        toMigrate.add((
          chunkId: chunkId,
          cardIndex: i,
          apiId: apiId,
          sourceUrl: rawSource,
        ));
      }
    }

    if (toMigrate.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    int migrated = 0, failed = 0;
    final affectedChunkIds = <String>{};

    for (int i = 0; i < toMigrate.length; i++) {
      final item = toMigrate[i];
      onProgress(i + 1, toMigrate.length);
      try {
        final storageUrl = await _uploadCardImageIfNeeded('magic', item.apiId, item.sourceUrl);
        if (storageUrl != null) {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          card.remove('image_url');
          card['imageUrl'] = storageUrl;
          final rawSets = card['sets'] as Map<String, dynamic>?;
          if (rawSets != null) {
            final enList = rawSets['en'] as List?;
            if (enList != null && enList.isNotEmpty) {
              final enEntry = Map<String, dynamic>.from(enList[0] as Map)..['image_url'] = storageUrl;
              card['sets'] = {...rawSets, 'en': [enEntry]};
            }
          }
          chunkMap[item.chunkId]![item.cardIndex] = card;
          affectedChunkIds.add(item.chunkId);
          migrated++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    for (final chunkId in affectedChunkIds) {
      await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .set({'cards': chunkMap[chunkId]!});
    }

    final metadataDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
    final currentVersion = metadataDoc.exists ? (metadataDoc.data()?['version'] as int? ?? 0) : 0;
    await _firestore.collection(catalogCollection).doc('metadata').set({
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    return {
      'migrated': migrated,
      'failed': failed,
      'chunksUpdated': affectedChunkIds.length,
    };
  }

  // ============================================================
  // Migrazione immagini generica (Digimon, Lorcana, FAB, Vanguard, …)
  // ============================================================

  /// Migra le immagini di qualsiasi catalogo v36 su Backblaze B2.
  /// Legge ogni chunk Firestore, carica l'immagine da `imageUrl`/`image_url`
  /// se non è già su storage hosted, poi aggiorna il chunk.
  Future<Map<String, dynamic>> migrateGenericCatalogImages({
    required String catalogKey,
    required String adminUid,
    required void Function(int current, int total) onProgress,
    bool force = false,
  }) async {
    final catalogCollection = '${catalogKey}_catalog';
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    final sortedChunkIds = chunkMap.keys.toList()..sort();
    final toMigrate = <({String chunkId, int cardIndex, String cardId, String sourceUrl})>[];

    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final hosted = card['imageUrl'] as String?;
        if (hosted != null && _isHostedImageUrl(hosted) && !force) continue;

        // Cerca l'URL sorgente (può essere imageUrl non-hosted o image_url raw)
        final source = (hosted != null && !_isHostedImageUrl(hosted))
            ? hosted
            : (card['image_url'] as String? ?? card['artwork'] as String?);
        if (source == null || source.isEmpty) continue;

        final cardId = card['api_id']?.toString() ?? card['id']?.toString() ?? '';
        if (cardId.isEmpty) continue;

        toMigrate.add((
          chunkId: chunkId,
          cardIndex: i,
          cardId: cardId,
          sourceUrl: source,
        ));
      }
    }

    if (toMigrate.isEmpty) {
      return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};
    }

    int migrated = 0, failed = 0;
    final affectedChunkIds = <String>{};

    for (int i = 0; i < toMigrate.length; i++) {
      final item = toMigrate[i];
      onProgress(i + 1, toMigrate.length);
      try {
        final b2Url = await _uploadCardImageIfNeeded(catalogKey, item.cardId, item.sourceUrl);
        if (b2Url != null) {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          card['imageUrl'] = b2Url;
          card.remove('image_url');
          chunkMap[item.chunkId]![item.cardIndex] = card;
          affectedChunkIds.add(item.chunkId);
          migrated++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    for (final chunkId in affectedChunkIds) {
      await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .set({'cards': chunkMap[chunkId]!});
    }

    if (affectedChunkIds.isNotEmpty) {
      final metaDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
      final ver = metaDoc.exists ? (metaDoc.data()?['version'] as int? ?? 0) : 0;
      await _firestore.collection(catalogCollection).doc('metadata').set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'version': ver + 1,
        'updatedBy': adminUid,
      }, SetOptions(merge: true));
    }

    return {
      'migrated': migrated,
      'failed': failed,
      'chunksUpdated': affectedChunkIds.length,
    };
  }

  /// Scarica le carte Oracle da Scryfall bulk data e le trasforma nel formato Firestore.
  Future<List<Map<String, dynamic>>> _fetchAllMagicCards(
    Function(String, double?) onProgress,
  ) async {
    const scryfallHeaders = {
      'Accept': 'application/json',
      'User-Agent': 'DeckMaster/1.0 (g.favara.dev@gmail.com)',
    };

    // 1. Recupera la lista di bulk data disponibili
    onProgress('Recupero indice bulk data Scryfall...', null);
    final bulkResponse = await http
        .get(Uri.parse('https://api.scryfall.com/bulk-data'), headers: scryfallHeaders)
        .timeout(const Duration(seconds: 30));
    if (bulkResponse.statusCode != 200) {
      throw Exception('Scryfall bulk-data HTTP ${bulkResponse.statusCode}');
    }
    final bulkData = jsonDecode(bulkResponse.body) as Map<String, dynamic>;
    final entries = (bulkData['data'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final oracleEntry = entries.firstWhere(
      (e) => e['type'] == 'oracle_cards',
      orElse: () => throw Exception('Bulk data oracle_cards non trovato'),
    );
    final downloadUri = oracleEntry['download_uri'] as String;

    // 2. Scarica il file JSON bulk
    onProgress('Scaricando bulk data (~100 MB)...', null);
    final dataResponse = await http
        .get(Uri.parse(downloadUri), headers: scryfallHeaders)
        .timeout(const Duration(minutes: 10));
    if (dataResponse.statusCode != 200) {
      throw Exception('Download bulk data HTTP ${dataResponse.statusCode}');
    }

    // 3. Decodifica e trasforma
    onProgress('Elaborando carte...', null);
    final rawList = jsonDecode(dataResponse.body) as List<dynamic>;
    final cards = <Map<String, dynamic>>[];

    for (int i = 0; i < rawList.length; i++) {
      final raw = rawList[i] as Map<String, dynamic>;

      // Salta carte non in inglese o token/memorabilia
      final layout = raw['layout'] as String? ?? '';
      if (layout == 'token' || layout == 'emblem' || layout == 'art_series') continue;
      if ((raw['lang'] as String? ?? 'en') != 'en') continue;

      // Immagine (gestisce anche double-faced cards)
      String? imageUrl;
      final imageUris = raw['image_uris'] as Map<String, dynamic>?;
      if (imageUris != null) {
        imageUrl = imageUris['normal'] as String?;
      } else {
        final faces = raw['card_faces'] as List<dynamic>?;
        if (faces != null && faces.isNotEmpty) {
          imageUrl = ((faces[0] as Map<String, dynamic>)['image_uris']
              as Map<String, dynamic>?)?['normal'] as String?;
        }
      }

      // Colori come stringa CSV
      final colorsRaw = raw['colors'] as List<dynamic>? ?? raw['color_identity'] as List<dynamic>? ?? [];
      final colors = colorsRaw.join(',');

      // Prezzo EUR
      final prices = raw['prices'] as Map<String, dynamic>?;
      final priceEur = double.tryParse(prices?['eur']?.toString() ?? '');

      cards.add({
        'id': raw['id'],
        'api_id': raw['id'],
        'name': raw['name'],
        'type': raw['type_line'],
        'mana_cost': raw['mana_cost'],
        'cmc': (raw['cmc'] as num?)?.toDouble(),
        'oracle_text': raw['oracle_text'],
        'power': raw['power'],
        'toughness': raw['toughness'],
        'colors': colors.isEmpty ? null : colors,
        'rarity': raw['rarity'],
        'set_code': raw['set'],
        'set_name': raw['set_name'],
        'collector_number': raw['collector_number'],
        'image_url': imageUrl,
        'price_eur': priceEur,
        'catalog': 'magic',
      });

      if (i % 5000 == 0) {
        onProgress('Elaborando carta ${i + 1}/${rawList.length}...', (i + 1) / rawList.length);
      }
    }

    return cards;
  }

  // ============================================================
  // Digimon — digimoncard.io
  // ============================================================

  // API ha rimosso .php e il parametro series=all → usare series=Digimon+Card+Game
  static const String _digimonApiUrl = 'https://digimoncard.io/api-public/search';

  Future<Map<String, dynamic>> downloadDigimonCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando catalogo Digimon…', null);

    final response = await http
        .get(Uri.parse('$_digimonApiUrl?sort=name&series=Digimon+Card+Game'))
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception('Digimon API error: HTTP ${response.statusCode}\n${response.body}');
    }

    final raw = jsonDecode(response.body);
    if (raw is! List) {
      // L'API potrebbe restituire {"error":"..."} in caso di parametri errati
      final errMsg = raw is Map ? raw['error']?.toString() : raw.runtimeType.toString();
      throw Exception('Risposta Digimon API non valida: $errMsg');
    }

    onProgress('${raw.length} stampe ricevute. Elaborando…', null);

    final cards = <Map<String, dynamic>>[];
    final seen = <String>{};  // dedup set O(1) instead of O(n²)
    int nextId = 1;

    for (final item in raw.cast<Map<String, dynamic>>()) {
      // New API (2025): uses 'id' field (e.g. "BT5-103"). Old API used 'cardnumber'.
      final apiId = (item['id'] as String? ?? item['cardnumber'] as String? ?? '').trim();
      final name = (item['name'] as String? ?? '').trim();
      if (apiId.isEmpty || name.isEmpty) continue;

      // Deduplicate by api_id (same card may appear multiple times for different prints)
      if (!seen.add(apiId)) continue;

      // Set code: extract prefix before the last dash+digits ("BT5-103" → "BT5")
      final setCode = apiId.contains('-') ? apiId.split('-').first : null;

      // set_name is an array in the new API; fall back to first entry
      final setNameRaw = item['set_name'];
      final setName = setNameRaw is List && setNameRaw.isNotEmpty
          ? setNameRaw.first?.toString()
          : setNameRaw?.toString();

      cards.add({
        'id': nextId++,
        'api_id': apiId,
        'name': name,
        'card_type': item['type']?.toString(),
        'subtype': item['digi_type']?.toString() ?? item['attribute']?.toString(),
        'rarity': item['rarity']?.toString(),
        'cost': item['level']?.toString(),
        'power': item['dp']?.toString(),
        'defense': item['play_cost']?.toString(),
        'effect': _combineDigimonEffect(
          item['main_effect']?.toString() ?? item['effect']?.toString(),
          item['source_effect']?.toString() ?? item['evolution_effect']?.toString(),
        ),
        'set_code': setCode,
        'set_name': setName,
      });
    }

    if (cards.isEmpty) throw Exception('Nessuna carta Digimon trovata. Verifica i parametri API.');

    onProgress('${cards.length} carte Digimon. Caricando su Firestore…', null);
    await _uploadCatalogChunks(
      catalogCollection: 'digimon_catalog',
      cards: cards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Chunk $cur di $tot…', cur / tot),
    );

    return {'totalCards': cards.length};
  }

  static String? _combineDigimonEffect(String? effect, String? evoEffect) {
    final parts = [
      if (effect != null && effect.isNotEmpty) effect,
      if (evoEffect != null && evoEffect.isNotEmpty) '[Evo] $evoEffect',
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  // ============================================================
  // Disney Lorcana — lorcana-api.com
  // ============================================================

  static const String _lorcanaApiUrl = 'https://api.lorcana-api.com/cards/all';

  Future<Map<String, dynamic>> downloadLorcanaCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando carte Lorcana (EN)…', null);
    final enCards = await _fetchLorcanaCards('');
    if (enCards.isEmpty) throw Exception('Nessuna carta Lorcana trovata (EN)');

    onProgress('${enCards.length} carte EN. Scaricando IT…', null);
    final itCards = await _fetchLorcanaCards('Italian');
    onProgress('Scaricando FR…', null);
    final frCards = await _fetchLorcanaCards('French');
    onProgress('Scaricando DE…', null);
    final deCards = await _fetchLorcanaCards('German');

    // Build lookup maps keyed by Slug (unique per card print)
    Map<String, Map<String, dynamic>> buildLangMap(List<dynamic> list) {
      final m = <String, Map<String, dynamic>>{};
      for (final c in list.cast<Map<String, dynamic>>()) {
        final slug = c['Slug'] as String? ?? c['Name']?.toString() ?? '';
        if (slug.isNotEmpty) m[slug] = c;
      }
      return m;
    }

    final itMap = buildLangMap(itCards);
    final frMap = buildLangMap(frCards);
    final deMap = buildLangMap(deCards);

    onProgress('Costruendo catalogo…', null);
    final cards = <Map<String, dynamic>>[];
    int nextId = 1;

    for (final en in enCards.cast<Map<String, dynamic>>()) {
      final slug = en['Slug'] as String? ?? '';
      final name = en['Name'] as String? ?? '';
      if (name.isEmpty) continue;

      // api_id: "SetNum-CardNum" e.g. "1-001"
      final setNum = en['Set_Num']?.toString() ?? '';
      final cardNum = en['Card_Num']?.toString() ?? en['Number']?.toString() ?? '';
      final apiId = setNum.isNotEmpty && cardNum.isNotEmpty
          ? '$setNum-$cardNum'
          : (slug.isNotEmpty ? slug : name);

      final it = itMap[slug] ?? {};
      final fr = frMap[slug] ?? {};
      final de = deMap[slug] ?? {};

      cards.add({
        'id': nextId++,
        'api_id': apiId,
        'name': name,
        'card_type': en['Type']?.toString(),
        'subtype': en['Classifications']?.toString(),
        'rarity': en['Rarity']?.toString(),
        'cost': en['Cost']?.toString(),
        'power': en['Strength']?.toString(),
        'defense': en['Willpower']?.toString(),
        'effect': en['Body_Text']?.toString(),
        'set_code': setNum.isNotEmpty ? setNum : null,
        'set_name': en['Set_Name']?.toString(),
        'name_it': it['Name']?.toString(),
        'effect_it': it['Body_Text']?.toString(),
        'name_fr': fr['Name']?.toString(),
        'effect_fr': fr['Body_Text']?.toString(),
        'name_de': de['Name']?.toString(),
        'effect_de': de['Body_Text']?.toString(),
      });
    }

    if (cards.isEmpty) throw Exception('Nessuna carta Lorcana processata');

    onProgress('${cards.length} carte Lorcana. Caricando su Firestore…', null);
    await _uploadCatalogChunks(
      catalogCollection: 'lorcana_catalog',
      cards: cards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Chunk $cur di $tot…', cur / tot),
    );

    return {'totalCards': cards.length};
  }

  Future<List<dynamic>> _fetchLorcanaCards(String language) async {
    final uri = language.isEmpty
        ? Uri.parse(_lorcanaApiUrl)
        : Uri.parse('$_lorcanaApiUrl?language=$language');
    final response = await http
        .get(uri, headers: {'User-Agent': 'DeckMasterApp/1.0'})
        .timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) return [];
    final raw = jsonDecode(response.body);
    return raw is List ? raw : [];
  }

  // ============================================================
  // Flesh and Blood — fabdb.net
  // ============================================================

  static const String _fabApiUrl = 'https://api.fabdb.net';

  Future<Map<String, dynamic>> downloadFabCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    onProgress('Scaricando catalogo Flesh and Blood…', null);

    final allRaw = <Map<String, dynamic>>[];
    int page = 1;
    int? lastPage;

    do {
      final uri = Uri.parse('$_fabApiUrl/cards?per_page=250&page=$page');
      final response = await http
          .get(uri, headers: {'Accept': 'application/json', 'User-Agent': 'DeckMasterApp/1.0'})
          .timeout(const Duration(minutes: 2));

      if (response.statusCode != 200) {
        throw Exception('FAB API error: HTTP ${response.statusCode} page $page');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      allRaw.addAll(data.cast<Map<String, dynamic>>());

      final meta = body['meta'] as Map<String, dynamic>?;
      lastPage ??= (meta?['last_page'] as int?) ?? (meta?['total_pages'] as int?) ?? page;
      onProgress(
        'FAB: pagina $page/$lastPage (${allRaw.length} carte)…',
        page / lastPage,
      );
      page++;
    } while (page <= lastPage);

    if (allRaw.isEmpty) throw Exception('Nessuna carta FAB trovata');

    onProgress('${allRaw.length} carte FAB. Elaborando…', null);
    final cards = <Map<String, dynamic>>[];
    int nextId = 1;

    for (final raw in allRaw) {
      final apiId = (raw['identifier'] as String? ?? '').trim();
      final name = (raw['name'] as String? ?? '').trim();
      if (apiId.isEmpty || name.isEmpty) continue;

      // Extract set info from printings if available
      String? setCode, setName;
      final printings = raw['printings'] as List<dynamic>?;
      if (printings != null && printings.isNotEmpty) {
        final firstPrint = printings.first as Map<String, dynamic>;
        final setMap = firstPrint['set'] as Map<String, dynamic>?;
        setCode = setMap?['identifier'] as String?;
        setName = setMap?['name'] as String?;
      }
      setCode ??= raw['set_id'] as String?;

      cards.add({
        'id': nextId++,
        'api_id': apiId,
        'name': name,
        'card_type': raw['type_text']?.toString(),
        'subtype': raw['classes']?.toString(),
        'rarity': raw['rarity']?.toString(),
        'cost': raw['pitch']?.toString(),
        'power': raw['power']?.toString(),
        'defense': raw['defense']?.toString(),
        'effect': raw['body']?.toString(),
        'set_code': setCode,
        'set_name': setName ?? raw['set_name']?.toString(),
      });
    }

    if (cards.isEmpty) throw Exception('Nessuna carta FAB processata');

    onProgress('${cards.length} carte FAB. Caricando su Firestore…', null);
    await _uploadCatalogChunks(
      catalogCollection: 'flesh-and-blood_catalog',
      cards: cards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Chunk $cur di $tot…', cur / tot),
    );

    return {'totalCards': cards.length};
  }

  // ============================================================
  // CardTrader generic — per collezioni senza API dedicata
  // (Vanguard, Dragon Ball Super, Star Wars, Riftbound, Gundam, Union Arena)
  // ============================================================

  /// Catalog key → CT game name partial match string
  static const _ctGameNames = <String, String>{
    'vanguard':          'Cardfight!! Vanguard',
    'dragon-ball-super': 'Dragon Ball Super',
    'star-wars':         'Star Wars',
    'riftbound':         'Riftbound',
    'gundam':            'Gundam',
    'union-arena':       'Union Arena',
  };

  /// Returns the set of `api_id` keys already present in [catalogCollection]
  /// WITH a hosted (Backblaze) image — used to skip complete entries during
  /// incremental generic CT sync.
  Future<Set<String>> _getExistingGenericResolvedKeys(String catalogCollection) async {
    final metaDoc = await _firestore.collection(catalogCollection).doc('metadata').get();
    final totalChunks = metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    final keys = <String>{};
    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      for (final raw in (doc.data()?['cards'] as List? ?? [])) {
        final card = raw as Map;
        final apiId = card['api_id']?.toString() ?? '';
        if (apiId.isNotEmpty && _isHostedImageUrl(card['imageUrl'] as String?)) keys.add(apiId);
      }
    }
    return keys;
  }

  /// Downloads the catalog for a generic CT-only game (no dedicated official
  /// API integrated — Vanguard, Dragon Ball Super, Star Wars, etc.).
  ///
  /// Only stores the REAL collector number CT exposes for a card (top-level
  /// or `fixed_properties`, via [_extractCtCollectorNumber]); cards where CT
  /// only provides its internal blueprint id are discarded (no fallback
  /// official API exists for these games) and reported in `discardedSample`.
  /// Images are uploaded to Backblaze immediately. When [incremental] is
  /// true (default), cards already complete (real number + hosted image)
  /// are skipped and existing entries are updated in place rather than
  /// duplicated.
  Future<Map<String, dynamic>> downloadCardtraderGenericCatalog({
    required String catalogKey,
    required String adminUid,
    required Function(String status, double? progress) onProgress,
    bool uploadImages = true,
    bool incremental = true,
  }) async {
    final ctService = CardtraderService();
    final catalogCollection = '${catalogKey}_catalog';

    // Use hardcoded game IDs first (reliable), fall back to name search only if missing
    int? gameId = CardtraderService.gameIds[catalogKey];
    final ctGameName = _ctGameNames[catalogKey] ?? catalogKey;

    if (gameId == null) {
      onProgress('Ricerca "$ctGameName" su CardTrader…', null);
      gameId = await ctService.findGameIdByName(ctGameName);
      if (gameId == null) {
        throw Exception(
          '"$ctGameName" non trovato su CardTrader.\n'
          'Il gioco potrebbe non essere ancora disponibile su CT.\n'
          'Riprova più tardi o controlla https://www.cardtrader.com',
        );
      }
    } else {
      onProgress('Caricamento espansioni $ctGameName…', null);
    }

    final expansions = await ctService.fetchExpansionsForGameId(gameId);
    if (expansions.isEmpty) {
      throw Exception('Nessuna espansione trovata per "$ctGameName" (game_id=$gameId)');
    }

    onProgress('${expansions.length} espansioni trovate. Scaricando carte…', null);

    final existingResolvedKeys =
        incremental ? await _getExistingGenericResolvedKeys(catalogCollection) : <String>{};

    final cards = <Map<String, dynamic>>[];
    final discardedSample = <String>[];
    int nextId = 1;
    int skipped = 0;
    int discarded = 0;
    int skippedExisting = 0;

    for (int i = 0; i < expansions.length; i++) {
      final exp = expansions[i];
      final expId = exp['id'] as int;
      final expCode = (exp['code'] as String? ?? '').toLowerCase();
      final expName = exp['name'] as String? ?? expCode;

      onProgress(
        '$expName (${i + 1}/${expansions.length})',
        (i + 1) / expansions.length,
      );

      try {
        final rawBps = await ctService.fetchBlueprintsForExpansion(expId);
        final bps = rawBps.where(_isCardBlueprint).toList();

        for (final bp in bps) {
          final name = ((bp['name_en'] ?? bp['name']) as String? ?? '').trim();
          if (name.isEmpty) { skipped++; continue; }

          final collectorNumber = _extractCtCollectorNumber(bp);
          if (collectorNumber.isEmpty || _isSurrogateCtId(collectorNumber)) {
            discarded++;
            if (discardedSample.length < 20) {
              discardedSample.add('$expName: $name (nessun numero ufficiale CT)');
            }
            continue;
          }

          final apiId = bp['id'].toString();
          if (incremental && existingResolvedKeys.contains(apiId)) {
            skippedExisting++;
            continue;
          }

          String? storageUrl;
          if (uploadImages) {
            final ctImageUrl = CardtraderService.extractBlueprintImageUrl(bp);
            if (ctImageUrl != null) {
              storageUrl = await _uploadCardImageIfNeeded(catalogKey, apiId, ctImageUrl);
            }
          }

          final props = (bp['fixed_properties'] as Map<String, dynamic>?) ?? {};
          cards.add({
            'id': nextId++,
            'api_id': apiId,
            'name': name,
            'card_number': collectorNumber,
            'card_type': bp['category']?.toString()
                ?? props['type']?.toString()
                ?? props['card_type']?.toString(),
            'rarity': bp['rarity']?.toString()
                ?? props['rarity']?.toString(),
            'set_code': expCode.isNotEmpty ? expCode : null,
            'set_name': expName,
            if (storageUrl != null) 'imageUrl': storageUrl,
          });
        }
      } catch (_) {
        // Skip expansion on error — don't abort entire download
        skipped++;
      }
    }

    if (cards.isEmpty && skippedExisting == 0) {
      throw Exception(
        'Nessuna carta trovata per "$ctGameName" su CardTrader.\n'
        'Espansioni trovate: ${expansions.length}, carte skippate: $skipped, scartate (senza numero ufficiale): $discarded.',
      );
    }
    if (cards.isEmpty) {
      return {
        'totalCards': 0,
        'newCards': 0,
        'updatedCards': 0,
        'skipped': skipped,
        'discarded': discarded,
        'discardedSample': discardedSample,
        'skippedExisting': skippedExisting,
      };
    }

    onProgress('${cards.length} carte ${_catalogDisplayName(catalogKey)}. Caricando su Firestore…', null);

    int newCount;
    int updatedCount;
    if (incremental) {
      final upsert = await _upsertCatalogCards(
        catalogCollection: catalogCollection,
        catalog: catalogKey,
        cards: cards,
        adminUid: adminUid,
        onProgress: (cur, tot) => onProgress('Chunk $cur di $tot…', tot > 0 ? cur / tot : null),
      );
      newCount = upsert.newCount;
      updatedCount = upsert.updatedCount;
    } else {
      await _uploadCatalogChunks(
        catalogCollection: catalogCollection,
        cards: cards,
        adminUid: adminUid,
        isIncremental: false,
        onProgress: (cur, tot) =>
            onProgress('Chunk $cur di $tot…', cur / tot),
      );
      newCount = cards.length;
      updatedCount = 0;
    }

    return {
      'totalCards': cards.length,
      'newCards': newCount,
      'updatedCards': updatedCount,
      'skipped': skipped,
      'discarded': discarded,
      'discardedSample': discardedSample,
      'skippedExisting': skippedExisting,
    };
  }

  static String _catalogDisplayName(String key) => switch (key) {
    'yugioh'          => 'Yu-Gi-Oh!',
    'pokemon'         => 'Pokémon',
    'magic'           => 'Magic: The Gathering',
    'onepiece'        => 'One Piece',
    'digimon'         => 'Digimon',
    'lorcana'         => 'Disney Lorcana',
    'flesh-and-blood' => 'Flesh and Blood',
    'vanguard'        => 'Cardfight!! Vanguard',
    'dragon-ball-super' => 'Dragon Ball Super',
    'star-wars'       => 'Star Wars: Unlimited',
    'riftbound'       => 'Riftbound',
    'gundam'          => 'Gundam Card Game',
    'union-arena'     => 'Union Arena',
    _                 => key,
  };

  /// Returns the list of all available catalogs
  static List<Map<String, String>> getCollectionList() {
    return const [
      {'key': 'yugioh',           'name': 'Yu-Gi-Oh!',               'icon': 'style'},
      {'key': 'pokemon',          'name': 'Pokémon',                  'icon': 'catching_pokemon'},
      {'key': 'magic',            'name': 'Magic: The Gathering',     'icon': 'auto_awesome'},
      {'key': 'onepiece',         'name': 'One Piece',                'icon': 'sailing'},
      {'key': 'digimon',          'name': 'Digimon',                  'icon': 'pets'},
      {'key': 'lorcana',          'name': 'Disney Lorcana',           'icon': 'auto_stories'},
      {'key': 'flesh-and-blood',  'name': 'Flesh and Blood',          'icon': 'sports_martial_arts'},
      {'key': 'vanguard',         'name': 'Cardfight!! Vanguard',     'icon': 'shield'},
      {'key': 'dragon-ball-super','name': 'Dragon Ball Super',        'icon': 'bolt'},
      {'key': 'star-wars',        'name': 'Star Wars: Unlimited',     'icon': 'rocket'},
      {'key': 'riftbound',        'name': 'Riftbound',                'icon': 'casino'},
      {'key': 'gundam',           'name': 'Gundam Card Game',         'icon': 'smart_toy'},
      {'key': 'union-arena',      'name': 'Union Arena',              'icon': 'people'},
    ];
  }
}
