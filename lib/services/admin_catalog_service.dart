import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
    } catch (_) {
      // Not in storage yet — download from source and upload
      try {
        // Try the primary URL; if 404 fall back to high.png variant
        String fetchUrl = sourceUrl;
        debugPrint('[IMG] Scaricando: $fetchUrl');
        var response = await http.get(Uri.parse(fetchUrl));
        if (response.statusCode == 404 && fetchUrl.endsWith('/high.webp')) {
          fetchUrl = fetchUrl.replaceFirst('/high.webp', '/high.png');
          debugPrint('[IMG] Fallback PNG: $fetchUrl');
          response = await http.get(Uri.parse(fetchUrl));
        }
        debugPrint('[IMG] HTTP ${response.statusCode} — ${response.bodyBytes.length} bytes');
        if (response.statusCode != 200) return null;
        final compressed = await _compressCardImage(response.bodyBytes);
        debugPrint('[IMG] Compressa: ${compressed.length} bytes — uploading su Storage...');
        await ref.putData(
          compressed,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await ref.getDownloadURL();
        debugPrint('[IMG] OK: $url');
        return url;
      } catch (e) {
        debugPrint('[IMG] ERRORE card $cardId ($catalog): $e');
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

      // Add per-set image_url to each EN set entry (only if not already set by admin)
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
    } catch (e) {
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
    } catch (_) {
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
      } catch (e) {
        debugPrint('Could not load existing catalog for preservation (skipping): $e');
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
    } catch (e) {
      debugPrint('Traduzioni $lang non disponibili: $e. Continuo senza.');
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
            'set_price': _parseDouble(set['set_price']),
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
        RegExp(r'^([A-Z0-9]+)-(EN|IT|FR|DE|PT|E|I|F|D|P)(.+)$')
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
            'set_price': p['set_price'],
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
        } catch (_) {
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
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
        // Exponential back-off: 2 s, 4 s
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        debugPrint('Firestore write retry ${attempt + 2}/$maxAttempts after: $e');
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
    final response = await http.get(Uri.parse('$_optcgBaseUrl/$endpoint'));
    if (response.statusCode == 404 && optional) {
      debugPrint('[OPTCG] Endpoint $endpoint not found (404), skipping.');
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

      final groupKey = '$name\x00$type\x00$color\x00$cost\x00$power\x00$life';

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
        } catch (_) {
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

  /// Simple GET with retry+backoff for TCGDex (no API key needed).
  Future<dynamic> _tcgdexGet(String url) async {
    const backoffs = [5, 15, 30, 60];
    const maxAttempts = 5;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          return json.decode(response.body);
        }

        if (attempt == maxAttempts) {
          throw Exception('TCGDex errore permanente: HTTP ${response.statusCode} — $url');
        }
        final wait = backoffs[attempt - 1];
        debugPrint('TCGDex HTTP ${response.statusCode}, tentativo $attempt/$maxAttempts, attendo ${wait}s...');
        await Future.delayed(Duration(seconds: wait));
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        final wait = backoffs[attempt - 1];
        debugPrint('TCGDex errore ($e), tentativo $attempt/$maxAttempts, attendo ${wait}s...');
        await Future.delayed(Duration(seconds: wait));
      }
    }
    throw Exception('TCGDex: tutti i tentativi falliti per $url');
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
    } catch (_) {
      return null;
    }
  }

  /// Clears saved progress.
  Future<void> _clearPokemonProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pokemonProgressKey);
  }

  /// Fetches ALL Pokémon cards from TCGDex, set by set, with resume support.
  /// Each set requires only ONE request (returns set info + cards together).
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
      debugPrint('Pokémon: riprendendo da $skippedCount set già completati, skip...');
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
      if (allCards.isNotEmpty) await Future.delayed(const Duration(milliseconds: 500));

      final result = await _fetchTcgdexSetData(setId);
      final serieId = (result.setInfo['serie'] as Map?)?['id']?.toString() ?? '';

      for (final card in result.cards) {
        allCards.add(_transformTcgdexCard(card, result.setInfo, serieId));
      }
      completedSetIds.add(setId);

      // Persist progress after every set so we can resume on failure
      await _savePokemonProgress(
          completedSetIds, allCards.length + (savedProgress?.cardCount ?? 0));
    }
    return allCards;
  }

  /// Transforms a raw TCGDex card brief + set info into the Firestore storage format.
  Map<String, dynamic> _transformTcgdexCard(
      Map<String, dynamic> card,
      Map<String, dynamic> setInfo,
      String serieId) {
    final localId = card['localId']?.toString() ?? card['id']?.toString() ?? '';
    final setId = setInfo['id']?.toString() ?? '';
    // Compose a unique api_id matching the TCGDex card ID format: "{setId}-{localId}"
    final apiId = card['id']?.toString() ?? '$setId-$localId';

    // TCGDex image URL pattern: {image}/high.webp
    // 'image' field is the base URL without quality/extension suffix
    final imageBase = card['image']?.toString();
    final imageUrl = imageBase != null ? '$imageBase/high.webp' : null;

    final setName = setInfo['name']?.toString();
    final serieName = (setInfo['serie'] as Map?)?['name']?.toString();

    return {
      'api_id': apiId,
      'name': card['name']?.toString() ?? '',
      'supertype': null,   // not available in brief — can be filled via migration
      'subtype': null,
      'hp': null,
      'types': null,
      'rarity': null,      // not in brief listing
      'set_id': setId,
      'set_name': setName,
      'set_series': serieName,
      'number': localId,
      // image_url = source URL (will be migrated to Firebase Storage)
      if (imageUrl != null) 'image_url': imageUrl,
      'prints': [
        {
          'set_code': apiId,
          'set_name': setName,
          'rarity': null,
          'set_price': null,
          if (imageUrl != null) 'artwork': imageUrl,
        }
      ],
    };
  }

  /// Downloads the **full** Pokémon catalog from TCGDex, uploads every image to
  /// Firebase Storage (compressing to ~80 KB JPEG), then saves metadata to Firestore.
  /// Images already present in Storage are skipped (getDownloadURL check).
  Future<Map<String, dynamic>> downloadPokemonCatalogFromAPI({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    // Cancella eventuale progresso parziale salvato da run precedenti
    await _clearPokemonProgress();

    // 1. Fetch + transform all cards from TCGDex
    final cards = await _fetchAllPokemonCards(onProgress);
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
          final prints = (card['prints'] as List<dynamic>?)
              ?.map((p) => Map<String, dynamic>.from(p as Map)..['artwork'] = storageUrl)
              .toList();
          if (prints != null) card['prints'] = prints;
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

    // 3. Upload chunks to Firestore
    await _uploadCatalogChunks(
      catalogCollection: 'pokemon_catalog',
      cards: processedCards,
      adminUid: adminUid,
      isIncremental: false,
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
          // Update artwork in each print
          final prints = (card['prints'] as List<dynamic>?)
              ?.map((p) {
                final pm = Map<String, dynamic>.from(p as Map);
                pm['artwork'] = storageUrl;
                return pm;
              })
              .toList();
          if (prints != null) card['prints'] = prints;
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
