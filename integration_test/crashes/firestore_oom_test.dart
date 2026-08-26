// Regression test: Firestore unbounded collection queries → Android serialization crash / OOM
//
// Root cause: getCards(), getAlbums(), getCollections(), getDecks() call .get() with no
// .limit() guard. On real devices with >500 documents this causes an OOM or a Firestore
// serialization crash as the entire collection is deserialized into memory at once.
//
// Expected (fixed) behaviour: each method must cap results at a documented safe limit
// (QUERY_LIMIT = 500) and callers that need more must paginate.
//
// Second incident (2026-08-26, prod 1.3.9 vc113): the same class of bug on the
// CardTrader price path. fetchCardtraderPriceRows() ran a single unbounded
// `.get()` on cardtrader_prices/{catalog}/chunks — yugioh had grown to 626
// chunks / ~250 400 rows / ~69 MB. The Firestore plugin encodes the whole
// QuerySnapshot into ONE platform-channel message, so ByteArrayOutputStream
// grew until java.lang.OutOfMemoryError killed the process, every launch,
// for every user (the local syncedAt marker is written only after the fetch,
// so the crash never cleared itself).
//
// Expected (fixed) behaviour: price rows are streamed chunk-batch by
// chunk-batch, so no single batch — and no single platform-channel message —
// ever holds the whole dataset.

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

  group('Firestore OOM \u2013 CardTrader price rows', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService service;

    // 40 chunks x 400 rows = 16 000 rows. Production yugioh is 626 chunks /
    // 250 400 rows; 40 keeps the test fast while still being far larger than
    // any acceptable single batch.
    const int chunks = 40;
    const int rowsPerChunk = 400;
    const int totalRows = chunks * rowsPerChunk;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      service = FirestoreService.forTesting(fakeFirestore);
      await TestDataFactory.seedCardtraderPriceChunks(
        fakeFirestore,
        chunks: chunks,
        rowsPerChunk: rowsPerChunk,
      );
    });

    test('streamCardtraderPriceRows() delivers every row', () async {
      var seen = 0;
      await service.streamCardtraderPriceRows(
        'yugioh',
        onBatch: (rows) async => seen += rows.length,
      );
      expect(seen, totalRows,
          reason: 'streaming must not drop rows: SQLite would keep stale prices.');
    });

    test('streamCardtraderPriceRows() never holds the whole dataset in one batch '
        '(regression: OOM with 626 chunks / 250k rows)', () async {
      final batchSizes = <int>[];
      await service.streamCardtraderPriceRows(
        'yugioh',
        onBatch: (rows) async => batchSizes.add(rows.length),
      );

      expect(batchSizes.length, greaterThan(1),
          reason: 'a single batch means the unbounded .get() is back.');
      final biggest = batchSizes.reduce((a, b) => a > b ? a : b);
      expect(
        biggest,
        lessThan(totalRows),
        reason: 'one batch carried $biggest of $totalRows rows \u2014 that payload '
            'is what OOMs the StandardMessageCodec on Android.',
      );
    });

    test('streamCardtraderPriceRows() honours chunksPerBatch', () async {
      final batchSizes = <int>[];
      await service.streamCardtraderPriceRows(
        'yugioh',
        chunksPerBatch: 2,
        onBatch: (rows) async => batchSizes.add(rows.length),
      );
      expect(batchSizes.every((n) => n <= 2 * rowsPerChunk), isTrue,
          reason: 'batches exceeded the requested chunk ceiling: $batchSizes');
    });

    test('streamCardtraderPriceRows() is a no-op for an unknown catalog', () async {
      var called = false;
      await service.streamCardtraderPriceRows(
        'does-not-exist',
        onBatch: (rows) async => called = true,
      );
      expect(called, isFalse);
    });
  });
}
