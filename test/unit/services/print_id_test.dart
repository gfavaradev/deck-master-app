import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/services/print_id.dart';

/// VETTORI DI CONFORMITÀ — duplicati identici in
/// `deck-master-worker/src/lib/print-id.test.ts`.
///
/// Sono carte reali lette dai chunk catalogo su Firestore il 02/09/2026. Se le
/// due implementazioni divergono su uno solo di questi, il worker pubblica i
/// prezzi sotto chiavi che l'app non cerca e le carte restano senza prezzo:
/// è il contratto che tiene insieme i due repo.
void main() {
  group('printId — conformità con l\'implementazione TypeScript', () {
    test('flat: api_id è il blueprint CardTrader', () {
      expect(
        printIdFromCatalogCard('digimon', {'id': 1, 'api_id': '168145', 'set_code': 'btv1'}),
        '168145',
      );
      expect(
        printIdFromCatalogCard('lorcana', {'id': 1, 'api_id': '258453', 'set_code': 'ch1'}),
        '258453',
      );
      expect(
        printIdFromCatalogCard('star-wars', {'id': 1, 'api_id': '276235', 'set_code': 'sor'}),
        '276235',
      );
      expect(
        printIdFromCatalogCard('gundam', {'id': 1, 'api_id': '341124', 'set_code': 'gd01'}),
        '341124',
      );
      expect(
        printIdFromCatalogCard('union-arena', {'id': 1, 'api_id': '293026', 'set_code': 'ue01bt'}),
        '293026',
      );
    });

    test('pokemon: suffisso di api_id', () {
      expect(printIdFromCatalogCard('pokemon', {'api_id': 'pr1-273488'}), '273488');
    });

    test('onepiece: suffisso di card_set_id', () {
      expect(
        printIdFromCatalogCard(
          'onepiece',
          {'id': 1},
          {'card_set_id': 'UP-244190', 'set_id': 'UP'},
        ),
        '244190',
      );
    });

    test('magic: uuid Scryfall con suffisso di finitura', () {
      expect(
        printIdFromCatalogCard(
          'magic',
          {'api_id': 'a471b306-4941-4e46-a0cb-d92895c16f8a', 'set_code': 'drc'},
        ),
        'a471b306-4941-4e46-a0cb-d92895c16f8a-n',
      );
    });

    test('yugioh: chiave composta da card_id, set_code e rarity_code', () {
      expect(
        printIdFromCatalogCard(
          'yugioh',
          {'id': 80181649, 'name': '"A Case for K9"'},
          {'set_code': 'JUSH-EN040', 'rarity_code': '(StR)'},
        ),
        '80181649-jush-en040-str',
      );
    });
  });

  group('normalizeKey', () {
    test('nessun carattere vietato da RTDB', () {
      expect(normalizeKey('(StR)'), 'str');
      expect(normalizeKey('LOB-EN001'), 'lob-en001');
      expect(normalizeKey('  Quarter/Dot.Hash#  '), 'quarter-dot-hash');
      expect(normalizeKey(r'a$b[c]d'), 'a-b-c-d');
      expect(normalizeKey(null), '');
    });

    test('mai trattini ai bordi, mai caratteri fuori alfabeto', () {
      for (final s in ['a.b', r'a$b', 'a#b', 'a[b]', 'a/b', '--x--']) {
        final k = normalizeKey(s);
        expect(RegExp(r'^[a-z0-9_-]*$').hasMatch(k), isTrue, reason: s);
        expect(k.startsWith('-'), isFalse, reason: s);
        expect(k.endsWith('-'), isFalse, reason: s);
      }
    });
  });

  group('blueprintFromCompositeId', () {
    test('estrae il blueprint solo se il suffisso è numerico', () {
      expect(blueprintFromCompositeId('UP-244190'), '244190');
      expect(blueprintFromCompositeId('pr1-273488'), '273488');
      expect(blueprintFromCompositeId('168145'), '168145');
      // set_code con trattino ma suffisso non numerico: non è un blueprint
      expect(blueprintFromCompositeId('OP01-EN001'), 'op01-en001');
      expect(blueprintFromCompositeId(''), '');
      expect(blueprintFromCompositeId(null), '');
    });
  });

  group('printIdFromBlueprint', () {
    test('join esatto per i cataloghi con blueprint', () {
      expect(printIdFromBlueprint('digimon', 168145), '168145');
      expect(printIdFromBlueprint('pokemon', '273488'), '273488');
      expect(printIdFromBlueprint('onepiece', 244190), '244190');
    });

    test('vuoto per yugioh, per lo zero e per valori non numerici', () {
      expect(printIdFromBlueprint('yugioh', 76700), '');
      expect(printIdFromBlueprint('digimon', 0), '');
      expect(printIdFromBlueprint('digimon', 'non-numerico'), '');
    });
  });

  group('famiglie', () {
    test('i 13 cataloghi sono mappati, nessuno cade nel default per errore', () {
      expect(familyOf('yugioh'), PrintFamily.yugioh);
      expect(familyOf('pokemon'), PrintFamily.pokemon);
      expect(familyOf('onepiece'), PrintFamily.onepiece);
      expect(familyOf('magic'), PrintFamily.magic);
      for (final c in [
        'digimon', 'lorcana', 'flesh-and-blood', 'vanguard',
        'dragon-ball-super', 'star-wars', 'riftbound', 'gundam', 'union-arena',
      ]) {
        expect(familyOf(c), PrintFamily.flat, reason: c);
      }
    });
  });

  group('codici espansione per il path RTDB', () {
    test('pokemon e yugioh', () {
      expect(pokemonSetCode('pr1-273488'), 'pr1');
      expect(pokemonSetCode('sv3pt5-12345'), 'sv3pt5');
      expect(yugiohSetCode('JUSH-EN040'), 'jush');
      expect(yugiohSetCode('LOB'), 'lob');
    });
  });

  group('casi limite', () {
    test('magic: normale e foil sono chiavi distinte', () {
      const id = 'a471b306-4941-4e46-a0cb-d92895c16f8a';
      expect(magicPrintId(id, foil: false), '$id-n');
      expect(magicPrintId(id, foil: true), '$id-f');
      expect(magicPrintId('', foil: false), '');
    });

    test('yugioh: rarity_code mancante non lascia trattini penzolanti', () {
      expect(yugiohPrintId(80181649, 'JUSH-EN040', '(StR)'), '80181649-jush-en040-str');
      expect(yugiohPrintId(12345, 'LOB-EN001', ''), '12345-lob-en001');
      expect(yugiohPrintId(12345, 'LOB-EN001', null), '12345-lob-en001');
    });
  });
}
