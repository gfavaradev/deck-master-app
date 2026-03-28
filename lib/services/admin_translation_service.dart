import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

/// Fills missing card name/description translations (IT, FR, DE, PT, SP)
/// using the official YGOPRODeck API — same data source as Yu-Gi-Oh! Neuron.
///
/// Only cards missing at least one field are processed.
/// Existing translations are never overwritten.
class AdminTranslationService {
  static const _apiBase = 'https://db.ygoprodeck.com/api/v7/cardinfo.php';
  static const _batchSize = 100; // max IDs per YGOPRODeck request

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Internal lang code → YGOPRODeck language parameter
  static const Map<String, String> _langParam = {
    'it': 'it',
    'fr': 'fr',
    'de': 'de',
    'pt': 'pt',
    'sp': 'es', // YGOPRODeck uses 'es' for Spanish
  };

  /// Fills missing name/description for all YGO cards in [catalog].
  /// Returns a summary map: {translated, skipped, errors, modifiedChunks}.
  Future<Map<String, dynamic>> translateMissingTranslations({
    required String catalog,
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    // Only YGO is supported — other collections have no YGOPRODeck equivalent.
    if (catalog != 'yugioh') {
      throw Exception('Traduzione da YGOPRODeck disponibile solo per Yu-Gi-Oh!');
    }

    final catalogCollection = '${catalog}_catalog';
    onProgress('Lettura catalogo Firestore...', null);

    // ── 1. Download all chunks from Firestore ─────────────────────────────
    final metaDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    final totalChunks =
        metaDoc.exists ? (metaDoc.data()?['totalChunks'] as int? ?? 0) : 0;
    if (totalChunks == 0) throw Exception('Catalogo vuoto su Firestore');

    // Map chunkId → list of cards (mutable)
    final Map<String, List<Map<String, dynamic>>> chunkMap = {};

    for (int i = 0; i < totalChunks; i++) {
      final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
      onProgress(
        'Lettura chunk ${i + 1}/$totalChunks...',
        (i + 1) / totalChunks * 0.2,
      );
      final doc = await _firestore
          .collection(catalogCollection)
          .doc('chunks')
          .collection('items')
          .doc(chunkId)
          .get();
      if (!doc.exists) continue;
      chunkMap[chunkId] = List<Map<String, dynamic>>.from(
        (doc.data()?['cards'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }

    // ── 2. For each language, collect card IDs with missing fields ─────────
    int translatedCards = 0;
    int skippedCards = 0;
    int errorCards = 0;
    final Set<String> modifiedChunkIds = {};

    // Build a flat index: cardId → (chunkId, indexInChunk)
    final Map<int, ({String chunkId, int idx})> cardIndex = {};
    for (final entry in chunkMap.entries) {
      for (int i = 0; i < entry.value.length; i++) {
        final id = entry.value[i]['id'];
        if (id is int) cardIndex[id] = (chunkId: entry.key, idx: i);
      }
    }

    int langsDone = 0;
    for (final langEntry in _langParam.entries) {
      final internalLang = langEntry.key;  // e.g. 'it'
      final apiLang = langEntry.value;     // e.g. 'it'
      final nameKey = 'name_$internalLang';
      final descKey = 'description_$internalLang';

      // Collect IDs of cards missing this language
      final missingIds = <int>[];
      for (final entry in chunkMap.entries) {
        for (final card in entry.value) {
          final id = card['id'];
          if (id is! int) continue;
          final name = card[nameKey] as String?;
          final desc = card[descKey] as String?;
          if ((name == null || name.isEmpty) ||
              (desc == null || desc.isEmpty)) {
            missingIds.add(id);
          }
        }
      }

      if (missingIds.isEmpty) {
        langsDone++;
        skippedCards += cardIndex.length;
        continue;
      }

      onProgress(
        'Lingua ${internalLang.toUpperCase()}: ${missingIds.length} carte mancanti...',
        0.2 + langsDone / _langParam.length * 0.75,
      );

      // Fetch from YGOPRODeck in batches of _batchSize
      for (int b = 0; b < missingIds.length; b += _batchSize) {
        final chunk = missingIds.sublist(
          b,
          (b + _batchSize).clamp(0, missingIds.length),
        );

        onProgress(
          '${internalLang.toUpperCase()}: batch ${b ~/ _batchSize + 1}/${(missingIds.length / _batchSize).ceil()}...',
          0.2 + langsDone / _langParam.length * 0.75 +
              (b / missingIds.length) / _langParam.length * 0.75,
        );

        try {
          final ids = chunk.join('|');
          final uri = Uri.parse(
            '$_apiBase?id=$ids&language=$apiLang',
          );
          final response = await http
              .get(uri, headers: {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 30));

          if (response.statusCode != 200) {
            debugPrint(
              'YGOPRODeck error ${response.statusCode} for lang=$apiLang',
            );
            errorCards += chunk.length;
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }

          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final apiCards = data['data'] as List<dynamic>? ?? [];

          for (final apiCard in apiCards) {
            final id = apiCard['id'] as int?;
            if (id == null) continue;
            final loc = cardIndex[id];
            if (loc == null) continue;

            final card = chunkMap[loc.chunkId]![loc.idx];
            bool modified = false;

            final apiName = (apiCard['name'] as String?)?.trim() ?? '';
            final apiDesc = (apiCard['desc'] as String?)?.trim() ?? '';

            if (apiName.isNotEmpty &&
                (card[nameKey] == null ||
                    (card[nameKey] as String).isEmpty)) {
              card[nameKey] = apiName;
              modified = true;
            }
            if (apiDesc.isNotEmpty &&
                (card[descKey] == null ||
                    (card[descKey] as String).isEmpty)) {
              card[descKey] = apiDesc;
              modified = true;
            }

            if (modified) {
              translatedCards++;
              modifiedChunkIds.add(loc.chunkId);
            }
          }
        } catch (e) {
          debugPrint('Errore fetch YGOPRODeck lang=$apiLang batch=$b: $e');
          errorCards += chunk.length;
        }

        // Respect YGOPRODeck rate limiting
        await Future.delayed(const Duration(milliseconds: 300));
      }

      langsDone++;
    }

    skippedCards = cardIndex.length - translatedCards - errorCards;

    // ── 3. Save modified chunks back to Firestore ─────────────────────────
    if (modifiedChunkIds.isNotEmpty) {
      onProgress(
        'Salvataggio ${modifiedChunkIds.length} chunk su Firestore...',
        0.95,
      );
      for (final chunkId in modifiedChunkIds) {
        await _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .set({'cards': chunkMap[chunkId]!});
      }

      // Bump catalog version
      final currentVersion =
          metaDoc.exists ? (metaDoc.data()?['version'] as int? ?? 0) : 0;
      await _firestore.collection(catalogCollection).doc('metadata').set({
        'version': currentVersion + 1,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': adminUid,
        'modifiedChunks': modifiedChunkIds.toList(),
      }, SetOptions(merge: true));
    }

    onProgress('Completato!', 1.0);
    return {
      'translated': translatedCards,
      'skipped': skippedCards,
      'errors': errorCards,
      'modifiedChunks': modifiedChunkIds.length,
    };
  }

  /// Legge le traduzioni di set e rarità dalla SQLite locale e le salva
  /// nel documento metadata di Firestore come `setTranslations` e
  /// `rarityTranslations`. Al prossimo download del catalogo vengono
  /// applicate automaticamente.
  Future<void> pushSetRarityTranslations({
    required String catalog,
    required String adminUid,
    required Function(String status, double? progress) onProgress,
  }) async {
    if (catalog != 'yugioh') {
      throw Exception('Sincronizzazione disponibile solo per Yu-Gi-Oh!');
    }

    final catalogCollection = '${catalog}_catalog';
    onProgress('Lettura traduzioni dal DB locale...', null);

    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;

    const langs = ['it', 'fr', 'de', 'pt', 'sp'];

    // Build setTranslations map: {enName: {lang: translatedName}}
    final setRows = await db.rawQuery('''
      SELECT set_name,
             ${langs.map((l) => 'MIN(set_name_$l) AS set_name_$l').join(', ')}
      FROM yugioh_prints
      WHERE set_name IS NOT NULL AND set_name != ''
      GROUP BY set_name
    ''');

    final Map<String, Map<String, String>> setTranslations = {};
    for (final row in setRows) {
      final enName = row['set_name'] as String;
      final Map<String, String> trans = {};
      for (final l in langs) {
        final v = row['set_name_$l'] as String?;
        if (v != null && v.isNotEmpty) trans[l] = v;
      }
      if (trans.isNotEmpty) setTranslations[enName] = trans;
    }

    // Build rarityTranslations map: {enRarity: {lang: translatedRarity}}
    final rarityRows = await db.rawQuery('''
      SELECT rarity,
             ${langs.map((l) => 'MIN(rarity_$l) AS rarity_$l').join(', ')}
      FROM yugioh_prints
      WHERE rarity IS NOT NULL AND rarity != ''
      GROUP BY rarity
    ''');

    final Map<String, Map<String, String>> rarityTranslations = {};
    for (final row in rarityRows) {
      final enRarity = row['rarity'] as String;
      final Map<String, String> trans = {};
      for (final l in langs) {
        final v = row['rarity_$l'] as String?;
        if (v != null && v.isNotEmpty) trans[l] = v;
      }
      if (trans.isNotEmpty) rarityTranslations[enRarity] = trans;
    }

    onProgress('Salvataggio su Firestore...', 0.8);

    await _firestore.collection(catalogCollection).doc('metadata').set({
      'setTranslations': setTranslations,
      'rarityTranslations': rarityTranslations,
      'translationsUpdatedBy': adminUid,
      'translationsUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    onProgress(
      'Completato! ${setTranslations.length} set, ${rarityTranslations.length} rarità.',
      1.0,
    );
  }
}
