import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
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
  /// Returns the Firebase Storage download URL, or null on failure.
  Future<String?> _uploadCardImageIfNeeded(int cardId, String? sourceUrl) async {
    if (sourceUrl == null || sourceUrl.isEmpty) return null;
    final ref = _storage.ref('catalog/yugioh/images/$cardId.jpg');
    try {
      return await ref.getDownloadURL(); // already uploaded
    } catch (_) {
      // Not in storage yet — download from source and upload
      try {
        final response = await http.get(Uri.parse(sourceUrl));
        if (response.statusCode != 200) return null;
        await ref.putData(
          response.bodyBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        return await ref.getDownloadURL();
      } catch (e) {
        debugPrint('Image upload failed for card $cardId: $e');
        return null;
      }
    }
  }

  /// Processes a card before publishing:
  /// - uploads image to Firebase Storage
  /// - stores the Storage URL inside each EN set as `image_url`
  /// - removes the top-level `image_url` (ygoprodeck URL)
  Future<Map<String, dynamic>> _processCardForStorage(Map<String, dynamic> card) async {
    final cardId = card['id'];
    if (cardId == null) return card;

    final sourceUrl = card['image_url'] as String?;
    final storageUrl = await _uploadCardImageIfNeeded(cardId as int, sourceUrl);

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

  /// Surgical publish: reads all chunks to locate cards, then writes ONLY
  /// the chunks that were actually modified (typically 1-2 for edits/deletes,
  /// or the last chunk for adds).
  Future<void> _publishCatalogChangesSurgical({
    required String catalog,
    required List<PendingCatalogChange> changes,
    required String adminUid,
    required Function(int, int) onProgress,
  }) async {
    final catalogCollection = '${catalog}_catalog';

    // 1. Download all chunks as an ordered map  chunkId → mutable card list
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) return;

    final sortedChunkIds = chunkMap.keys.toList()..sort();

    // 2. Sort changes by timestamp (oldest first)
    final sortedChanges = List<PendingCatalogChange>.from(changes)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 3. Apply each change and track affected chunk IDs
    final affectedChunkIds = <String>{};
    final deletedCardIds = <dynamic>[];

    for (final change in sortedChanges) {
      switch (change.type) {
        case ChangeType.edit:
        case ChangeType.delete:
          final targetId = change.originalCardId ?? change.cardData['id'];
          // Find the chunk containing this card
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
          // Append to the last chunk; create a new chunk if it exceeds _chunkSize
          final processedCard = await _processCardForStorage(change.cardData);
          final lastChunkId = sortedChunkIds.last;
          final lastChunk = chunkMap[lastChunkId]!;
          if (lastChunk.length < _chunkSize) {
            lastChunk.add(processedCard);
            affectedChunkIds.add(lastChunkId);
          } else {
            // Last chunk is full: create a new one
            final newIndex = sortedChunkIds.length + 1;
            final newChunkId = 'chunk_${newIndex.toString().padLeft(3, '0')}';
            chunkMap[newChunkId] = [processedCard];
            sortedChunkIds.add(newChunkId);
            affectedChunkIds.add(newChunkId);
          }
          break;
      }
    }

    // 4. Write ONLY the affected chunks (typically 1-2 writes instead of 70)
    int step = 0;
    final totalSteps = affectedChunkIds.length + 1; // +1 for metadata update

    for (final chunkId in affectedChunkIds) {
      final cards = chunkMap[chunkId]!;
      if (cards.isEmpty) {
        // Chunk became empty due to deletes — remove it from Firestore
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
      onProgress(++step, totalSteps);
    }

    // 5. Update metadata (version, totalCards, totalChunks)
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
    onProgress(totalSteps, totalSteps);
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

    // 1. Download all chunks
    final chunkMap = await _downloadChunksMap(catalogCollection, onProgress);
    if (chunkMap.isEmpty) {
      return {'migrated': 0, 'failed': 0, 'chunksUpdated': 0};
    }

    final sortedChunkIds = chunkMap.keys.toList()..sort();

    // 2. Collect cards that need migration
    final toMigrate = <({String chunkId, int cardIndex, int cardId, String sourceUrl})>[];
    for (final chunkId in sortedChunkIds) {
      final cards = chunkMap[chunkId]!;
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final sourceUrl = card['image_url'] as String?;
        final storageUrl = card['imageUrl'] as String?;
        final needsMigration =
            (sourceUrl?.isNotEmpty ?? false) && (storageUrl?.isEmpty ?? true);
        if (needsMigration) {
          toMigrate.add((
            chunkId: chunkId,
            cardIndex: i,
            cardId: card['id'] as int,
            sourceUrl: sourceUrl!,
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

      final storageUrl = await _uploadCardImageIfNeeded(item.cardId, item.sourceUrl);
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

  /// Fills missing localized sets (IT/FR/DE/PT) for all cards currently in
  /// the Firestore catalog, using surgical per-chunk writes.
  Future<Map<String, dynamic>> fillMissingLocalizedSets({
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    const catalogCollection = 'yugioh_catalog';

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
          ? (cardImages[0] as Map)['image_url_small'] as String?
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
      _generateMissingSetsFromEn(setsByLang);

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
