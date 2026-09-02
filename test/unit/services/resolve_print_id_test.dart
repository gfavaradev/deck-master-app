import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `resolvePrintId` è il ponte fra una carta posseduta e i prezzi pubblicati
/// dal worker: se sbaglia, la carta resta senza prezzo (o peggio, ne prende uno
/// di un'altra stampa). Questi test lo fissano sulle forme reali dei cataloghi,
/// lette da Firestore il 02/09/2026.
void main() {
  late DatabaseHelper helper;
  late Database db;

  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // DatabaseHelper apre sempre `deck_master.db` sotto getDatabasesPath(): con
    // una directory di default condivisa, questo file di test e
    // cardtrader_price_match_test.dart (che cancella lo stesso file in setUpAll)
    // si contendono lo stesso database quando `flutter test` li esegue insieme.
    // Una directory dedicata per file di test li rende indipendenti.
    tempDir = await Directory.systemTemp.createTemp('dm_resolve_print_id_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    helper = DatabaseHelper();
    db = await helper.database;
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('flat — api_id è già il blueprint', () {
    test('catalogId contiene direttamente il blueprint, nessuna query', () async {
      // getGenericCatalogCards espone `api_id AS id`, quindi la collezione
      // salva già il blueprint in catalogId.
      expect(
        await helper.resolvePrintId(catalog: 'digimon', catalogId: '168145'),
        '168145',
      );
      expect(
        await helper.resolvePrintId(catalog: 'lorcana', catalogId: '258453'),
        '258453',
      );
    });

    test('id locale invece del blueprint: si risale via api_id', () async {
      await db.insert('digimon_cards', {
        'id': 7,
        'api_id': '168145',
        'name': 'Yokomon',
        'set_code': 'btv1',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect(
        await helper.resolvePrintId(catalog: 'digimon', catalogId: '7'),
        '168145',
      );
    });

    test('carta non in catalogo locale: si usa l\'id cosi\' com\'e\'', () async {
      // Puo' essere il blueprint di una carta che il catalogo locale non ha
      // ancora: il lookup semplicemente non trovera' un prezzo.
      expect(
        await helper.resolvePrintId(catalog: 'digimon', catalogId: '999999999'),
        '999999999',
      );
    });

    test('senza catalogId non si inventa una chiave', () async {
      expect(await helper.resolvePrintId(catalog: 'digimon'), '');
      expect(
        await helper.resolvePrintId(catalog: 'digimon', catalogId: 'non-numerico'),
        '',
      );
    });
  });

  group('onepiece — il blueprint sta nel seriale', () {
    test('serialNumber "UP-244190" ⇒ 244190', () async {
      expect(
        await helper.resolvePrintId(
          catalog: 'onepiece',
          catalogId: '12',
          serialNumber: 'UP-244190',
        ),
        '244190',
      );
    });

    test('seriale senza blueprint: si passa dalle stampe locali', () async {
      await db.insert('onepiece_cards', {
        'id': 55,
        'name': 'Monkey D. Luffy',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('onepiece_prints', {
        'card_id': 55,
        'card_set_id': 'OP01-244191',
        'set_id': 'OP01',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect(
        await helper.resolvePrintId(
          catalog: 'onepiece',
          catalogId: '55',
          serialNumber: '',
        ),
        '244191',
      );
    });
  });

  group('onepiece — dal rebuild 03/09/2026 il seriale è vero', () {
    // Il catalogo pubblicato fino al 03/09/2026 metteva l'id del blueprint nel
    // seriale ("OP01-244442": 2407 stampe su 2407), e il printId lo estraeva da
    // lì. Col seriale vero ("OP01-064") quella deduzione darebbe "064", cioè il
    // prezzo di nessuna carta: il blueprint arriva esplicito in una colonna sua.
    test('seriale vero: il blueprint viene dalla colonna, non dal seriale', () async {
      await db.insert('onepiece_cards', {
        'id': 77,
        'name': 'Alvida',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('onepiece_prints', {
        'card_id': 77,
        'card_set_id': 'OP01-064',
        'blueprint_id': '244442',
        'set_id': 'OP01',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect(
        await helper.resolvePrintId(
          catalog: 'onepiece',
          catalogId: '77',
          serialNumber: 'OP01-064',
        ),
        '244442',
      );
    });

    test('mai il numero di collezione scambiato per un blueprint', () async {
      // Nessuna stampa in tabella: meglio nessun prezzo che il prezzo del
      // blueprint 64, che è una carta di tutt'altro gioco.
      expect(
        await helper.resolvePrintId(
          catalog: 'onepiece',
          catalogId: '999',
          serialNumber: 'OP05-118',
        ),
        '',
      );
    });
  });

  group('pokemon — api_id "pr1-273488"', () {
    test('si risale al blueprint sia da id locale sia da api_id', () async {
      await db.insert('pokemon_cards', {
        'id': 31,
        'api_id': 'pr1-273488',
        'name': 'Zapdos',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect(
        await helper.resolvePrintId(catalog: 'pokemon', catalogId: '31'),
        '273488',
      );
      expect(
        await helper.resolvePrintId(catalog: 'pokemon', catalogId: 'pr1-273488'),
        '273488',
      );
    });
  });

  group('yugioh — chiave composita, seriale localizzato', () {
    setUpAll(() async {
      await db.insert('yugioh_cards', {
        'id': 80181649,
        'name': 'A Case for K9',
        'type': 'Spell Card',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Stessa carta, stesso set, DUE rarità: prezzi molto diversi, quindi la
      // rarità posseduta deve poter discriminare.
      await db.insert('yugioh_prints', {
        'card_id': 80181649,
        'set_code': 'JUSH-EN040',
        'rarity': 'Starlight Rare',
        'rarity_code': '(StR)',
        'set_code_it': 'JUSH-IT040',
        'rarity_it': 'Rara Starlight',
        'rarity_code_it': '(StR)',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('yugioh_prints', {
        'card_id': 80181649,
        'set_code': 'JUSH-EN040',
        'rarity': 'Common',
        'rarity_code': '(C)',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    test('seriale inglese + rarità ⇒ chiave della stampa giusta', () async {
      expect(
        await helper.resolvePrintId(
          catalog: 'yugioh',
          catalogId: '80181649',
          serialNumber: 'JUSH-EN040',
          rarity: 'Starlight Rare',
        ),
        '80181649-jush-en040-str',
      );
    });

    test('la rarità discrimina fra stampe con lo stesso set_code', () async {
      expect(
        await helper.resolvePrintId(
          catalog: 'yugioh',
          catalogId: '80181649',
          serialNumber: 'JUSH-EN040',
          rarity: 'Common',
        ),
        '80181649-jush-en040-c',
      );
    });

    test('seriale italiano: si cerca sulle colonne della lingua', () async {
      expect(
        await helper.resolvePrintId(
          catalog: 'yugioh',
          catalogId: '80181649',
          serialNumber: 'JUSH-IT040',
          rarity: 'Rara Starlight',
        ),
        '80181649-jush-it040-str',
      );
    });

    test('rarità che non combacia: ripiega su una stampa dello stesso seriale', () async {
      final id = await helper.resolvePrintId(
        catalog: 'yugioh',
        catalogId: '80181649',
        serialNumber: 'JUSH-EN040',
        rarity: 'Rarità Inventata',
      );
      expect(id, startsWith('80181649-jush-en040'));
    });

    test('seriale sconosciuto ⇒ vuoto', () async {
      expect(
        await helper.resolvePrintId(
          catalog: 'yugioh',
          catalogId: '80181649',
          serialNumber: 'XXXX-EN999',
        ),
        '',
      );
      // Senza seriale la stampa non è determinabile: meglio nessun prezzo che
      // il prezzo di un'altra stampa.
      expect(
        await helper.resolvePrintId(catalog: 'yugioh', catalogId: '80181649'),
        '',
      );
    });
  });

  group('magic — uuid Scryfall', () {
    test('uuid passa senza query, con suffisso di finitura', () async {
      expect(
        await helper.resolvePrintId(
          catalog: 'magic',
          catalogId: 'a471b306-4941-4e46-a0cb-d92895c16f8a',
        ),
        'a471b306-4941-4e46-a0cb-d92895c16f8a-n',
      );
    });

    test('id locale: si risale all\'uuid via api_id', () async {
      await db.insert('magic_cards', {
        'id': 4,
        'api_id': 'a471b306-4941-4e46-a0cb-d92895c16f8a',
        'name': 'Nissa, Worldsoul Speaker',
        'created_at': '2026-09-02',
        'updated_at': '2026-09-02',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect(
        await helper.resolvePrintId(catalog: 'magic', catalogId: '4'),
        'a471b306-4941-4e46-a0cb-d92895c16f8a-n',
      );
    });
  });

  group('card_prices — lettura per chiave', () {
    test('scrittura e lookup per printId e lingua', () async {
      await helper.replaceSetPrices('digimon', 'btv1', [
        {
          'catalog': 'digimon',
          'print_id': '168145',
          'set_code': 'btv1',
          'lang': 'en',
          'nm_cents': 500,
          'any_cents': 400,
          'listings': 3,
        },
        {
          'catalog': 'digimon',
          'print_id': '168145',
          'set_code': 'btv1',
          'lang': 'it',
          'nm_cents': null,
          'any_cents': 250,
          'listings': 1,
        },
      ]);

      final en = await helper.getUnifiedPrice(
          catalog: 'digimon', printId: '168145', lang: 'en');
      expect(en?['nm_cents'], 500);

      final all = await helper.getUnifiedPricesForPrint(
          catalog: 'digimon', printId: '168145');
      expect(all.length, 2);
      expect(await helper.countUnifiedPrices('digimon'), 2);
    });

    test('un nuovo sync del set sostituisce i prezzi, non li accumula', () async {
      await helper.replaceSetPrices('digimon', 'btv1', [
        {
          'catalog': 'digimon',
          'print_id': '168146',
          'set_code': 'btv1',
          'lang': 'en',
          'nm_cents': 900,
          'any_cents': 900,
          'listings': 1,
        },
      ]);
      // Le righe precedenti del set spariscono: una stampa uscita dal listino
      // non deve restare con un prezzo fossile.
      expect(await helper.countUnifiedPrices('digimon'), 1);
      expect(
        await helper.getUnifiedPrice(
            catalog: 'digimon', printId: '168145', lang: 'en'),
        isNull,
      );
    });

    test('le versioni dei set sopravvivono e guidano il prossimo sync', () async {
      await helper.setPriceSetVersion('digimon', 'btv1', 12);
      await helper.setPriceSetVersion('digimon', 'bt5', 3);
      final versions = await helper.getPriceSetVersions('digimon');
      expect(versions, {'btv1': 12, 'bt5': 3});
    });
  });

  group('set posseduti — il sync scarica solo quelli', () {
    // Senza questo filtro `_syncCatalog` scaricava TUTTI i set del catalogo:
    // 490 letture RTDB per Yu-Gi-Oh a ogni bump di versione, contro le poche
    // che servono a chi possiede tre buste.
    setUp(() async {
      await db.delete('cards');
    });

    Future<void> addCard(String collection, String catalogId, String serial) =>
        db.insert('cards', {
          'name': 'x',
          'serialNumber': serial,
          'collection': collection,
          'catalogId': catalogId,
          'quantity': 1,
          'value': 0.0,
          'rarity': '',
          'added_at': '2026-09-03',
        });

    test('yugioh e onepiece: il codice sta nel seriale', () async {
      await addCard('yugioh', '80181649', 'JUSH-IT040');
      await addCard('yugioh', '10202894', 'LOB-EN105');
      await addCard('yugioh', '10202894', 'LOB-EN106');
      await addCard('onepiece', '77', 'OP01-064');

      expect(await helper.getOwnedSetCodes('yugioh'), {'jush', 'lob'});
      expect(await helper.getOwnedSetCodes('onepiece'), {'op01'});
    });

    test('pokemon: il codice sta nel prefisso di api_id', () async {
      await db.insert('pokemon_cards', {
        'id': 90,
        'api_id': 'pr1-273488',
        'name': 'Zapdos',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await addCard('pokemon', 'pr1-273488', '15/62');

      expect(await helper.getOwnedSetCodes('pokemon'), {'pr1'});
    });

    test('flat: il codice sta sulla carta di catalogo', () async {
      await db.insert('lorcana_cards', {
        'id': 5,
        'api_id': '258453',
        'name': 'Mickey Mouse',
        'set_code': 'ch1',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await addCard('lorcana', '258453', '208/204');

      expect(await helper.getOwnedSetCodes('lorcana'), {'ch1'});
    });

    test('collezione vuota ⇒ insieme vuoto, cioè "scarica tutto"', () async {
      // Vuoto non vuol dire "nessun set": vuol dire che il criterio non sa
      // rispondere, e chi chiama deve scaricare tutto invece di niente.
      expect(await helper.getOwnedSetCodes('vanguard'), isEmpty);
      expect(await helper.getOwnedSetCodes('yugioh'), isEmpty);
    });
  });
}
