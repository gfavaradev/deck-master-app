import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Percorso completo di un catalogo generico: dalla carta come la pubblica il
/// worker fino alle colonne che la griglia legge.
///
/// Copre due sintomi che l'utente vedeva insieme e che avevano cause diverse:
/// in catalogo compariva un id numerico al posto del seriale, e le carte non
/// avevano immagine. Il primo era del worker (nessun `card_number`), il secondo
/// dell'app: `insertGenericCatalogCards` non mappava `image_url`, quindi la
/// colonna restava NULL qualunque cosa arrivasse.
void main() {
  late DatabaseHelper helper;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_generic_fields_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    helper = DatabaseHelper();
    db = await helper.database;
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('lorcana_cards');
  });

  // Carta reale, letta da lorcana_catalog dopo il rebuild del 03/09/2026.
  final rebuilt = {
    'id': 1,
    'api_id': '258453',
    'blueprint_id': '258453',
    'name': 'Mickey Mouse - Wayward Sorcerer',
    'card_type': null,
    'rarity': 'Enchanted',
    'set_code': 'ch1',
    'set_name': 'The First Chapter',
    'card_number': '208/204',
    'image_url':
        'https://www.cardtrader.com/uploads/blueprints/image/258453/mickey-mouse.jpg',
  };

  test('il seriale mostrato è il numero di collezione, non il blueprint', () async {
    await helper.insertGenericCatalogCards('lorcana', [rebuilt]);
    final cards = await helper.getGenericCatalogCards('lorcana');
    expect(cards.single['setCode'], '208/204');
    // L'id resta il blueprint: è la chiave con cui si aggancia il prezzo.
    expect(cards.single['id'], '258453');
  });

  test('l\'immagine arriva fino alla griglia', () async {
    await helper.insertGenericCatalogCards('lorcana', [rebuilt]);
    final cards = await helper.getGenericCatalogCards('lorcana');
    expect(cards.single['artwork'],
        'https://www.cardtrader.com/uploads/blueprints/image/258453/mickey-mouse.jpg');
  });

  test('la rarità non è più nulla', () async {
    await helper.insertGenericCatalogCards('lorcana', [rebuilt]);
    final cards = await helper.getGenericCatalogCards('lorcana');
    expect(cards.single['rarity'], 'Enchanted');
  });

  test('una carta senza numero di collezione ripiega sul blueprint', () async {
    // Alcuni blueprint CardTrader non hanno collector_number (buste, promo):
    // meglio l'id che una riga senza codice.
    await helper.insertGenericCatalogCards('lorcana', [
      {...rebuilt, 'api_id': '999999', 'card_number': null},
    ]);
    final cards = await helper.getGenericCatalogCards('lorcana');
    expect(cards.single['setCode'], '999999');
  });

  test('il printId di una carta flat è il blueprint', () async {
    await helper.insertGenericCatalogCards('lorcana', [rebuilt]);
    expect(
      await helper.resolvePrintId(catalog: 'lorcana', catalogId: '258453'),
      '258453',
    );
  });
}
