import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/pokemon_models.dart';

void main() {
  group('PokemonCard', () {
    PokemonCard makeCard({
      String name = 'Charizard',
      String? nameIt = 'Charizard IT',
      String? nameFr = 'Charizard FR',
      String? nameDe = 'Charizard DE',
      String? namePt = 'Charizard PT',
    }) =>
        PokemonCard(
          id: 1,
          apiId: 'base1-4',
          name: name,
          supertype: 'Pokémon',
          rarity: 'Rare Holo',
          setId: 'base1',
          setName: 'Base Set',
          number: '4',
          nameIt: nameIt,
          nameFr: nameFr,
          nameDe: nameDe,
          namePt: namePt,
        );

    // ── getLocalizedName ──────────────────────────────────────────────────
    group('getLocalizedName', () {
      test('IT restituisce nameIt', () {
        expect(makeCard().getLocalizedName('IT'), 'Charizard IT');
      });

      test('it (lowercase) restituisce nameIt', () {
        expect(makeCard().getLocalizedName('it'), 'Charizard IT');
      });

      test('FR restituisce nameFr', () {
        expect(makeCard().getLocalizedName('FR'), 'Charizard FR');
      });

      test('DE restituisce nameDe', () {
        expect(makeCard().getLocalizedName('DE'), 'Charizard DE');
      });

      test('PT restituisce namePt', () {
        expect(makeCard().getLocalizedName('PT'), 'Charizard PT');
      });

      test('EN restituisce name base', () {
        expect(makeCard().getLocalizedName('EN'), 'Charizard');
      });

      test('lingua sconosciuta → name base', () {
        expect(makeCard().getLocalizedName('ZH'), 'Charizard');
      });

      test('fallback a name base se nameIt è null', () {
        final card = makeCard(nameIt: null);
        expect(card.getLocalizedName('IT'), 'Charizard');
      });

      test('fallback a name base se nameFr è null', () {
        final card = makeCard(nameFr: null);
        expect(card.getLocalizedName('FR'), 'Charizard');
      });
    });

    // ── toMap / fromMap round-trip ────────────────────────────────────────
    group('serializzazione', () {
      test('toMap include tutti i campi rilevanti', () {
        final card = makeCard();
        final map = card.toMap();
        expect(map['id'], 1);
        expect(map['api_id'], 'base1-4');
        expect(map['name'], 'Charizard');
        expect(map['name_it'], 'Charizard IT');
        expect(map['name_fr'], 'Charizard FR');
        expect(map['name_de'], 'Charizard DE');
        expect(map['name_pt'], 'Charizard PT');
        expect(map['set_id'], 'base1');
        expect(map['set_name'], 'Base Set');
      });

      test('fromMap round-trip preserva i dati', () {
        final original = makeCard();
        final rt = PokemonCard.fromMap(original.toMap());
        expect(rt.id, original.id);
        expect(rt.apiId, original.apiId);
        expect(rt.name, original.name);
        expect(rt.nameIt, original.nameIt);
        expect(rt.nameFr, original.nameFr);
        expect(rt.nameDe, original.nameDe);
        expect(rt.namePt, original.namePt);
        expect(rt.setId, original.setId);
      });

      test('fromMap con campi opzionali null', () {
        final card = PokemonCard.fromMap({
          'id': 5,
          'api_id': 'xy1-1',
          'name': 'Pikachu',
        });
        expect(card.id, 5);
        expect(card.name, 'Pikachu');
        expect(card.nameIt, isNull);
        expect(card.hp, isNull);
        expect(card.rarity, isNull);
      });
    });
  });

  // ── PokemonPrint ──────────────────────────────────────────────────────────
  group('PokemonPrint', () {
    final fullMap = {
      'id': 1,
      'card_id': 10,
      'set_code': 'base1-4',
      'set_name': 'Base Set',
      'rarity': 'Rare Holo',
      'set_price': 50.0,
      'artwork': 'https://img.url/art.jpg',
      'set_code_it': 'it1-4',
      'set_name_it': 'Set Base',
      'rarity_it': 'Olografica Rara',
      'set_price_it': 45.0,
    };

    test('fromMap parsa tutti i campi', () {
      final print = PokemonPrint.fromMap(fullMap);
      expect(print.id, 1);
      expect(print.cardId, 10);
      expect(print.setCode, 'base1-4');
      expect(print.setName, 'Base Set');
      expect(print.rarity, 'Rare Holo');
      expect(print.setPrice, 50.0);
      expect(print.artwork, 'https://img.url/art.jpg');
      expect(print.setCodeIt, 'it1-4');
      expect(print.setNameIt, 'Set Base');
      expect(print.rarityIt, 'Olografica Rara');
      expect(print.setPriceIt, 45.0);
    });

    test('toMap → fromMap round-trip', () {
      final original = PokemonPrint.fromMap(fullMap);
      final rt = PokemonPrint.fromMap(original.toMap());
      expect(rt.setCode, original.setCode);
      expect(rt.setPrice, original.setPrice);
      expect(rt.setCodeIt, original.setCodeIt);
      expect(rt.setPriceIt, original.setPriceIt);
    });
  });
}
