import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:deck_master/services/price_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `updateCollectionValues` scrive `cardtrader_value`, la colonna da cui
/// dipendono sia il totale in lista (`card_list_page._getEffectiveValue`) sia
/// le statistiche SQL. Fino a questo fix guardava solo la tabella unificata
/// `card_prices`: una carta il cui prezzo esiste solo nelle tabelle di stampa
/// del catalogo (`yugioh_prints.set_price` e affini — il terzo ripiego di
/// `CardtraderService.getPriceForCard`) restava con `cardtrader_value` nullo,
/// mostrando un prezzo in riga e zero nel totale.
void main() {
  late DatabaseHelper helper;
  late PriceSyncService service;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_price_sync_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    helper = DatabaseHelper();
    db = await helper.database;
    // Nessun `repository` iniettato: se il costruttore toccasse Firebase qui
    // il test fallirebbe all'avvio, prima ancora di arrivare alle asserzioni.
    service = PriceSyncService(database: helper);
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('cards');
    await db.delete('yugioh_prints');
    await db.delete('yugioh_cards');
    await db.delete('card_prices');
  });

  test('ripiega sul prezzo incorporato nella tabella di stampa quando '
      'card_prices non ha ancora la riga', () async {
    await db.insert('yugioh_cards', {
      'id': 500,
      'type': 'Effect Monster',
      'name': 'Kuriboh Test',
    });
    await db.insert('yugioh_prints', {
      'card_id': 500,
      'set_code': 'LOB-EN020',
      'rarity': 'Common',
      'set_price': 1.20,
    });
    final cardId = await db.insert('cards', {
      'name': 'Kuriboh Test',
      'collection': 'yugioh',
      'catalogId': '500',
      'serialNumber': 'LOB-EN020',
      'rarity': 'Common',
      'quantity': 1,
      'value': 0.0,
      'cardtrader_value': null,
      'added_at': '2026-09-09',
    });

    final updated = await service.updateCollectionValues('yugioh');

    expect(updated, 1);
    final row = (await db.query('cards', where: 'id = ?', whereArgs: [cardId])).first;
    expect((row['cardtrader_value'] as num).toDouble(), closeTo(1.20, 0.001));
  });

  test('la tabella unificata resta prioritaria quando ha un prezzo', () async {
    await db.insert('yugioh_cards', {
      'id': 501,
      'type': 'Effect Monster',
      'name': 'Altra Carta',
    });
    await db.insert('yugioh_prints', {
      'card_id': 501,
      'set_code': 'LOB-EN021',
      'rarity': 'Common',
      'set_price': 1.20,
    });
    await db.insert('card_prices', {
      'catalog': 'yugioh',
      'print_id': '501-lob-en021',
      'lang': 'en',
      'nm_cents': 900,
      'any_cents': 900,
      'listings': 3,
    });
    final cardId = await db.insert('cards', {
      'name': 'Altra Carta',
      'collection': 'yugioh',
      'catalogId': '501',
      'serialNumber': 'LOB-EN021',
      'rarity': 'Common',
      'quantity': 1,
      'value': 0.0,
      'cardtrader_value': null,
      'added_at': '2026-09-09',
    });

    await service.updateCollectionValues('yugioh');

    final row = (await db.query('cards', where: 'id = ?', whereArgs: [cardId])).first;
    // 9.00 dalla tabella unificata, non 1.20 dalla tabella di stampa.
    expect((row['cardtrader_value'] as num).toDouble(), closeTo(9.00, 0.001));
  });

  test('senza prezzo in nessuna delle due fonti non tocca la carta', () async {
    await db.insert('yugioh_cards', {
      'id': 502,
      'type': 'Effect Monster',
      'name': 'Senza Prezzo',
    });
    await db.insert('yugioh_prints', {
      'card_id': 502,
      'set_code': 'LOB-EN022',
      'rarity': 'Common',
    });
    await db.insert('cards', {
      'name': 'Senza Prezzo',
      'collection': 'yugioh',
      'catalogId': '502',
      'serialNumber': 'LOB-EN022',
      'rarity': 'Common',
      'quantity': 1,
      'value': 0.0,
      'cardtrader_value': null,
      'added_at': '2026-09-09',
    });

    final updated = await service.updateCollectionValues('yugioh');

    expect(updated, 0);
  });
}
