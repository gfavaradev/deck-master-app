import 'package:deck_master/utils/subscription_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('savingsPercent', () {
    test('calcola lo sconto della scala attuale (mensile 4.99)', () {
      // Semestrale 22.99 → 3.83/mese contro 4.99.
      expect(
        savingsPercent(monthlyPrice: 4.99, planPrice: 22.99, months: 6),
        23,
      );
      // Annuale 34.99 → 2.92/mese contro 4.99. Il valore esatto è 41,57%:
      // troncato a 41, non arrotondato a 42.
      expect(
        savingsPercent(monthlyPrice: 4.99, planPrice: 34.99, months: 12),
        41,
      );
    });

    test('calcola lo sconto della scala precedente (mensile 2.99)', () {
      expect(
        savingsPercent(monthlyPrice: 2.99, planPrice: 12.99, months: 6),
        27,
      );
      expect(
        savingsPercent(monthlyPrice: 2.99, planPrice: 19.99, months: 12),
        44,
      );
    });

    test('non restituisce sconti negativi se il piano conviene meno', () {
      // 6 mesi di mensile costano 29.94: un semestrale a 34.99 è più caro.
      expect(
        savingsPercent(monthlyPrice: 4.99, planPrice: 34.99, months: 6),
        0,
      );
    });

    test('regge un prezzo mensile assente senza dividere per zero', () {
      expect(savingsPercent(monthlyPrice: 0, planPrice: 34.99, months: 12), 0);
    });
  });
}
