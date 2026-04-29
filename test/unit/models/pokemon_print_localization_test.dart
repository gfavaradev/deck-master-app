import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/pokemon_models.dart';

void main() {
  // ── PokemonPrint localization ───────────────────────────────────────────────
  group('PokemonPrint localization', () {
    final fullMap = {
      'id': 1,
      'card_id': 10,
      'set_code': 'swsh1-25',
      'set_name': 'Sword & Shield',
      'rarity': 'Rare Holo',
      'set_price': 8.00,
      'artwork': 'https://img.url/art.jpg',
      'set_code_it': 'swsh1it-25',
      'set_name_it': 'Spada e Scudo',
      'rarity_it': 'Rara Olografica',
      'set_price_it': 7.50,
      'set_code_fr': 'swsh1fr-25',
      'set_name_fr': 'Épée et Bouclier',
      'rarity_fr': 'Rare Holographique',
      'set_price_fr': 7.00,
      'set_code_de': 'swsh1de-25',
      'set_name_de': 'Schwert und Schild',
      'rarity_de': 'Seltene Holografische',
      'set_price_de': 6.50,
      'set_code_pt': 'swsh1pt-25',
      'set_name_pt': 'Espada e Escudo',
      'rarity_pt': 'Rara Holográfica',
      'set_price_pt': 7.20,
    };

    group('getLocalizedSetCode', () {
      final print = PokemonPrint.fromMap(fullMap);
      test('IT → setCodeIt', () => expect(print.getLocalizedSetCode('IT'), 'swsh1it-25'));
      test('FR → setCodeFr', () => expect(print.getLocalizedSetCode('FR'), 'swsh1fr-25'));
      test('DE → setCodeDe', () => expect(print.getLocalizedSetCode('DE'), 'swsh1de-25'));
      test('PT → setCodePt', () => expect(print.getLocalizedSetCode('PT'), 'swsh1pt-25'));
      test('EN → setCode base', () => expect(print.getLocalizedSetCode('EN'), 'swsh1-25'));
      test('fallback a base se null', () {
        final p = PokemonPrint.fromMap({'card_id': 1, 'set_code': 'base'});
        expect(p.getLocalizedSetCode('IT'), 'base');
      });
    });

    group('getLocalizedSetName', () {
      final print = PokemonPrint.fromMap(fullMap);
      test('IT → setNameIt', () => expect(print.getLocalizedSetName('IT'), 'Spada e Scudo'));
      test('FR → setNameFr', () => expect(print.getLocalizedSetName('FR'), 'Épée et Bouclier'));
      test('DE → setNameDe', () => expect(print.getLocalizedSetName('DE'), 'Schwert und Schild'));
      test('PT → setNamePt', () => expect(print.getLocalizedSetName('PT'), 'Espada e Escudo'));
      test('EN → setName base', () => expect(print.getLocalizedSetName('EN'), 'Sword & Shield'));
    });

    group('getLocalizedRarity', () {
      final print = PokemonPrint.fromMap(fullMap);
      test('IT → rarityIt', () => expect(print.getLocalizedRarity('IT'), 'Rara Olografica'));
      test('FR → rarityFr', () => expect(print.getLocalizedRarity('FR'), 'Rare Holographique'));
      test('DE → rarityDe', () => expect(print.getLocalizedRarity('DE'), 'Seltene Holografische'));
      test('PT → rarityPt', () => expect(print.getLocalizedRarity('PT'), 'Rara Holográfica'));
      test('EN → rarity base', () => expect(print.getLocalizedRarity('EN'), 'Rare Holo'));
      test('fallback a base se null', () {
        final p = PokemonPrint.fromMap({'card_id': 1, 'set_code': 'x', 'rarity': 'Rare'});
        expect(p.getLocalizedRarity('IT'), 'Rare');
      });
    });

    group('getLocalizedPrice', () {
      final print = PokemonPrint.fromMap(fullMap);
      test('IT → setPriceIt', () => expect(print.getLocalizedPrice('IT'), 7.50));
      test('FR → setPriceFr', () => expect(print.getLocalizedPrice('FR'), 7.00));
      test('DE → setPriceDe', () => expect(print.getLocalizedPrice('DE'), 6.50));
      test('PT → setPricePt', () => expect(print.getLocalizedPrice('PT'), 7.20));
      test('EN → setPrice base', () => expect(print.getLocalizedPrice('EN'), 8.00));
      test('fallback a base se traduzione è null', () {
        final p = PokemonPrint.fromMap({'card_id': 1, 'set_code': 'x', 'set_price': 5.0});
        expect(p.getLocalizedPrice('IT'), 5.0);
      });
      test('null se nessun prezzo', () {
        final p = PokemonPrint.fromMap({'card_id': 1, 'set_code': 'x'});
        expect(p.getLocalizedPrice('EN'), isNull);
        expect(p.getLocalizedPrice('IT'), isNull);
      });
    });
  });

  // ── PokemonPrice ────────────────────────────────────────────────────────────
  group('PokemonPrice', () {
    final fullMap = {
      'id': 1,
      'print_id': 10,
      'language': 'EN',
      'cardmarket_price': 8.00,
      'tcgplayer_price': 9.50,
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-04-28T00:00:00.000',
    };

    test('fromMap parsa tutti i campi', () {
      final price = PokemonPrice.fromMap(fullMap);
      expect(price.id, 1);
      expect(price.printId, 10);
      expect(price.language, 'EN');
      expect(price.cardmarketPrice, 8.00);
      expect(price.tcgplayerPrice, 9.50);
      expect(price.createdAt, DateTime(2026, 1, 1));
      expect(price.updatedAt, DateTime(2026, 4, 28));
    });

    test('prezzi null se assenti', () {
      final price = PokemonPrice.fromMap({'print_id': 1, 'language': 'EN'});
      expect(price.cardmarketPrice, isNull);
      expect(price.tcgplayerPrice, isNull);
    });

    test('round-trip toMap → fromMap', () {
      final original = PokemonPrice.fromMap(fullMap);
      final rt = PokemonPrice.fromMap(original.toMap());
      expect(rt.printId, original.printId);
      expect(rt.language, original.language);
      expect(rt.cardmarketPrice, original.cardmarketPrice);
      expect(rt.tcgplayerPrice, original.tcgplayerPrice);
    });
  });
}
