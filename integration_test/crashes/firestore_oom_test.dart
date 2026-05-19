// Regression test: Firestore unbounded collection queries → Android serialization crash / OOM
//
// Root cause: getCards(), getAlbums(), getCollections(), getDecks() call .get() with no
// .limit() guard. On real devices with >500 documents this causes an OOM or a Firestore
// serialization crash as the entire collection is deserialized into memory at once.
//
// Expected (fixed) behaviour: each method must cap results at a documented safe limit
// (QUERY_LIMIT = 500) and callers that need more must paginate.

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:deck_master/services/firestore_service.dart';
import '../helpers/test_data_factory.dart';

const int kQueryLimit = 500; // safe per-call ceiling enforced by the service

void main() {
  group('Firestore OOM – unbounded queries', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService service;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      service = FirestoreService.forTesting(fakeFirestore);
    });

    test('getCards() returns at most $kQueryLimit documents (regression: OOM with 10k docs)', () async {
      // Arrange: seed 10 000 cards — a realistic large collection
      await TestDataFactory.seedUserCards(fakeFirestore, count: 10000);

      // Act
      final cards = await service.getCards(TestDataFactory.testUserId);

      // Assert: the service must NOT return all 10 000 docs at once
      expect(
        cards.length,
        lessThanOrEqualTo(kQueryLimit),
        reason: 'getCards() without a .limit() guard returns ${ cards.length } docs '
            'and will OOM on Android with realistic collection sizes.',
      );
    });

    test('getAlbums() returns at most $kQueryLimit documents', () async {
      await TestDataFactory.seedUserAlbums(fakeFirestore, count: 600);

      final albums = await service.getAlbums(TestDataFactory.testUserId);

      expect(
        albums.length,
        lessThanOrEqualTo(kQueryLimit),
        reason: 'getAlbums() fetches ${albums.length} docs with no limit guard.',
      );
    });

    test('getCards() result is non-null and iterable when collection is empty', () async {
      // No seeding — empty collection must return [] not throw
      final cards = await service.getCards(TestDataFactory.testUserId);
      expect(cards, isNotNull);
      expect(cards, isEmpty);
    });

    test('getCards() result contains expected fields for each document', () async {
      await TestDataFactory.seedUserCards(fakeFirestore, count: 5);
      final cards = await service.getCards(TestDataFactory.testUserId);
      for (final card in cards) {
        expect(card.containsKey('name'), isTrue);
        expect(card.containsKey('serialNumber'), isTrue);
        expect(card.containsKey('quantity'), isTrue);
      }
    });
  });
}
