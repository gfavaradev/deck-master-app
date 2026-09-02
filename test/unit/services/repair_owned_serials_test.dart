import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fino al 03/09/2026 i cataloghi mettevano l'id del blueprint CardTrader dove
/// l'app mostra il seriale, perché il rebuild leggeva un endpoint che non
/// espone il collector number. Le carte aggiunte in quel periodo hanno copiato
/// quel finto seriale nella collezione: ricostruire il catalogo corregge lo
/// scaffale ma non ciò che l'utente possiede.
///
/// La riparazione è ammessa solo perché la corrispondenza è esatta e
/// deterministica: il vecchio seriale ERA l'id del blueprint (o
/// "{set}-{blueprint}"), quindi si riconosce senza ambiguità la riga da
/// correggere. Tutto ciò che non combacia resta com'è.
void main() {
  late DatabaseHelper helper;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_repair_serials_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    helper = DatabaseHelper();
    db = await helper.database;
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('cards');
  });

  Future<int> addCard(String collection, String catalogId, String serial) =>
      db.insert('cards', {
        'name': 'carta',
        'serialNumber': serial,
        'collection': collection,
        'catalogId': catalogId,
        'quantity': 1,
        'value': 0.0,
        'rarity': '',
        'added_at': '2026-09-03',
      });

  Future<String?> serialOf(int id) async {
    final rows = await db.query('cards', where: 'id = ?', whereArgs: [id]);
    return rows.first['serialNumber'] as String?;
  }

  group('flat — il seriale era api_id, cioè il blueprint', () {
    setUp(() async {
      await db.insert('lorcana_cards', {
        'id': 5,
        'api_id': '258453',
        'name': 'Mickey Mouse',
        'set_code': 'ch1',
        'card_number': '208/204',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    test('il blueprint diventa il numero di collezione vero', () async {
      final id = await addCard('lorcana', '258453', '258453');
      expect(await helper.repairOwnedSerials('lorcana'), 1);
      expect(await serialOf(id), '208/204');
    });

    test('un seriale già buono non viene toccato', () async {
      final id = await addCard('lorcana', '258453', '208/204');
      expect(await helper.repairOwnedSerials('lorcana'), 0);
      expect(await serialOf(id), '208/204');
    });

    test('senza numero di collezione in catalogo non si inventa nulla', () async {
      await db.insert('lorcana_cards', {
        'id': 6,
        'api_id': '999999',
        'name': 'Senza numero',
        'set_code': 'ch1',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final id = await addCard('lorcana', '999999', '999999');
      expect(await helper.repairOwnedSerials('lorcana'), 0);
      expect(await serialOf(id), '999999');
    });
  });

  group('pokemon — il seriale era il blueprint nudo', () {
    setUp(() async {
      await db.insert('pokemon_cards', {
        'id': 90,
        'api_id': 'pr1-273488',
        'name': 'Zapdos',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('pokemon_prints', {
        'card_id': 90,
        'set_code': '15/62 ©1999',
        'set_name': 'WOTC Promos',
        'created_at': '2026-09-03',
        'updated_at': '2026-09-03',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    test('"273488" diventa il collector number della stampa', () async {
      final id = await addCard('pokemon', 'pr1-273488', '273488');
      expect(await helper.repairOwnedSerials('pokemon'), 1);
      expect(await serialOf(id), '15/62 ©1999');
    });

    test('un seriale che non è il blueprint di quella carta resta intatto', () async {
      final id = await addCard('pokemon', 'pr1-273488', '99/62');
      expect(await helper.repairOwnedSerials('pokemon'), 0);
      expect(await serialOf(id), '99/62');
    });
  });

  group('onepiece — il seriale era "{set}-{blueprint}"', () {
    setUp(() async {
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
    });

    test('"OP01-244442" diventa "OP01-064"', () async {
      final id = await addCard('onepiece', '77', 'OP01-244442');
      expect(await helper.repairOwnedSerials('onepiece'), 1);
      expect(await serialOf(id), 'OP01-064');
    });

    test('il seriale nuovo non viene riscritto una seconda volta', () async {
      final id = await addCard('onepiece', '77', 'OP01-064');
      expect(await helper.repairOwnedSerials('onepiece'), 0);
      expect(await serialOf(id), 'OP01-064');
    });

    test('un set diverso con lo stesso numero non viene confuso', () async {
      final id = await addCard('onepiece', '77', 'OP05-244442');
      expect(await helper.repairOwnedSerials('onepiece'), 0);
      expect(await serialOf(id), 'OP05-244442');
    });
  });

  test('cataloghi senza riparazione: nessuna modifica e nessun errore', () async {
    final id = await addCard('magic', 'uuid-1', '13');
    expect(await helper.repairOwnedSerials('magic'), 0);
    expect(await helper.repairOwnedSerials('yugioh'), 0);
    expect(await serialOf(id), '13');
  });
}
