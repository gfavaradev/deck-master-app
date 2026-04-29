import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/subscription_model.dart';

void main() {
  group('DonationTier', () {
    // ── fromTotal ─────────────────────────────────────────────────────────
    group('fromTotal', () {
      test('0.0 → none', () => expect(DonationTier.fromTotal(0.0), DonationTier.none));
      test('1.98 → none (sotto la soglia comune)', () => expect(DonationTier.fromTotal(1.98), DonationTier.none));
      test('1.99 → comune (esattamente sulla soglia)', () => expect(DonationTier.fromTotal(1.99), DonationTier.comune));
      test('2.0 → comune', () => expect(DonationTier.fromTotal(2.0), DonationTier.comune));
      test('5.99 → comune (sotto nonComune)', () => expect(DonationTier.fromTotal(5.99), DonationTier.comune));
      test('6.0 → nonComune (esattamente sulla soglia)', () => expect(DonationTier.fromTotal(6.0), DonationTier.nonComune));
      test('11.99 → nonComune', () => expect(DonationTier.fromTotal(11.99), DonationTier.nonComune));
      test('12.0 → raro', () => expect(DonationTier.fromTotal(12.0), DonationTier.raro));
      test('19.99 → raro', () => expect(DonationTier.fromTotal(19.99), DonationTier.raro));
      test('20.0 → ultraRaro', () => expect(DonationTier.fromTotal(20.0), DonationTier.ultraRaro));
      test('29.99 → ultraRaro', () => expect(DonationTier.fromTotal(29.99), DonationTier.ultraRaro));
      test('30.0 → secretRare', () => expect(DonationTier.fromTotal(30.0), DonationTier.secretRare));
      test('100.0 → secretRare', () => expect(DonationTier.fromTotal(100.0), DonationTier.secretRare));
    });

    // ── fromString ────────────────────────────────────────────────────────
    group('fromString', () {
      test('nomi validi ritornano il tier corretto', () {
        expect(DonationTier.fromString('none'), DonationTier.none);
        expect(DonationTier.fromString('comune'), DonationTier.comune);
        expect(DonationTier.fromString('nonComune'), DonationTier.nonComune);
        expect(DonationTier.fromString('raro'), DonationTier.raro);
        expect(DonationTier.fromString('ultraRaro'), DonationTier.ultraRaro);
        expect(DonationTier.fromString('secretRare'), DonationTier.secretRare);
      });

      test('null → none', () => expect(DonationTier.fromString(null), DonationTier.none));
      test('stringa sconosciuta → none', () => expect(DonationTier.fromString('UNKNOWN'), DonationTier.none));
      test('stringa vuota → none', () => expect(DonationTier.fromString(''), DonationTier.none));
    });

    // ── label ─────────────────────────────────────────────────────────────
    group('label', () {
      test('none ha label vuota', () => expect(DonationTier.none.label, ''));
      test('comune → Comune', () => expect(DonationTier.comune.label, 'Comune'));
      test('secretRare → Secret Rare', () => expect(DonationTier.secretRare.label, 'Secret Rare'));
    });

    // ── symbol ────────────────────────────────────────────────────────────
    group('symbol', () {
      test('none ha symbol vuoto', () => expect(DonationTier.none.symbol, ''));
      test('ogni tier ha un symbol distinto', () {
        final symbols = DonationTier.values.map((t) => t.symbol).where((s) => s.isNotEmpty).toSet();
        expect(symbols.length, DonationTier.values.length - 1); // none escluso
      });
    });

    // ── requiredTotal ─────────────────────────────────────────────────────
    group('requiredTotal', () {
      test('none richiede 0', () => expect(DonationTier.none.requiredTotal, 0));
      test('soglie in ordine crescente', () {
        final tiers = [
          DonationTier.none,
          DonationTier.comune,
          DonationTier.nonComune,
          DonationTier.raro,
          DonationTier.ultraRaro,
          DonationTier.secretRare,
        ];
        for (int i = 1; i < tiers.length; i++) {
          expect(tiers[i].requiredTotal, greaterThan(tiers[i - 1].requiredTotal));
        }
      });
    });

    // ── nextTier ──────────────────────────────────────────────────────────
    group('nextTier', () {
      test('catena completa', () {
        expect(DonationTier.none.nextTier, DonationTier.comune);
        expect(DonationTier.comune.nextTier, DonationTier.nonComune);
        expect(DonationTier.nonComune.nextTier, DonationTier.raro);
        expect(DonationTier.raro.nextTier, DonationTier.ultraRaro);
        expect(DonationTier.ultraRaro.nextTier, DonationTier.secretRare);
        expect(DonationTier.secretRare.nextTier, isNull);
      });
    });

    // ── flag booleani ─────────────────────────────────────────────────────
    group('flag', () {
      test('hasBorder: false per none e comune, true dagli altri', () {
        expect(DonationTier.none.hasBorder, isFalse);
        expect(DonationTier.comune.hasBorder, isFalse);
        expect(DonationTier.nonComune.hasBorder, isTrue);
        expect(DonationTier.raro.hasBorder, isTrue);
        expect(DonationTier.ultraRaro.hasBorder, isTrue);
        expect(DonationTier.secretRare.hasBorder, isTrue);
      });

      test('hasAnimation: solo ultraRaro e secretRare', () {
        expect(DonationTier.none.hasAnimation, isFalse);
        expect(DonationTier.comune.hasAnimation, isFalse);
        expect(DonationTier.raro.hasAnimation, isFalse);
        expect(DonationTier.ultraRaro.hasAnimation, isTrue);
        expect(DonationTier.secretRare.hasAnimation, isTrue);
      });

      test('isInWallOfFame: solo secretRare', () {
        for (final t in DonationTier.values) {
          expect(t.isInWallOfFame, t == DonationTier.secretRare);
        }
      });
    });

    // ── consistenza fromTotal / requiredTotal ─────────────────────────────
    test('fromTotal(tier.requiredTotal) == tier per ogni tier non-none', () {
      for (final tier in DonationTier.values) {
        if (tier == DonationTier.none) continue;
        expect(DonationTier.fromTotal(tier.requiredTotal), tier,
            reason: 'fromTotal(${tier.requiredTotal}) dovrebbe essere $tier');
      }
    });

    test('fromString(tier.name) == tier per ogni tier', () {
      for (final tier in DonationTier.values) {
        expect(DonationTier.fromString(tier.name), tier);
      }
    });
  });
}
