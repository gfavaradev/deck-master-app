// Regression test: negative quantity / value fields → wrong totals displayed in UI
//
// Root cause: CardModel.fromMap() accepts any integer for `quantity` and any double
// for `value` with no floor guard. Downstream arithmetic in card_list_page.dart
// (lines 618-631) accumulates `sum + effectivePrice * item.quantity` without
// clamping, so a single card with quantity=-5 makes the entire collection total
// negative. This was reported as "negative numbers" in album/collection views.
//
// Expected (fixed) behaviour:
//   - CardModel.quantity must be clamped to >= 0 at construction time.
//   - CardModel.value / purchasePrice must be clamped to >= 0.
//   - Collection total and count computations must never return negative values.

import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/card_model.dart';
import '../helpers/test_data_factory.dart';

void main() {
  group('Negative number handling', () {
    group('CardModel construction', () {
      test('fromMap() clamps negative quantity to 0 (regression: quantity = -5)', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(quantity: -5));
        expect(
          card.quantity,
          greaterThanOrEqualTo(0),
          reason: 'CardModel.fromMap() accepted quantity=-5 without clamping. '
              'Negative quantities corrupt collection totals.',
        );
      });

      test('fromMap() clamps negative value to 0.0', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(value: -99.99));
        expect(
          card.value,
          greaterThanOrEqualTo(0.0),
          reason: 'CardModel.fromMap() accepted value=-99.99. '
              'Negative values corrupt the portfolio total.',
        );
      });

      test('fromMap() preserves valid positive quantity', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(quantity: 3));
        expect(card.quantity, equals(3));
      });

      test('fromMap() preserves quantity = 0', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(quantity: 0));
        expect(card.quantity, equals(0));
      });

      test('fromMap() preserves valid positive value', () {
        final card = CardModel.fromMap(TestDataFactory.cardMap(value: 12.50));
        expect(card.value, equals(12.50));
      });
    });

    group('Collection total calculations (mirrors card_list_page.dart fold logic)', () {
      // Replicates the exact fold from card_list_page.dart lines 618-621.
      double totalValue(List<CardModel> cards) => cards.fold(0.0, (sum, item) {
            final price = item.cardtraderValue ?? item.value;
            return sum + (price * item.quantity);
          });

      int totalCount(List<CardModel> cards) =>
          cards.fold(0, (sum, item) => sum + item.quantity);

      test('total value is non-negative even when one card has negative quantity', () {
        final cards = [
          CardModel.fromMap(TestDataFactory.cardMap(quantity: 5, value: 10.0)),
          CardModel.fromMap(TestDataFactory.cardMap(quantity: -3, value: 10.0)), // bug trigger
          CardModel.fromMap(TestDataFactory.cardMap(quantity: 2, value: 5.0)),
        ];
        expect(
          totalValue(cards),
          greaterThanOrEqualTo(0.0),
          reason: 'A card with quantity=-3 pulls the total below zero.',
        );
      });

      test('total count is non-negative even when one card has negative quantity', () {
        final cards = [
          CardModel.fromMap(TestDataFactory.cardMap(quantity: 2)),
          CardModel.fromMap(TestDataFactory.cardMap(quantity: -10)), // bug trigger
        ];
        expect(
          totalCount(cards),
          greaterThanOrEqualTo(0),
          reason: 'A card with quantity=-10 makes total count negative.',
        );
      });

      test('total value is 0 for empty collection', () {
        expect(totalValue([]), equals(0.0));
      });

      test('doppioni map accumulation does not produce negative totals', () {
        // Mirrors card_list_page.dart lines 113-116:
        // doppioniMap[key] = (doppioniMap[key] ?? 0) + c.quantity
        final cards = [
          CardModel.fromMap(TestDataFactory.cardMap(serialNumber: 'TC-001', quantity: -2)),
          CardModel.fromMap(TestDataFactory.cardMap(serialNumber: 'TC-001', quantity: 3)),
        ];

        final doppioniMap = <String, int>{};
        for (final c in cards) {
          final key = '${c.serialNumber.toLowerCase()}|${c.rarity.toLowerCase()}|${c.catalogId ?? ''}';
          doppioniMap[key] = (doppioniMap[key] ?? 0) + c.quantity;
        }

        for (final qty in doppioniMap.values) {
          expect(
            qty,
            greaterThanOrEqualTo(0),
            reason: 'Doppioni map accumulated a negative total ($qty) for a key.',
          );
        }
      });
    });
  });
}
