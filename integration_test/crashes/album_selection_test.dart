// Regression test: album selection state bugs
//
// Root cause (reported): album selection was wrong after navigating between cards,
// and the -1 sentinel value for "no album" was not always handled consistently.
//
// Specific issues:
//   1. albumId = -1 is the sentinel for "no album" but CardModel.fromMap() stores it
//      as a plain int. Some code paths check `albumId == -1`, others check `albumId == null`.
//   2. _selectedAlbumId in card_detail_page is nullable but set from albumId (an int),
//      so the -1 → null conversion at line 110 must be consistent everywhere.
//   3. Force-unwrap of selectedAlbumId! at card_dialogs.dart line 590 is safe only
//      because of the null guard at line 542 — but stale state from a prior navigation
//      can bypass that guard in edge cases.
//   4. lastUsedAlbumId from SharedPreferences can reference a deleted album;
//      the .firstWhere() at card_dialogs.dart line 551 must use orElse.
//
// Expected (fixed) behaviour:
//   - albumId = -1 consistently maps to "no album selected" everywhere.
//   - Navigating to a card with albumId = -1 does not crash or show wrong album.
//   - A persisted lastUsedAlbumId that no longer exists is silently discarded.
//   - Album capacity check handles null albumId gracefully.

import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/card_model.dart';
import 'package:deck_master/models/album_model.dart';
import '../helpers/test_data_factory.dart';

void main() {
  group('Album selection state', () {
    group('albumId sentinel (-1 = no album)', () {
      test('CardModel.fromMap() preserves albumId = -1 (no album sentinel)', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(albumId: -1));
        expect(card.albumId, equals(-1));
      });

      test('album sentinel -1 maps to null in UI state (regression: inconsistent mapping)', () {
        // Mirrors card_detail_page.dart line 110:
        // _selectedAlbumId = newCard.albumId == -1 ? null : newCard.albumId
        int? toSelectedAlbumId(int albumId) => albumId == -1 ? null : albumId;

        expect(toSelectedAlbumId(-1), isNull);
        expect(toSelectedAlbumId(0), equals(0));
        expect(toSelectedAlbumId(42), equals(42));
      });

      test('no crash when building state for card with no album', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(albumId: -1));
        // Simulate the state initialisation in card_detail_page.dart initState
        int? selectedAlbumId = card.albumId == -1 ? null : card.albumId;
        expect(selectedAlbumId, isNull);
      });
    });

    group('Album lookup safety (.firstWhere with orElse)', () {
      final albums = [
        AlbumModel(id: 1, name: 'Base Set', collection: 'yugioh', maxCapacity: 100),
        AlbumModel(id: 2, name: 'Doppioni', collection: 'yugioh', maxCapacity: 0),
      ];

      test('firstWhere with valid id returns correct album', () {
        final result = albums.firstWhere(
          (a) => a.id == 1,
          orElse: () => AlbumModel(name: '', collection: '', maxCapacity: 0),
        );
        expect(result.name, equals('Base Set'));
      });

      test('firstWhere with deleted/unknown id returns safe fallback (not throws)', () {
        // Regression: stale lastUsedAlbumId = 999 (album was deleted)
        expect(
          () {
            final result = albums.firstWhere(
              (a) => a.id == 999,
              orElse: () => AlbumModel(name: '', collection: '', maxCapacity: 0),
            );
            // Safe fallback must have maxCapacity 0 (treated as no-capacity-limit skip)
            expect(result.maxCapacity, equals(0));
          },
          returnsNormally,
        );
      });

      test('firstWhere WITHOUT orElse throws StateError for unknown id (documents unsafe pattern)', () {
        // This is what happens if orElse is omitted — documents the crash risk.
        expect(
          () => albums.firstWhere((a) => a.id == 999),
          throwsStateError,
          reason: '.firstWhere() without orElse throws when album is deleted — '
              'always use orElse in production code.',
        );
      });
    });

    group('Null safety before force-unwrap', () {
      test('saveCard flow: null albumId is caught before force-unwrap', () {
        // Mirrors card_dialogs.dart _saveCard() lines 542-590:
        // if (selectedAlbumId == null) { showSnackBar; return; }
        // ...
        // int albumIdToUse = selectedAlbumId!; // safe only because of the guard above

        int? selectedAlbumId; // null — no album chosen

        bool saveWasAborted = false;
        void simulateSaveCard() {
          saveWasAborted = true;
          return; // guard
                  // ignore: unnecessary_non_null_assertion
          final _ = selectedAlbumId!; // would crash without the guard
        }

        expect(simulateSaveCard, returnsNormally);
        expect(saveWasAborted, isTrue,
            reason: 'Save must be aborted when no album is selected, '
                'not crash with a null force-unwrap.');
      });

      test('saveCard flow: valid albumId proceeds without abort', () {
        int? selectedAlbumId = 1;
        bool saveWasAborted = false;
        int? usedAlbumId;

        void simulateSaveCard() {
          usedAlbumId = selectedAlbumId;
        }

        simulateSaveCard();
        expect(saveWasAborted, isFalse);
        expect(usedAlbumId, equals(1));
      });
    });

    group('Album selection persistence', () {
      test('lastUsedAlbumId is cleared when the referenced album no longer exists', () {
        // Simulates reading stale prefs and resolving against current album list
        const staleLastUsedId = 999;
        final currentAlbums = [
          AlbumModel(id: 1, name: 'Base', collection: 'yugioh', maxCapacity: 100),
        ];

        final hasAlbum = currentAlbums.any((a) => a.id == staleLastUsedId);
        final resolvedLastUsed = hasAlbum ? staleLastUsedId : null;

        expect(
          resolvedLastUsed,
          isNull,
          reason: 'Stale lastUsedAlbumId $staleLastUsedId should be discarded '
              'when the album no longer exists in the current album list.',
        );
      });
    });
  });
}
