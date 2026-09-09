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

  Future<int> addCard(
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

  // getGlobalStats(collection: null) somma solo le collezioni sbloccate (vedi
  // sotto): nella realtà una carta esiste solo in una collezione sbloccata,
  // ma lo schema di test parte con tutte le collezioni bloccate di default.
  Future<void> unlock(String id) =>
      db.update('collections', {'isUnlocked': 1}, where: 'id = ?', whereArgs: [id]);

  test('i cataloghi senza tabelle di stampa contano nel totale', () async {
    await unlock('digimon');
    await unlock('lorcana');
    await unlock('flesh-and-blood');
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
    await unlock('lorcana');
    await addCard('lorcana', ctValue: 12.0, value: 3.0);

    final stats = await helper.getGlobalStats();
    expect(stats['totalValue'], closeTo(12.0, 0.001));
  });

  test('senza prezzo di mercato si ripiega su value, poi su zero', () async {
    await unlock('vanguard');
    await unlock('gundam');
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

  group('quantity NULL conta come 1, non come zero', () {
    // La colonna e' nullable (ALTER TABLE senza DEFAULT su una colonna
    // preesistente): SUM ignora le righe NULL invece di sollevare un errore,
    // quindi contavano zero nel totale mentre CardModel.fromMap (letto dalla
    // lista carte) le mostra a quantita' 1 — il totale non tornava con le
    // righe visibili.
    Future<void> addCardWithNullQuantity(String collection, {double? ctValue}) =>
        db.insert('cards', {
          'name': 'carta',
          'serialNumber': '',
          'collection': collection,
          'catalogId': '1',
          'quantity': null,
          'value': 0.0,
          'cardtrader_value': ctValue,
          'rarity': 'Rare',
          'added_at': '2026-09-03',
        });

    test('getGlobalStats: totale carte e totale valore', () async {
      await addCardWithNullQuantity('digimon', ctValue: 3.0);

      final stats = await helper.getGlobalStats(collection: 'digimon');

      expect(stats['totalCards'], 1);
      expect(stats['totalValue'], closeTo(3.0, 0.001));
    });

    test('getStatsPerCollection', () async {
      await addCardWithNullQuantity('lorcana', ctValue: 5.0);

      final rows = await helper.getStatsPerCollection();
      final lorcana = rows.firstWhere((r) => r['collection'] == 'lorcana');

      expect((lorcana['totalCards'] as num).toInt(), 1);
      expect((lorcana['totalValue'] as num).toDouble(), closeTo(5.0, 0.001));
    });

    test('getStatsPerRarity', () async {
      await addCardWithNullQuantity('digimon', ctValue: 2.0);

      final rows = await helper.getStatsPerRarity(collection: 'digimon');

      expect((rows.first['count'] as num).toInt(), 1);
      expect((rows.first['totalValue'] as num).toDouble(), closeTo(2.0, 0.001));
    });

    test('getRoiSummary: valore corrente e valore posseduto', () async {
      await db.insert('cards', {
        'name': 'carta',
        'serialNumber': '',
        'collection': 'digimon',
        'catalogId': '1',
        'quantity': null,
        'value': 0.0,
        'cardtrader_value': 4.0,
        'purchase_price': 1.0,
        'rarity': 'Rare',
        'added_at': '2026-09-03',
      });

      final roi = await helper.getRoiSummary();

      expect(roi['currentValue'], closeTo(4.0, 0.001));
      expect(roi['totalInvested'], closeTo(1.0, 0.001));
      expect(roi['ownedValue'], closeTo(4.0, 0.001));
    });

    test('duplicateCards conta anche le carte senza quantity in un album Doppioni',
        () async {
      final albumId = await db.insert('albums', {
        'name': 'Doppioni',
        'collection': 'digimon',
        'maxCapacity': 100,
      });
      await db.insert('cards', {
        'name': 'carta',
        'serialNumber': '',
        'collection': 'digimon',
        'catalogId': '1',
        'albumId': albumId,
        'quantity': null,
        'value': 0.0,
        'rarity': 'Rare',
        'added_at': '2026-09-03',
      });

      final stats = await helper.getGlobalStats(collection: 'digimon');

      expect(stats['duplicateCards'], 1);
    });
  });

  group('il totale globale coincide con la somma dei tab per-collezione', () {
    // Bug segnalato: il tab "_global" delle statistiche non tornava con la
    // somma manuale dei tab per-collezione. Causa: getGlobalStats(collection:
    // null) sommava TUTTE le carte, incluse quelle di una collezione ancora
    // presente in `cards` ma ri-bloccata (es. race in pullFromCloud che
    // resetta i lucchetti dal remoto) — quella collezione non ha un tab
    // visibile da sommare, quindi il globale la contava in più.
    test('una collezione bloccata non entra nel totale globale', () async {
      await unlock('digimon');
      // 'magic' resta bloccata (default di schema): le sue carte non devono
      // comparire nel totale globale né nel conteggio carte/doppioni.
      await addCard('digimon', ctValue: 2.0);
      await addCard('magic', value: 100.0);

      final global = await helper.getGlobalStats();
      expect(global['totalValue'], closeTo(2.0, 0.001));
      expect(global['totalCards'], 1);
    });

    test('sbloccata: il globale è esattamente la somma dei per-collezione', () async {
      await unlock('digimon');
      await unlock('lorcana');
      await unlock('onepiece');
      await addCard('digimon', ctValue: 2.0);
      await addCard('lorcana', ctValue: 1.25, quantity: 4);
      await addCard('onepiece', value: 7.5, serial: 'OP01-001');

      final global = await helper.getGlobalStats();
      final digimon = await helper.getGlobalStats(collection: 'digimon');
      final lorcana = await helper.getGlobalStats(collection: 'lorcana');
      final onepiece = await helper.getGlobalStats(collection: 'onepiece');

      final sumOfCollections =
          (digimon['totalValue'] as double) + (lorcana['totalValue'] as double) + (onepiece['totalValue'] as double);
      expect(global['totalValue'], closeTo(sumOfCollections, 0.001));
      expect(global['totalValue'], closeTo(2.0 + 5.0 + 7.5, 0.001));
    });
  });

  group('getEffectiveCardValuesByCollection — stessa fonte del totale in lista', () {
    // Bug segnalato: il "Valore" mostrato nella lista carte di una collezione
    // non coincideva col "Valore Stimato" nelle sue statistiche. Causa:
    // card_list_page._getEffectiveValue usava solo cardtrader_value → value,
    // senza il ripiego sul prezzo di stampa da catalogo che la CTE delle
    // statistiche applica per yugioh/pokemon/onepiece. Questo metodo espone
    // la stessa CTE per-carta così la lista può usare la stessa fonte.
    test('somma dei prezzi per-carta combacia col totale delle statistiche', () async {
      final id1 = await addCard('digimon', ctValue: 3.0);
      final id2 = await addCard('digimon', value: 1.5, quantity: 2);

      final byCard = await helper.getEffectiveCardValuesByCollection('digimon');
      final stats = await helper.getGlobalStats(collection: 'digimon');

      expect(byCard[id1], closeTo(3.0, 0.001));
      expect(byCard[id2], closeTo(1.5, 0.001));
      final rebuiltTotal = byCard.entries.fold<double>(0.0, (sum, e) => sum + e.value * (e.key == id2 ? 2 : 1));
      expect(rebuiltTotal, closeTo(stats['totalValue'] as double, 0.001));
    });

    test('è indicizzato per card id e ignora le altre collezioni', () async {
      await addCard('digimon', ctValue: 3.0);
      await addCard('lorcana', ctValue: 9.0);

      final byCard = await helper.getEffectiveCardValuesByCollection('digimon');

      expect(byCard.values, [3.0]);
    });
  });

  group('ROI: stessa fonte di prezzo delle statistiche', () {
    // Stesso bug del gruppo precedente, trovato nella pagina ROI:
    // getRoiSummary/getRoiCardList calcolavano il prezzo con
    // COALESCE(cardtrader_value, value, 0), senza il ripiego sul prezzo di
    // stampa da catalogo. Una carta yugioh/pokemon/onepiece con solo quel
    // prezzo mostrava guadagno/ROI% a zero mentre il totale collezione era
    // corretto.
    setUp(() async {
      await db.delete('yugioh_prints');
    });

    test('totalInvested e ownedValue contano esattamente le stesse carte', () async {
      // card_values (da cui viene ownedValue/cardCount) esclude le carte con
      // collection NULL (la CTE ha WHERE c.collection IS NOT NULL); prima del
      // fix totalInvested non aveva lo stesso filtro, quindi una carta simile
      // finanziava l'invested ma spariva dal valore posseduto — gain e ROI%
      // sballati per un motivo che non ha niente a che fare con la carta.
      await db.insert('cards', {
        'name': 'carta senza collezione',
        'serialNumber': '',
        'collection': null,
        'quantity': 1,
        'value': 0.0,
        'cardtrader_value': 50.0,
        'purchase_price': 10.0,
        'rarity': '',
        'added_at': '2026-09-10',
      });

      final roi = await helper.getRoiSummary();

      expect(roi['totalInvested'], 0.0);
      expect(roi['ownedValue'], 0.0);
      expect(roi['cardCount'], 0);
      expect(roi['gain'], 0.0);
    });

    test('getRoiSummary usa il prezzo di stampa quando manca cardtrader_value', () async {
      await db.insert('yugioh_prints', {
        'card_id': 42,
        'set_code': 'LOB-EN001',
        'set_price': 8.0,
      });
      await db.insert('cards', {
        'name': 'carta',
        'serialNumber': 'LOB-EN001',
        'collection': 'yugioh',
        'catalogId': '42',
        'quantity': 1,
        'value': 0.0,
        'purchase_price': 2.0,
        'rarity': 'Rare',
        'added_at': '2026-09-10',
      });

      final roi = await helper.getRoiSummary();

      expect(roi['ownedValue'], closeTo(8.0, 0.001));
      expect(roi['gain'], closeTo(6.0, 0.001));
    });

    test('getRoiCardList usa il prezzo di stampa nel current_price/gain/roi', () async {
      await db.insert('yugioh_prints', {
        'card_id': 42,
        'set_code': 'LOB-EN001',
        'set_price': 8.0,
      });
      await db.insert('cards', {
        'name': 'carta',
        'serialNumber': 'LOB-EN001',
        'collection': 'yugioh',
        'catalogId': '42',
        'quantity': 1,
        'value': 0.0,
        'purchase_price': 2.0,
        'rarity': 'Rare',
        'added_at': '2026-09-10',
      });

      final rows = await helper.getRoiCardList();

      expect(rows, hasLength(1));
      expect((rows.first['current_price'] as num).toDouble(), closeTo(8.0, 0.001));
      expect((rows.first['gain_euros'] as num).toDouble(), closeTo(6.0, 0.001));
      expect((rows.first['roi_pct'] as num).toDouble(), closeTo(300.0, 0.001));
    });

    test('getRoiCardList filtra per collezione', () async {
      await addCard('digimon', ctValue: 5.0);
      await db.update('cards', {'purchase_price': 1.0}, where: "collection = 'digimon'");
      await addCard('lorcana', ctValue: 9.0);
      await db.update('cards', {'purchase_price': 1.0}, where: "collection = 'lorcana'");

      final rows = await helper.getRoiCardList(collection: 'digimon');

      expect(rows, hasLength(1));
      expect(rows.first['collection'], 'digimon');
    });
  });
}
