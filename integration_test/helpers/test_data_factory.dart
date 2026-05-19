import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Generates realistic Firestore test data for regression tests.
class TestDataFactory {
  static const String testUserId = 'test-user-regression';

  /// Seeds [count] card documents into the fake Firestore under the user's cards
  /// collection. Uses the same field names as FirestoreService.insertCard().
  static Future<void> seedUserCards(
    FakeFirebaseFirestore firestore, {
    int count = 10000,
    String userId = testUserId,
  }) async {
    final batch = firestore.batch();
    final col = firestore.collection('users/$userId/cards');
    for (int i = 0; i < count; i++) {
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

  /// Seeds [count] album documents.
  static Future<void> seedUserAlbums(
    FakeFirebaseFirestore firestore, {
    int count = 500,
    String userId = testUserId,
  }) async {
    final batch = firestore.batch();
    final col = firestore.collection('users/$userId/albums');
    for (int i = 0; i < count; i++) {
      batch.set(col.doc('album_$i'), {
        'name': 'Album $i',
        'collection': 'yugioh',
        'maxCapacity': 100,
      });
    }
    await batch.commit();
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
        .collection('catalogs/$catalogName/meta')
        .doc('metadata')
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
              .collection('catalogs/$catalogName/chunks/chunk_list/items')
              .doc('chunk_${(i + 1).toString().padLeft(3, '0')}'),
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
