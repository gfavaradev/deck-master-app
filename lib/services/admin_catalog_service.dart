import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:deck_master/models/pending_catalog_change.dart';
import 'package:deck_master/services/database_helper.dart';

/// Service for managing admin catalog operations
class AdminCatalogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _pendingChangesKey = 'admin_pending_catalog_changes';
  static const int _chunkSize = 200;

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
                cards[idx] = change.cardData;
              } else {
                cards.removeAt(idx);
              }
              affectedChunkIds.add(chunkId);
              break;
            }
          }
          break;

        case ChangeType.add:
          // Append to the last chunk; create a new chunk if it exceeds _chunkSize
          final lastChunkId = sortedChunkIds.last;
          final lastChunk = chunkMap[lastChunkId]!;
          if (lastChunk.length < _chunkSize) {
            lastChunk.add(change.cardData);
            affectedChunkIds.add(lastChunkId);
          } else {
            // Last chunk is full: create a new one
            final newIndex = sortedChunkIds.length + 1;
            final newChunkId = 'chunk_${newIndex.toString().padLeft(3, '0')}';
            chunkMap[newChunkId] = [change.cardData];
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
