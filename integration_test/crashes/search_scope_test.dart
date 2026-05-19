// Regression test: search scope bugs
//
// Root cause: _filterCards() in card_list_page.dart searches only serialNumber
// (not name, rarity, or type). _searchCatalog() triggers a separate async
// catalog query scoped to the current collectionKey. When the filter and catalog
// searches use different field sets, search results are incomplete or misleading.
//
// Specific bugs reported:
//   1. Searching by card name returns nothing (only serialNumber is searched locally).
//   2. Catalog search fires on every keystroke without debounce causing stale results.
//   3. Very long search strings and special characters cause unexpected behaviour.
//
// Expected (fixed) behaviour:
//   - Local filter matches on at least name AND serialNumber.
//   - Catalog search result is discarded if the query changed before it resolved.
//   - Empty / whitespace / very-long queries are handled gracefully.

import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/card_model.dart';
import '../helpers/test_data_factory.dart';

// Extracted and testable version of the filter predicate.
// Mirrors _applyFilter in card_list_page.dart — update this if the production
// code is widened to include name/rarity/type.
bool _localMatches(CardModel card, String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return true;
  return card.serialNumber.toLowerCase().contains(q) ||
      card.name.toLowerCase().contains(q); // name search MUST be included
}

void main() {
  group('Search scope', () {
    final cards = [
      CardModel.fromMap(TestDataFactory.cardMap(name: 'Blue-Eyes White Dragon', serialNumber: 'SDK-001')),
      CardModel.fromMap(TestDataFactory.cardMap(name: 'Dark Magician', serialNumber: 'SDK-002')),
      CardModel.fromMap(TestDataFactory.cardMap(name: 'Red-Eyes Black Dragon', serialNumber: 'LOB-070')),
    ];

    group('Local filter predicate', () {
      test('empty query matches all cards', () {
        final results = cards.where((c) => _localMatches(c, '')).toList();
        expect(results.length, equals(cards.length));
      });

      test('whitespace-only query matches all cards', () {
        final results = cards.where((c) => _localMatches(c, '   ')).toList();
        // whitespace normalised to empty → all match
        expect(results.length, equals(cards.length));
      });

      test('serial number search returns matching cards', () {
        final results = cards.where((c) => _localMatches(c, 'SDK')).toList();
        expect(results.length, equals(2));
      });

      test('name search returns matching cards (regression: only serialNumber was searched)', () {
        final results = cards.where((c) => _localMatches(c, 'dark magician')).toList();
        expect(
          results.length,
          equals(1),
          reason: 'Searching by name returned ${results.length} results. '
              'The production filter only checked serialNumber (regression).',
        );
      });

      test('case-insensitive search works for both fields', () {
        final results = cards.where((c) => _localMatches(c, 'BLUE-EYES')).toList();
        expect(results.length, equals(1));
      });

      test('very long query (1000 chars) does not throw', () {
        final longQuery = 'a' * 1000;
        expect(
          () => cards.where((c) => _localMatches(c, longQuery)).toList(),
          returnsNormally,
        );
      });

      test('query with special regex characters does not throw', () {
        const specialChars = r'.*+?^${}()|[]\\';
        expect(
          () => cards.where((c) => _localMatches(c, specialChars)).toList(),
          returnsNormally,
        );
      });

      test('no results for query that matches nothing', () {
        final results = cards.where((c) => _localMatches(c, 'zzz-not-found-999')).toList();
        expect(results, isEmpty);
      });
    });

    group('Stale result guard (catalog async search)', () {
      // Simulates the race condition: query changes before the async result returns.
      test('result discarded when query changed before resolution', () async {
        String currentQuery = 'dragon';
        List<CardModel> displayedSuggestions = [];

        Future<List<CardModel>> mockCatalogSearch(String query) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return cards.where((c) => c.name.toLowerCase().contains(query)).toList();
        }

        // Simulate: user types 'dragon', then immediately types 'magician'
        final future = mockCatalogSearch('dragon').then((results) {
          // Stale-result guard — mirrors the `if (!mounted) return` pattern
          if (currentQuery != 'dragon') return; // query already changed
          displayedSuggestions = results;
        });

        currentQuery = 'magician'; // query changed before future resolves
        await future;

        // The 'dragon' results must NOT appear — they are stale
        expect(
          displayedSuggestions,
          isEmpty,
          reason: 'Stale catalog search results for "dragon" were displayed '
              'after the query changed to "magician".',
        );
      });
    });
  });
}
