import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Il valore della collezione esce tutto da una CTE sola (`card_values`), usata
/// dal totale, dalle statistiche per collezione e per rarità e dallo snapshot
/// storico. Fino al 03/09/2026 quella CTE era l'unione di tre SELECT su
/// yugioh/onepiece/pokemon: le carte degli altri dieci cataloghi non
/// comparivano affatto e valevano zero, anche quando la riga in lista un prezzo
/// ce l'aveva. Questi test tengono la CTE onesta.
void main() {
  late DatabaseHelper helper;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_collection_value_');
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

  Future<void> addCard(
    String collection, {
    double? ctValue,
    double value = 0.0,
    int quantity = 1,
    String serial = '',
    String catalogId = '1',
  }) =>
      db.insert('cards', {
        'name': 'carta',
        'serialNumber': serial,
        'collection': collection,
        'catalogId': catalogId,
        'quantity': quantity,
        'value': value,
        'cardtrader_value': ctValue,
        'rarity': 'Rare',
        'added_at': '2026-09-03',
      });

  test('i cataloghi senza tabelle di stampa contano nel totale', () async {
    await addCard('digimon', ctValue: 3.50);
    await addCard('lorcana', ctValue: 1.25, quantity: 4);
    await addCard('flesh-and-blood', ctValue: 10.0);

    final stats = await helper.getGlobalStats();
    expect(stats['totalValue'], closeTo(3.50 + 5.00 + 10.0, 0.001));
  });

  test('per collezione: nessun catalogo sparisce dal raggruppamento', () async {
    await addCard('digimon', ctValue: 2.0);
    await addCard('magic', value: 7.0);
    await addCard('yugioh', ctValue: 1.0, serial: 'LOB-EN001');

    final rows = await helper.getStatsPerCollection();
    final byCollection = {
      for (final r in rows)
        r['collection'] as String: (r['totalValue'] as num).toDouble(),
    };
    expect(byCollection['digimon'], closeTo(2.0, 0.001));
    expect(byCollection['magic'], closeTo(7.0, 0.001));
    expect(byCollection['yugioh'], closeTo(1.0, 0.001));
  });

  test('cardtrader_value ha la precedenza sull\'istantanea di acquisto', () async {
    // `value` è il prezzo di catalogo copiato quando la carta è stata aggiunta e
    // non si aggiorna più: se prevalesse, una collezione tenuta a lungo
    // mostrerebbe prezzi di due anni fa.
    await addCard('lorcana', ctValue: 12.0, value: 3.0);

    final stats = await helper.getGlobalStats();
    expect(stats['totalValue'], closeTo(12.0, 0.001));
  });

  test('senza prezzo di mercato si ripiega su value, poi su zero', () async {
    await addCard('vanguard', value: 4.5);
    await addCard('gundam');

    final stats = await helper.getGlobalStats();
    expect(stats['totalValue'], closeTo(4.5, 0.001));
  });

  test('il filtro per collezione resta valido', () async {
    await addCard('digimon', ctValue: 2.0);
    await addCard('lorcana', ctValue: 5.0);

    final stats = await helper.getGlobalStats(collection: 'lorcana');
    expect(stats['totalValue'], closeTo(5.0, 0.001));
    expect(stats['totalCards'], 1);
  });

  test('statistiche per rarità: anche qui i dieci cataloghi contano', () async {
    await addCard('digimon', ctValue: 2.0);
    final rows = await helper.getStatsPerRarity(collection: 'digimon');
    expect(rows, isNotEmpty);
    expect((rows.first['totalValue'] as num).toDouble(), closeTo(2.0, 0.001));
  });
}
