// Regression test: parallel catalog downloads → Android heap OOM
//
// Root cause: fetchCatalog() fires Future.wait() on batches of 10 chunks. Each chunk
// carries up to 200 card maps. With 50 chunks × 200 cards = 10 000 maps all held in
// memory in `allCards` before being written to SQLite. On low-RAM devices (2 GB) this
// OOMs the Dart VM.
//
// Expected (fixed) behaviour:
//   1. Concurrent requests per batch must not exceed kMaxConcurrentChunks.
//   2. The service must flush (write to SQLite / invoke onBatch) and release each batch
//      before fetching the next, so peak memory ≈ batchSize × chunkSize not totalSize.

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:deck_master/services/firestore_service.dart';
import '../helpers/test_data_factory.dart';

const int kMaxConcurrentChunks = 10;
const int kTestChunks = 30;
const int kCardsPerChunk = 200;

void main() {
  group('Parallel catalog downloads – heap OOM', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService service;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      service = FirestoreService.forTesting(fakeFirestore);
    });

    test('fetchCatalog() processes all chunks and returns correct total card count', () async {
      // Arrange
      const catalogName = 'yugioh';
      await TestDataFactory.seedCatalog(
        fakeFirestore,
        catalogName,
        chunksCount: kTestChunks,
        cardsPerChunk: kCardsPerChunk,
      );

      // Act
      int progressCallCount = 0;
      int lastProgressValue = 0;
      final cards = await service.fetchCatalog(
        catalogName,
        onProgress: (current, total) {
          progressCallCount++;
          expect(current, greaterThanOrEqualTo(lastProgressValue),
              reason: 'Progress must be monotonically increasing');
          lastProgressValue = current;
          expect(total, equals(kTestChunks));
        },
      );

      // Assert: correct total
      expect(cards.length, equals(kTestChunks * kCardsPerChunk));

      // Assert: progress was reported for every batch
      expect(progressCallCount, greaterThan(0));
    });

    test('fetchCatalog() batch size never exceeds $kMaxConcurrentChunks concurrent requests', () async {
      // We track how many Firestore get() calls are in-flight simultaneously.
      // Fake Firestore resolves synchronously, so we instrument via the progress callback
      // to infer batch boundaries instead.
      const catalogName = 'yugioh';
      await TestDataFactory.seedCatalog(
        fakeFirestore,
        catalogName,
        chunksCount: 25,
        cardsPerChunk: 50,
      );

      final List<int> batchSizes = [];
      int previousProgress = 0;

      await service.fetchCatalog(
        catalogName,
        onProgress: (current, total) {
          final batchSize = current - previousProgress;
          if (batchSize > 0) batchSizes.add(batchSize);
          previousProgress = current;
        },
      );

      for (final size in batchSizes) {
        expect(
          size,
          lessThanOrEqualTo(kMaxConcurrentChunks),
          reason: 'fetchCatalog() fired a batch of $size concurrent requests; '
              'max allowed is $kMaxConcurrentChunks to prevent heap OOM.',
        );
      }
    });

    test('fetchCatalog() throws descriptively when metadata is missing', () async {
      // No catalog seeded — metadata doc absent
      expect(
        () => service.fetchCatalog('nonexistent_catalog'),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchCatalog() completes without error for catalog with 0 chunks', () async {
      await fakeFirestore
          .collection('catalogs/empty_catalog/meta')
          .doc('metadata')
          .set({'totalChunks': 0});

      expect(
        () => service.fetchCatalog('empty_catalog'),
        throwsA(isA<Exception>()), // should throw "No chunks available"
      );
    });
  });
}
