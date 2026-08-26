import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:deck_master/constants/app_constants.dart';
import 'package:deck_master/utils/firestore_paths.dart';

/// Generates realistic Firestore test data for regression tests.
class TestDataFactory {
  static const String testUserId = 'test-user-regression';

  /// Max writes per batch commit. Firestore (and fake_cloud_firestore) reject
  /// batches larger than 500 operations.
  static const int _batchLimit = 450;

  /// Seeds [count] card documents into the fake Firestore under the user's cards
  /// collection. Uses the same field names as FirestoreService.insertCard().
  static Future<void> seedUserCards(
    FakeFirebaseFirestore firestore, {
    int count = 10000,
    String userId = testUserId,
  }) async {
    final col = firestore.collection('users/$userId/cards');
    // Chunk commits at ≤500 ops — Firestore's hard per-batch limit.
    for (int b = 0; b < count; b += _batchLimit) {
      final batch = firestore.batch();
      final end = (b + _batchLimit).clamp(0, count);
      for (int i = b; i < end; i++) {
        batch.set(col.doc('card_$i'), {
          'catalogId': 'cat_$i',
          'name': 'Card $i',
          'serialNumber': 'SN-${i.toString().padLeft(5, '0')}',
          'collection': 'yugioh',
          'albumId': (i % 5) + 1,
          'albumFirestoreId': 'album_${(i % 5) + 1}',
          'type': 'Monster',
          'rarity': 'Common',
          'description': 'Test card $i',
          'quantity': 1,
          'value': 1.5 + (i % 100) * 0.1,
          'imageUrl': null,
        });
      }
      await batch.commit();
    }
  }

  /// Seeds `cardtrader_prices/{catalog}` with [chunks] chunk documents of
  /// [rowsPerChunk] price rows each, mirroring the layout written by
  /// `FirestoreService.saveCardtraderPrices()` and `scripts/price_sync`:
  /// chunk doc ids are the numeric row offset (`'0'`, `'400'`, …) and the
  /// parent doc carries `count` = total rows.
  static Future<void> seedCardtraderPriceChunks(
    FakeFirebaseFirestore firestore, {
    String catalog = 'yugioh',
    int chunks = 40,
    int rowsPerChunk = 400,
  }) async {
    final ref = firestore.collection('cardtrader_prices').doc(catalog);
    for (int c = 0; c < chunks; c++) {
      final start = c * rowsPerChunk;
      await ref.collection('chunks').doc('$start').set({
        'rows': [
          for (int i = 0; i < rowsPerChunk; i++)
            {
              'blueprint_id': start + i,
              'language': 'en',
              'first_edition': 0,
              'rarity': 'Common',
              'min_price_nm_cents': 100 + ((start + i) % 500),
              'listing_count': 3,
              'synced_at': '2026-08-26T03:00:00.000Z',
            },
        ],
      });
    }
    await ref.set({
      'catalog': catalog,
      'count': chunks * rowsPerChunk,
      'syncedAt': DateTime.utc(2026, 8, 26, 3),
    });
  }

  /// Seeds [count] album documents.
  static Future<void> seedUserAlbums(
    FakeFirebaseFirestore firestore, {
    int count = 500,
    String userId = testUserId,
  }) async {
    final col = firestore.collection('users/$userId/albums');
    // Chunk commits at ≤500 ops — Firestore's hard per-batch limit.
    for (int b = 0; b < count; b += _batchLimit) {
      final batch = firestore.batch();
      final end = (b + _batchLimit).clamp(0, count);
      for (int i = b; i < end; i++) {
        batch.set(col.doc('album_$i'), {
          'name': 'Album $i',
          'collection': 'yugioh',
          'maxCapacity': 100,
        });
      }
      await batch.commit();
    }
  }

  /// Builds a catalog metadata + chunk structure with [chunksCount] chunks,
  /// each containing [cardsPerChunk] card entries.
  static Future<void> seedCatalog(
    FakeFirebaseFirestore firestore,
    String catalogName, {
    int chunksCount = 50,
    int cardsPerChunk = 200,
  }) async {
    // Metadata doc
    await firestore
        .collection(FirestorePaths.catalog(catalogName))
        .doc(FirestoreConstants.catalogMetadata)
        .set({'totalChunks': chunksCount, 'version': 1});

    // Chunk docs (batched to avoid hitting fake Firestore limits)
    const batchSize = 20;
    for (int b = 0; b < chunksCount; b += batchSize) {
      final batch = firestore.batch();
      final end = (b + batchSize).clamp(0, chunksCount);
      for (int i = b; i < end; i++) {
        final cards = List.generate(cardsPerChunk, (j) => {
          'id': 'c_${i}_$j',
          'name': 'Catalog Card ${i}_$j',
          'serialNumber': 'S${i.toString().padLeft(3, '0')}-${j.toString().padLeft(3, '0')}',
        });
        batch.set(
          firestore
              .collection(FirestorePaths.catalog(catalogName))
              .doc(FirestoreConstants.catalogChunks)
              .collection(FirestoreConstants.catalogItems)
              .doc(FirestoreConstants.getChunkId(i + 1)),
          {'cards': cards},
        );
      }
      await batch.commit();
    }
  }

  /// Returns a CardModel-compatible map with a given [quantity] (may be negative).
  static Map<String, dynamic> cardMap({
    String name = 'Test Card',
    String serialNumber = 'TC-001',
    int quantity = 1,
    double value = 10.0,
    int albumId = 1,
  }) => {
    'id': null,
    'catalogId': 'cat_1',
    'name': name,
    'serialNumber': serialNumber,
    'collection': 'yugioh',
    'albumId': albumId,
    'type': 'Monster',
    'rarity': 'Common',
    'description': '',
    'quantity': quantity,
    'value': value,
    'cardtrader_value': null,
    'imageUrl': null,
    'purchase_price': null,
  };
}
