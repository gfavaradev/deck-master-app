import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `onepiece_prints.card_set_id` è UNIQUE, quindi quando il rebuild del
/// 03/09/2026 ha sostituito il seriale surrogato ("OP01-244442") con quello
/// vero ("OP01-064") la stampa nuova entra come riga NUOVA invece di aggiornare
/// quella esistente. Senza pulizia la stessa carta comparirebbe due volte in
/// catalogo, una col numero vero e una con l'id del blueprint.
void main() {
  late DatabaseHelper helper;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_op_stale_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    helper = DatabaseHelper();
    db = await helper.database;
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('onepiece_prints');
    await db.delete('onepiece_cards');
  });

  Future<void> oldPrint(int cardId, String cardSetId) => db.insert(
        'onepiece_prints',
        {
          'card_id': cardId,
          'card_set_id': cardSetId,
          'set_id': cardSetId.split('-').first,
          'created_at': '2026-08-01',
          'updated_at': '2026-08-01',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<String>> setIdsFor(int cardId) async {
    final rows = await db.query('onepiece_prints',
        where: 'card_id = ?', whereArgs: [cardId], orderBy: 'card_set_id');
    return rows.map((r) => r['card_set_id'] as String).toList();
  }

  test('la stampa col vecchio seriale sparisce quando arriva quella vera', () async {
    await oldPrint(77, 'OP01-244442');
    await helper.insertOnepieceCards([
      {
        'id': 77,
        'name': 'Alvida',
        'prints': [
          {
            'card_set_id': 'OP01-064',
            'blueprint_id': '244442',
            'set_id': 'OP01',
            'set_name': 'Romance Dawn',
          },
        ],
      },
    ]);

    expect(await setIdsFor(77), ['OP01-064']);
  });

  test('una carta non ancora aggiornata non viene toccata', () async {
    // Un download interrotto non deve svuotare il catalogo di chi resta indietro.
    await oldPrint(88, 'OP02-244500');
    await oldPrint(77, 'OP01-244442');
    await helper.insertOnepieceCards([
      {
        'id': 77,
        'name': 'Alvida',
        'prints': [
          {'card_set_id': 'OP01-064', 'blueprint_id': '244442', 'set_id': 'OP01'},
        ],
      },
    ]);

    expect(await setIdsFor(77), ['OP01-064']);
    expect(await setIdsFor(88), ['OP02-244500']);
  });

  test('una stampa il cui seriale non cambia viene aggiornata sul posto', () async {
    // I promo senza collector number su CardTrader tengono il seriale
    // surrogato: la riga è la stessa, riceve solo il blueprint_id.
    await oldPrint(99, 'PROMO-244185');
    await helper.insertOnepieceCards([
      {
        'id': 99,
        'name': 'Promotion Pack',
        'prints': [
          {'card_set_id': 'PROMO-244185', 'blueprint_id': '244185', 'set_id': 'PROMO'},
        ],
      },
    ]);

    expect(await setIdsFor(99), ['PROMO-244185']);
    final rows = await db.query('onepiece_prints', where: 'card_id = 99');
    expect(rows.single['blueprint_id'], '244185');
  });
}
