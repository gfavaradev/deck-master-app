import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'cardtrader_service.dart' show CardtraderService;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:deck_master/models/pending_catalog_change.dart';
import 'package:deck_master/services/database_helper.dart';

/// Service for managing admin catalog operations
class AdminCatalogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _pendingChangesKey = 'admin_pending_catalog_changes';
  static const int _chunkSize = 100;

  // ============================================================
  // Image Storage
  // ============================================================

  /// Uploads a card image to Firebase Storage if not already there.
  /// [catalog] determines the storage path (e.g. 'yugioh', 'pokemon', 'onepiece').
  /// [cardId] can be an int (YuGiOh) or String (Pokémon api_id).
  /// Returns the Firebase Storage download URL, or null on failure.
  Future<String?> _uploadCardImageIfNeeded(String catalog, dynamic cardId, String? sourceUrl) async {
    if (sourceUrl == null || sourceUrl.isEmpty) return null;
    final safeId = cardId.toString().replaceAll(RegExp(r'[/\s]'), '_');
    final ref = _storage.ref('catalog/$catalog/images/$safeId.jpg');
    try {
      return await ref.getDownloadURL(); // already uploaded
    } catch (_) { // ignore: empty_catches
      // Not in storage yet — download from source and upload
      try {
        // Try the primary URL; if 404 fall back to high.png variant
        String fetchUrl = sourceUrl;

        var response = await http.get(Uri.parse(fetchUrl));
        if (response.statusCode == 404 && fetchUrl.endsWith('/high.webp')) {
          fetchUrl = fetchUrl.replaceFirst('/high.webp', '/high.png');

          response = await http.get(Uri.parse(fetchUrl));
        }

        if (response.statusCode != 200) return null;
        final compressed = await _compressCardImage(response.bodyBytes);

        await ref.putData(
          compressed,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await ref.getDownloadURL();

        return url;
      } catch (e) { // ignore: empty_catches

        return null;
      }
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
      // Store Firebase Storage URL at card level (backward compat for web / old clients)
      updatedCard['imageUrl'] = storageUrl;

      if (catalog == 'onepiece') {
        // One Piece: update artwork in each print entry
        final prints = updatedCard['prints'];
        if (prints is List) {
          updatedCard['prints'] = prints.map((p) {
            final print = Map<String, dynamic>.from(p as Map);
            final existingArtwork = print['artwork'] as String?;
            if (existingArtwork == null || existingArtwork.isEmpty ||
                !existingArtwork.contains('firebasestorage')) {
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
                  !existingUrl.contains('firebasestorage')) {
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
  Future<Map<String, dynamic>> publishChanges({
    required String adminUid,
    required Function(int current, int total) onProgress,
  }) async {
    final changes = await getPendingChanges();

    if (changes.isEmpty) {
      return {'success': true, 'message': 'Nessuna modifica da pubblicare'};
    }

    try {
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

      return {
        'success': true,
        'message': 'Pubblicate ${changes.length} modifiche con successo',
        'changesCount': changes.length,
      };
    } catch (e) { // ignore: empty_catches
      return {'success': false, 'error': e.toString()};
    }
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

    // 5. Apply changes, track affected chunks and index mutations
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
            cards[idx] = await _processCardForStorage(change.cardData);
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
          final processedCard = await _processCardForStorage(change.cardData);
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
                cards[idx] = await _processCardForStorage(change.cardData);
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
          final processedCard = await _processCardForStorage(change.cardData);
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

  /// Search cards in local database (or Firestore on web)
  Future<List<Map<String, dynamic>>> searchCards(String query) async {
    // On web, SQLite doesn't work - return empty and user must download from Firestore
    if (kIsWeb) {
      // Web users must use downloadCurrentCatalog instead
      return [];
    }

    final db = await _dbHelper.database;

    final results = await db.rawQuery('''
      SELECT DISTINCT
        yp.id,
        yp.name,
        yp.type,
        yp.race,
        yp.archetype,
        yp.atk,
        yp.def,
        yp.level,
        yp.attribute,
        yp.description
      FROM yugioh_prints yp
      WHERE yp.name LIKE ?
         OR yp.archetype LIKE ?
         OR CAST(yp.id AS TEXT) LIKE ?
      LIMIT 100
    ''', ['%$query%', '%$query%', '%$query%']);

    return results.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Get card details by ID
  Future<Map<String, dynamic>?> getCardById(int cardId) async {
    // On web, SQLite doesn't work
    if (kIsWeb) {
      return null;
    }

    final db = await _dbHelper.database;

    final results = await db.rawQuery('''
      SELECT *
      FROM yugioh_prints yp
      WHERE yp.id = ?
      LIMIT 1
    ''', [cardId]);

    if (results.isEmpty) return null;
    return Map<String, dynamic>.from(results.first);
  }

  /// Migrates all catalog card images from external URLs to Firebase Storage.
  ///
  /// Only processes cards that have `image_url` (external source) but no
  /// `imageUrl` (Firebase Storage URL). Already-migrated cards are skipped.
  ///
  /// Returns `{migrated, failed, chunksUpdated}`.
  Future<Map<String, dynamic>> migrateAllImagesToStorage({
    required String catalog,
    required String adminUid,
    required Function(int current, int total) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';

    // 0. Delete all existing images in Storage for this catalog
    try {
      final folder = _storage.ref('catalog/$catalog/images');
      final listResult = await folder.listAll();
      for (final item in listResult.items) {
        try { await item.delete(); } catch (_) {}
      }
    } catch (_) { // ignore: empty_catches
      // Cartella non ancora esistente — procedi normalmente
    }

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
        // URLs with Firebase Storage URL; existing Storage URLs are preserved
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
                    !existingUrl.contains('firebasestorage')) {
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
  static const List<String> _apiLangs = ['en', 'it', 'fr', 'de', 'pt'];

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
      if (url != null && url.contains('firebasestorage')) {
        imageUrlMap[entry.key] = url;
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
    final newCards = _transformYGOProDeckCards(newRaw);

    await _uploadCatalogChunks(
      catalogCollection: 'yugioh_catalog',
      cards: newCards,
      adminUid: adminUid,
      isIncremental: true,
      onProgress: (cur, tot) =>
          onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {'newCards': newCards.length};
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
    for (final lang in ['it', 'fr', 'de', 'pt']) {
      final existingByCode = <String, Map<String, dynamic>>{};
      for (final s in List.from(setsByLang[lang] ?? [])) {
        final code = (s['set_code']?.toString() ?? '').toUpperCase();
        if (code.isNotEmpty) existingByCode.putIfAbsent(code, () => s);
      }
      final newList = <Map<String, dynamic>>[];
      for (final enSet in enSets) {
        final enCode = enSet['set_code']?.toString() ?? '';
        final localCode = _generateLocalizedSetCode(enCode, lang);
        final targetCode = localCode ?? enCode;
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

  Future<Map<int, Map<String, dynamic>>> _getExistingCardsMap(
      String catalogCollection) async {
    final snapshot = await _firestore
        .collection(catalogCollection)
        .doc('chunks')
        .collection('items')
        .get();
    final map = <int, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      for (final raw in (doc.data()['cards'] as List? ?? [])) {
        final card = Map<String, dynamic>.from(raw as Map);
        final id = card['id'];
        if (id is int) map[id] = card;
      }
    }
    return map;
  }

  Future<Set<int>> _getExistingCardIds(String catalogCollection) async {
    final snapshot = await _firestore
        .collection(catalogCollection)
        .doc('chunks')
        .collection('items')
        .get();
    final ids = <int>{};
    for (final doc in snapshot.docs) {
      for (final card in (doc.data()['cards'] as List? ?? [])) {
        final id = (card as Map)['id'];
        if (id != null) ids.add((id as num).toInt());
      }
    }
    return ids;
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
      onProgress(i + 1, chunks.length);
    }

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

  /// Writes [data] to [ref] with up to 3 attempts and exponential back-off.
  /// Handles transient `deadline-exceeded` errors on slow connections.
  Future<void> _writeWithRetry(
    DocumentReference ref,
    Map<String, dynamic> data, {
    int maxAttempts = 3,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await ref.set(data);
        return;
      } catch (e) { // ignore: empty_catches
        if (attempt == maxAttempts - 1) rethrow;
        // Exponential back-off: 2 s, 4 s
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));

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

  /// Comprime un'immagine carta preservando i colori ICC (codec nativi).
  /// Target: ~80-100 KB — buona qualità, ~40% risparmio rispetto all'originale.
  Future<Uint8List> _compressCardImage(Uint8List bytes, {int maxWidth = 400, int quality = 78}) async {
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxWidth,
      minHeight: 9999, // no height constraint — only width is limited, aspect ratio preserved
      quality: quality,
      format: CompressFormat.jpeg,
    );
    return result;
  }

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
        if (artwork != null && artwork.contains('firebasestorage') && cardSetId != null) {
          existingImageUrls[cardSetId] = artwork;
        }
      }
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
        'artwork': existingArtwork ?? m['card_image']?.toString(),
      });
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

    onProgress('${mergedCards.length} carte uniche. Caricando su Firestore...', null);

    await _uploadCatalogChunks(
      catalogCollection: 'onepiece_catalog',
      cards: mergedCards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Caricando chunk $cur di $tot...', cur / tot),
    );

    return {'totalCards': mergedCards.length, 'totalPrints': allRaw.length};
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
    final toMigrate = <({String chunkId, int cardIndex, int printIndex, String cardSetId, String sourceUrl})>[];
    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final prints = card['prints'] as List<dynamic>? ?? [];
        for (int j = 0; j < prints.length; j++) {
          final p = Map<String, dynamic>.from(prints[j] as Map);
          final artwork = p['artwork'] as String?;
          final sourceUrl = p['artwork'] as String? ?? card['image_url'] as String?;
          final needsMigration = sourceUrl != null &&
              sourceUrl.isNotEmpty &&
              (force || artwork == null || !artwork.contains('firebasestorage'));
          if (needsMigration) {
            toMigrate.add((
              chunkId: chunkId,
              cardIndex: i,
              printIndex: j,
              cardSetId: p['card_set_id'] as String? ?? '',
              sourceUrl: sourceUrl,
            ));
          }
        }
      }
    }

    if (toMigrate.isEmpty) return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};

    int migrated = 0, failed = 0;
    final affectedChunkIds = <String>{};

    for (int i = 0; i < toMigrate.length; i++) {
      final item = toMigrate[i];
      onProgress(i + 1, toMigrate.length);

      try {
        final ref = _storage.ref('catalog/onepiece/images/${item.cardSetId}.jpg');
        String? storageUrl;
        try {
          storageUrl = await ref.getDownloadURL();
        } catch (_) { // ignore: empty_catches
          final response = await http.get(Uri.parse(item.sourceUrl));
          if (response.statusCode == 200) {
            final compressed = await _compressCardImage(response.bodyBytes);
            await ref.putData(compressed,
                SettableMetadata(contentType: 'image/jpeg'));
            storageUrl = await ref.getDownloadURL();
          }
        }

        if (storageUrl != null) {
          final card = Map<String, dynamic>.from(chunkMap[item.chunkId]![item.cardIndex]);
          final prints = List<dynamic>.from(card['prints'] as List);
          final print = Map<String, dynamic>.from(prints[item.printIndex] as Map);
          print['artwork'] = storageUrl;
          prints[item.printIndex] = print;
          card['prints'] = prints;
          // Aggiorna image_url della card con la prima immagine migrata
          if (!card.containsKey('imageUrl')) card['imageUrl'] = storageUrl;
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
      // Svuota i modifiedChunks per forzare un re-download completo sul client
      // (la migrazione tocca tutti i chunk, non un sottoinsieme)
      'modifiedChunks': [],
    }, SetOptions(merge: true));

    return {'migrated': migrated, 'failed': failed, 'chunksUpdated': affectedChunkIds.length};
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

    final total = cards.length;
    onProgress('$total carte ricevute. Caricando immagini su Firebase Storage (0/$total)...', 0);

    // 2. Upload each image to Firebase Storage (skip if already there)
    int done = 0, failed = 0;
    final processedCards = <Map<String, dynamic>>[];

    for (int i = 0; i < total; i++) {
      final card = Map<String, dynamic>.from(cards[i]);
      final apiId = card['api_id'] as String?;
      final sourceUrl = card['image_url'] as String?;

      if (apiId != null && sourceUrl != null && sourceUrl.isNotEmpty) {
        final storageUrl = await _uploadCardImageIfNeeded('pokemon', apiId, sourceUrl);
        if (storageUrl != null) {
          done++;
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
        } else {
          failed++;
        }
      }

      processedCards.add(card);

      if (i % 100 == 0 || i == total - 1) {
        onProgress(
          'Immagini: ${i + 1}/$total — ok: $done, fallite: $failed',
          (i + 1) / total,
        );
      }
    }

    onProgress('Immagini completate. Salvataggio catalogo su Firestore...', null);

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

    return {
      'totalCards': processedCards.length,
      'imagesOk': done,
      'imagesFailed': failed,
    };
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
        final sourceUrl = (card['image_url'] ?? card['imageUrl']) as String?;
        final storageUrl = card['imageUrl'] as String?;
        final apiId = card['api_id'] as String? ?? '';
        final needsMigration = sourceUrl != null &&
            sourceUrl.isNotEmpty &&
            (force || storageUrl == null || !storageUrl.contains('firebasestorage'));
        if (needsMigration && apiId.isNotEmpty) {
          toMigrate.add((
            chunkId: chunkId,
            cardIndex: i,
            apiId: apiId,
            sourceUrl: sourceUrl,
          ));
        }
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

    return {
      'migrated': migrated,
      'failed': failed,
      'chunksUpdated': affectedChunkIds.length,
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

                // Ricerca per nome (primaria)
                double? price = priceByNameLang['$expCode|$nameEn|$ctLang'];

                // Fallback: ricerca per collector-number (parte dopo l'ultimo '-')
                if (price == null) {
                  final cn = rawCode.contains('-')
                      ? rawCode.split('-').last.toLowerCase()
                      : '';
                  if (cn.isNotEmpty) {
                    price = priceByCNLang['$expCode|$cn|$ctLang'];
                  }
                }

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
            final nameEn    = (card['name'] as String? ?? '').toLowerCase();
            final rawPrintsField = card['prints'];
            if (rawPrintsField is! List) break;
            final rawPrints = rawPrintsField;

            final updatedPrintsList = rawPrints.map((raw) {
              final p       = Map<String, dynamic>.from(raw as Map);
              final expCode = (p['set_id'] as String? ?? '').toLowerCase();
              if (expCode.isEmpty) return p;

              // Ricava CN e lingua da card_set_id (es. 'OP01-001' → cn='001', lang='ja')
              final cardSetId = p['card_set_id'] as String? ?? '';
              final rawCN = cardSetId.contains('-')
                  ? cardSetId.split('-').last.toLowerCase()
                  : '';
              final langMatch = RegExp(r'^([a-z]{2})\d').firstMatch(rawCN);
              final ctLang    = langMatch != null ? langMatch.group(1)! : 'ja';

              // Ricerca per nome (primaria, lingua specifica poi fallback su 'en')
              double? price = priceByNameLang['$expCode|$nameEn|$ctLang'];
              price ??= priceByNameLang['$expCode|$nameEn|en'];

              // Fallback: ricerca per CN
              if (price == null && rawCN.isNotEmpty) {
                price = priceByCNLang['$expCode|$rawCN|$ctLang'];
                price ??= priceByCNLang['$expCode|$rawCN|en'];
                price ??= priceByCNLang['$expCode|$rawCN|ja'];
              }

              if (price != null) {
                cardModified = true;
                updatedPrices++;
                return {...p, 'market_price': price};
              }
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

  /// Downloads the complete catalog for [catalog] ('pokemon' or 'onepiece')
  /// from CardTrader blueprints API and uploads to Firestore.
  /// Images are downloaded from CT CDN and stored in Firebase Storage.
  Future<Map<String, dynamic>> downloadCatalogFromCardtrader({
    required String catalog,
    required String adminUid,
    required void Function(String status, double? progress) onProgress,
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

    final List<Map<String, dynamic>> allCards;
    if (catalog == 'pokemon') {
      allCards = await _buildPokemonCatalogFromCT(
        expansions: expansions,
        ctService: ctService,
        onProgress: onProgress,
      );
    } else {
      allCards = await _buildOnepieceCatalogFromCT(
        expansions: expansions,
        ctService: ctService,
        onProgress: onProgress,
      );
    }

    if (allCards.isEmpty) throw Exception('Nessuna carta estratta da CT');

    onProgress('Caricamento ${allCards.length} carte su Firestore…', null);
    await _uploadCatalogChunks(
      catalogCollection: '${catalog}_catalog',
      cards: allCards,
      adminUid: adminUid,
      isIncremental: false,
      onProgress: (cur, tot) =>
          onProgress('Chunk $cur/$tot caricato', tot > 0 ? cur / tot : null),
    );

    return {
      'totalCards': allCards.length,
      'totalExpansions': expansions.length,
    };
  }

  /// Builds Pokemon catalog cards from CT blueprints.
  /// Output format: Firestore `sets` map (compatible with _normalizePokemonCardForSQLite).
  Future<List<Map<String, dynamic>>> _buildPokemonCatalogFromCT({
    required List<Map<String, dynamic>> expansions,
    required CardtraderService ctService,
    required void Function(String, double?) onProgress,
  }) async {
    final allCards = <Map<String, dynamic>>[];
    final errors = <String>[];
    int skippedEmpty = 0;

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
        final blueprints = await ctService.fetchBlueprintsForExpansion(expId);
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

        String bpCollectorNumber(Map<String, dynamic> bp) {
          // CT may expose collector_number as top-level or inside fixed_properties
          final top = bp['collector_number'] ?? bp['number'];
          if (top != null) return top.toString().trim();
          final p = bpProps(bp);
          final nested = p['collector_number'] ?? p['number'];
          if (nested != null) return nested.toString().trim();
          return bp['id']?.toString() ?? '';
        }

        String bpRarityFn(Map<String, dynamic> bp, String fallback) {
          final top = bp['rarity']?.toString() ?? '';
          if (top.isNotEmpty) return top;
          final p = bpProps(bp);
          return (p['pokemon_rarity'] ?? p['rarity'])?.toString() ?? fallback;
        }

        // Group blueprints by collector_number — same number = same card across languages
        final byNumber = <String, List<Map<String, dynamic>>>{};
        for (final bp in blueprints) {
          final num = bpCollectorNumber(bp);
          if (num.isEmpty) continue;
          byNumber.putIfAbsent(num, () => []).add(bp);
        }

        for (final entry in byNumber.entries) {
          final collectorNumber = entry.key;
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

          // Upload EN image to Firebase Storage once per card
          final ctImageUrl = CardtraderService.extractBlueprintImageUrl(enBp);
          final apiId = '$expCode-$collectorNumber';
          final storageUrl = ctImageUrl != null
              ? await _uploadCardImageIfNeeded('pokemon', apiId, ctImageUrl)
              : null;

          // Build sets map: one entry per language
          final setsMap = <String, dynamic>{};
          for (final bp in langBps) {
            final lang = bpLang(bp);
            final bpRarity = bpRarityFn(bp, rarity);
            setsMap[lang] = [
              {
                'set_code': collectorNumber,
                'set_name': expName,
                'rarity': bpRarity,
                if (storageUrl != null) 'artwork': storageUrl,
              }
            ];
          }
          setsMap.putIfAbsent('en', () => [
            {
              'set_code': collectorNumber,
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
            'sets': setsMap,
          });
        }
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        errors.add('$expName: $e');
      }
    }

    if (allCards.isEmpty) {
      final detail = [
        if (skippedEmpty > 0) '$skippedEmpty/${expansions.length} espansioni con 0 blueprint',
        if (errors.isNotEmpty) 'errori: ${errors.take(3).join(' | ')}',
        if (skippedEmpty == 0 && errors.isEmpty) 'tutte le espansioni erano vuote',
      ].join('; ');
      throw Exception('Nessuna carta Pokémon estratta da CT. $detail');
    }
    return allCards;
  }

  /// Builds One Piece catalog cards from CT blueprints.
  /// Output format: flat `prints` list (compatible with insertOnepieceCards).
  Future<List<Map<String, dynamic>>> _buildOnepieceCatalogFromCT({
    required List<Map<String, dynamic>> expansions,
    required CardtraderService ctService,
    required void Function(String, double?) onProgress,
  }) async {
    final allCards = <Map<String, dynamic>>[];
    final errors = <String>[];
    int skippedEmpty = 0;
    int nextId = 1;

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
        final blueprints = await ctService.fetchBlueprintsForExpansion(expId);
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

        String bpCollNum(Map<String, dynamic> bp) {
          final top = bp['collector_number'] ?? bp['number'];
          if (top != null) return top.toString().trim();
          final p = bpProps(bp);
          final nested = p['collector_number'] ?? p['number'];
          if (nested != null) return nested.toString().trim();
          return bp['id']?.toString() ?? '';
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
          if (nameEn.isEmpty) continue;
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

          final prints = <Map<String, dynamic>>[];
          for (final bp in langBps) {
            final collNum = bpCollNum(bp);
            if (collNum.isEmpty) continue;

            // Build card_set_id: prepend expansion code if not already present
            final collUpper = collNum.toUpperCase();
            final cardSetId = collUpper.startsWith(expCode)
                ? collUpper
                : '$expCode-$collUpper';

            final bpRarity = bpRarityFn(bp, rarity);
            final ctImageUrl = CardtraderService.extractBlueprintImageUrl(bp);
            final storageUrl = ctImageUrl != null
                ? await _uploadCardImageIfNeeded(
                    'onepiece', '${expCode}_$collNum', ctImageUrl)
                : null;
            prints.add({
              'card_set_id': cardSetId,
              'set_id': expCode,
              'set_name': expName,
              'rarity': bpRarity,
              if (storageUrl != null) 'artwork': storageUrl,
            });
          }
          if (prints.isEmpty) continue;

          allCards.add({
            'id': nextId++,
            'name': nameEn,
            if (jaName != nameEn) 'name_ja': jaName,
            'catalog': 'onepiece',
            'rarity': rarity,
            'prints': prints,
          });
        }
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        errors.add('$expName: $e');
      }
    }

    if (allCards.isEmpty) {
      final detail = [
        if (skippedEmpty > 0) '$skippedEmpty/${expansions.length} espansioni con 0 blueprint',
        if (errors.isNotEmpty) 'errori: ${errors.take(3).join(' | ')}',
        if (skippedEmpty == 0 && errors.isEmpty) 'tutte le espansioni erano vuote',
      ].join('; ');
      throw Exception('Nessuna carta One Piece estratta da CT. $detail');
    }
    return allCards;
  }

  // ============================================================
  // Collection list
  // ============================================================

  /// Returns the list of all available catalogs
  static List<Map<String, String>> getCollectionList() {
    return const [
      {'key': 'yugioh', 'name': 'Yu-Gi-Oh!', 'icon': 'style'},
      {'key': 'pokemon', 'name': 'Pokémon', 'icon': 'catching_pokemon'},
      {'key': 'magic', 'name': 'Magic: The Gathering', 'icon': 'auto_awesome'},
      {'key': 'onepiece', 'name': 'One Piece', 'icon': 'sailing'},
    ];
  }
}
