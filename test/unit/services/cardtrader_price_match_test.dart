import 'dart:io';

import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regressione sull'aggancio dei prezzi CardTrader al catalogo locale.
///
/// Le passate di `syncCatalogPricesFromCardtrader` confrontavano colonne
/// avvolte in LOWER/SUBSTR/REPLACE, quindi nessun indice era utilizzabile e
/// ogni riga di stampa scandiva l'intero bucket di espansione dei prezzi.
/// La riscrittura sposta la normalizzazione su colonne persistite e
/// indicizzate: questi test fissano il comportamento di match che deve
/// restare identico (priorità del collector number, fallback sul nome, nome
/// CT con qualificatore fra parentesi) più l'avanzamento riportato alla UI.
void main() {
  late DatabaseHelper helper;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // DatabaseHelper è un singleton su un file fisso: si parte da pulito.
    final path = p.join(await databaseFactory.getDatabasesPath(), 'deck_master.db');
    for (final f in [File(path), File('$path-wal'), File('$path-shm')]) {
      if (await f.exists()) await f.delete();
    }

    helper = DatabaseHelper();
    db = await helper.database;
  });

  Future<void> seedCard({
    required int id,
    required String name,
    required String setCode,
    required String setId,
  }) async {
    await db.insert('yugioh_cards', {
      'id': id,
      'type': 'Spellcaster',
      'name': name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('yugioh_prints', {
      'card_id': id,
      'set_code': setCode,
      'set_id': setId,
      'rarity': 'Ultra Rare',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> seedPrice({
    required int blueprintId,
    required String expansionCode,
    required String cardNameEn,
    required String collectorNumber,
    required int cents,
    String language = 'en',
  }) async {
    await db.insert('cardtrader_prices', {
      'blueprint_id': blueprintId,
      'catalog': 'yugioh',
      'expansion_code': expansionCode,
      'card_name_en': cardNameEn,
      'language': language,
      'first_edition': 0,
      'rarity': '',
      'collector_number': collectorNumber,
      'min_price_nm_cents': cents,
      'min_price_any_cents': cents,
      'listing_count': 4,
      'synced_at': '2026-08-31T03:00:00.000Z',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double?> priceOf(String setCode) async {
    final rows = await db.query('yugioh_prints',
        columns: ['set_price'], where: 'set_code = ?', whereArgs: [setCode]);
    return rows.isEmpty ? null : rows.first['set_price'] as double?;
  }

  setUp(() async {
    await db.delete('yugioh_prints');
    await db.delete('yugioh_cards');
    await db.delete('cardtrader_prices');
  });

  group('syncCatalogPricesFromCardtrader — yugioh', () {
    test('il collector number vince sul nome, anche se costa di più', () async {
      // Due blueprint con lo stesso nome nella stessa espansione: solo il
      // collector number distingue la stampa giusta dall'altra rarità. Senza
      // la priorità della passata 0 verrebbe scelto il più economico.
      await seedCard(id: 1, name: 'Dark Magician', setCode: 'LOB-EN005', setId: 'LOB');
      await seedPrice(
        blueprintId: 100, expansionCode: 'lob',
        cardNameEn: 'Dark Magician', collectorNumber: 'EN005', cents: 1500,
      );
      await seedPrice(
        blueprintId: 101, expansionCode: 'lob',
        cardNameEn: 'Dark Magician', collectorNumber: 'EN006', cents: 500,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('LOB-EN005'), 15.0);
    });

    test('senza collector number corrispondente ripiega sul nome', () async {
      await seedCard(id: 2, name: 'Blue-Eyes White Dragon', setCode: 'LOB-EN001', setId: 'LOB');
      await seedPrice(
        blueprintId: 200, expansionCode: 'lob',
        cardNameEn: 'Blue-Eyes White Dragon', collectorNumber: 'ZZZ999', cents: 4200,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('LOB-EN001'), 42.0);
    });

    test("aggancia il nome CT con qualificatore ' (...)' in coda", () async {
      await seedCard(id: 3, name: 'Polymerization', setCode: 'SDY-EN010', setId: 'SDY');
      await seedPrice(
        blueprintId: 300, expansionCode: 'sdy',
        cardNameEn: 'Polymerization (Speed Duel)', collectorNumber: 'ZZZ999', cents: 300,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('SDY-EN010'), 3.0);
    });

    test('la forma corta del collector number aggancia lo stesso blueprint', () async {
      // CardTrader indicizza alcuni blueprint senza il prefisso di lingua:
      // "LOB-EN001" deve trovare anche il collector number "001".
      await seedCard(id: 4, name: 'Mystical Elf', setCode: 'LOB-EN012', setId: 'LOB');
      await seedPrice(
        blueprintId: 400, expansionCode: 'lob',
        cardNameEn: 'Nome Diverso Da Quello Locale', collectorNumber: '012', cents: 250,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('LOB-EN012'), 2.5);
    });

    test('un collector number vuoto non aggancia il bucket dei prezzi senza CN', () async {
      // cn_secondary è vuoto quando il suffisso è corto: senza il guardiano
      // `cp.cn_lc <> ''` la stampa si sarebbe agganciata a un prezzo di
      // un'altra carta solo perché entrambi avevano il campo vuoto.
      await seedCard(id: 5, name: 'Carta Senza Match', setCode: 'ABC-X1', setId: 'ABC');
      await seedPrice(
        blueprintId: 500, expansionCode: 'abc',
        cardNameEn: 'Tutt Altra Carta', collectorNumber: '', cents: 9900,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('ABC-X1'), isNull);
    });

    test('nessun match lascia il prezzo intatto', () async {
      await seedCard(id: 6, name: 'Sconosciuta', setCode: 'QQQ-EN001', setId: 'QQQ');

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('QQQ-EN001'), isNull);
    });

    test('i metadati di sync arrivano sulla stampa agganciata', () async {
      await seedCard(id: 7, name: 'Kuriboh', setCode: 'LOB-EN020', setId: 'LOB');
      await seedPrice(
        blueprintId: 700, expansionCode: 'lob',
        cardNameEn: 'Kuriboh', collectorNumber: 'EN020', cents: 120,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');

      final row = (await db.query('yugioh_prints',
          columns: ['ct_synced_at', 'ct_listing_count'],
          where: 'set_code = ?',
          whereArgs: ['LOB-EN020'])).first;
      expect(row['ct_synced_at'], '2026-08-31T03:00:00.000Z');
      expect(row['ct_listing_count'], 4);
    });

    test('onProgress avanza e chiude a 1.0', () async {
      // Senza questo la barra di download restava ferma al 100% per tutta la
      // durata dell'aggancio dei prezzi, che è il passo più lungo.
      await seedCard(id: 8, name: 'Test', setCode: 'LOB-EN099', setId: 'LOB');

      final steps = <double>[];
      await helper.syncCatalogPricesFromCardtrader('yugioh',
          onProgress: steps.add);

      expect(steps, isNotEmpty);
      expect(steps.last, 1.0);
      expect(steps.first, lessThan(1.0));
      // Monotono e sempre dentro [0, 1].
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThanOrEqualTo(steps[i - 1]));
      }
      expect(steps.every((s) => s >= 0.0 && s <= 1.0), isTrue);
    });

    test('rieseguirlo è idempotente', () async {
      await seedCard(id: 9, name: 'Dark Magician', setCode: 'LOB-EN005', setId: 'LOB');
      await seedPrice(
        blueprintId: 900, expansionCode: 'lob',
        cardNameEn: 'Dark Magician', collectorNumber: 'EN005', cents: 1500,
      );

      await helper.syncCatalogPricesFromCardtrader('yugioh');
      final first = await priceOf('LOB-EN005');
      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('LOB-EN005'), first);
    });

    test('le chiavi di match si ricalcolano dopo un upsert dei prezzi', () async {
      // upsertCardtraderPrices inserisce con REPLACE: la riga viene riscritta
      // e le colonne derivate tornano NULL. Il refresh deve riprenderle, o il
      // sync successivo non aggancerebbe più nulla.
      await seedCard(id: 10, name: 'Jinzo', setCode: 'PSV-EN000', setId: 'PSV');
      await helper.syncCatalogPricesFromCardtrader('yugioh');
      expect(await priceOf('PSV-EN000'), isNull);

      await helper.upsertCardtraderPrices([
        {
          'blueprint_id': 1000,
          'catalog': 'yugioh',
          'expansion_code': 'psv',
          'card_name_en': 'Jinzo',
          'language': 'en',
          'first_edition': 0,
          'rarity': '',
          'collector_number': 'EN000',
          'min_price_nm_cents': 777,
          'min_price_any_cents': 777,
          'listing_count': 1,
          'synced_at': '2026-08-31T04:00:00.000Z',
        }
      ]);
      await helper.syncCatalogPricesFromCardtrader('yugioh');

      expect(await priceOf('PSV-EN000'), 7.77);
    });
  });

  group('piano di esecuzione', () {
    // Il vero difetto non era il risultato ma il costo: con LOWER/SUBSTR/REPLACE
    // applicati alla colonna indicizzata nessun indice era utilizzabile e ogni
    // riga di stampa scandiva l'intero bucket di espansione dei prezzi (250k
    // righe su yugioh) per trenta statement di fila. Se una modifica futura
    // rimette una funzione sul lato indicizzato, questi test cadono.
    Future<String> planFor(String sql) async {
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql');
      return rows.map((r) => r['detail']).join(' | ');
    }

    test('il match per collector number usa tutte e 4 le colonne dell indice', () async {
      final plan = await planFor("""
        SELECT 1 FROM cardtrader_prices cp
        WHERE cp.catalog = 'yugioh'
          AND cp.expansion_code = (SELECT set_id_lc FROM yugioh_prints LIMIT 1)
          AND cp.cn_lc = (SELECT cn_primary FROM yugioh_prints LIMIT 1)
          AND cp.language = 'en'
      """);
      expect(plan, contains('idx_ct_prices_cn_lc'));
      expect(plan, contains('catalog=? AND expansion_code=? AND cn_lc=? AND language=?'));
    });

    test('il match per nome usa tutte e 4 le colonne dell indice', () async {
      final plan = await planFor("""
        SELECT 1 FROM cardtrader_prices cp
        WHERE cp.catalog = 'yugioh'
          AND cp.expansion_code = (SELECT set_id_lc FROM yugioh_prints LIMIT 1)
          AND cp.name_norm = (SELECT name_norm FROM yugioh_cards LIMIT 1)
          AND cp.language = 'en'
      """);
      expect(plan, contains('idx_ct_prices_name_norm'));
      expect(plan, contains('catalog=? AND expansion_code=? AND name_norm=? AND language=?'));
    });

    test('il match per nome base usa tutte e 4 le colonne dell indice', () async {
      final plan = await planFor("""
        SELECT 1 FROM cardtrader_prices cp
        WHERE cp.catalog = 'yugioh'
          AND cp.expansion_code = (SELECT set_id_lc FROM yugioh_prints LIMIT 1)
          AND cp.name_base_norm = (SELECT name_norm FROM yugioh_cards LIMIT 1)
          AND cp.language = 'en'
      """);
      expect(plan, contains('idx_ct_prices_name_base'));
      expect(plan, contains('catalog=? AND expansion_code=? AND name_base_norm=? AND language=?'));
    });

    test('la passata dei metadati riusa lo stesso indice senza la lingua', () async {
      final plan = await planFor("""
        SELECT MAX(cp.synced_at) FROM cardtrader_prices cp
        WHERE cp.catalog = 'yugioh'
          AND cp.expansion_code = (SELECT set_id_lc FROM yugioh_prints LIMIT 1)
          AND cp.name_norm = (SELECT name_norm FROM yugioh_cards LIMIT 1)
      """);
      expect(plan, contains('idx_ct_prices_name_norm'));
      expect(plan, isNot(contains('SCAN cp')));
    });
  });

  group('lingue disponibili nel catalogo', () {
    setUp(() async {
      await db.delete('yugioh_prints');
      await db.delete('yugioh_cards');
    });

    test('una lingua con il nome carta tradotto è disponibile', () async {
      // L'array card_sets di YGOProDeck porta codici quasi solo inglesi, anche
      // interrogandolo con language=it: guardare solo set_code_it faceva
      // sparire italiano, francese e tedesco pur avendone le traduzioni.
      await db.insert('yugioh_cards', {
        'id': 1,
        'type': 'Effect Monster',
        'name': 'Flying "C"',
        'name_it': '"C" Volante',
      });
      await db.insert('yugioh_prints', {
        'card_id': 1,
        'set_code': 'LOB-EN001',
        'set_id': 'LOB',
      });

      final langs = await helper.getAvailableCatalogLanguages('yugioh');

      expect(langs, contains('IT'));
    });

    test('una lingua senza traduzioni resta indisponibile', () async {
      // Lo spagnolo non ha traduzioni: YGOProDeck accetta solo fr/de/it/pt
      // come parametro `language`, quindi name_sp non viene mai popolato.
      await db.insert('yugioh_cards', {
        'id': 1,
        'type': 'Effect Monster',
        'name': 'Flying "C"',
        'name_it': '"C" Volante',
      });

      final langs = await helper.getAvailableCatalogLanguages('yugioh');

      expect(langs, isNot(contains('SP')));
      expect(langs, isNot(contains('FR')));
    });

    test('il codice set localizzato basta da solo', () async {
      // Il vecchio criterio resta valido come seconda strada: se una carta ha
      // davvero una stampa localizzata, quella lingua è disponibile anche
      // senza nome tradotto.
      await db.insert('yugioh_cards',
          {'id': 1, 'type': 'Spell', 'name': 'Monster Reborn'});
      await db.insert('yugioh_prints', {
        'card_id': 1,
        'set_code': 'LOB-EN118',
        'set_id': 'LOB',
        'set_code_pt': 'LOB-PT118',
      });

      final langs = await helper.getAvailableCatalogLanguages('yugioh');

      expect(langs, contains('PT'));
    });

    test("l'inglese c'è sempre", () async {
      expect(await helper.getAvailableCatalogLanguages('yugioh'), contains('EN'));
    });
  });

  group('potatura dopo un ridownload', () {
    // I redownload* cancellavano tutto PRIMA di scaricare, riga di
    // catalog_metadata compresa: un'app uccisa a metà download lasciava
    // l'utente senza catalogo e con un "primo download" da rifare da capo.
    // Ora si scarica prima e si pota dopo.
    Future<void> seedAged(int id, String name, String updatedAt) async {
      await db.insert('yugioh_cards', {
        'id': id,
        'type': 'Spellcaster',
        'name': name,
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('yugioh_prints', {
        'card_id': id,
        'set_code': 'SET-EN00$id',
        'set_id': 'SET',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<List<int>> remainingIds() async {
      final rows = await db.query('yugioh_cards', columns: ['id'], orderBy: 'id');
      return rows.map((r) => r['id'] as int).toList();
    }

    test('toglie solo le carte che il download non ha toccato', () async {
      await seedAged(1, 'Vecchia', '2026-01-01T00:00:00.000');
      await seedAged(2, 'Nuova', '2026-06-01T00:00:00.000');

      final deleted = await helper.pruneCatalogCardsNotUpdatedSince(
          'yugioh', '2026-03-01T00:00:00.000');

      expect(deleted, 1);
      expect(await remainingIds(), [2]);
    });

    test('porta via anche le stampe della carta rimossa', () async {
      await seedAged(1, 'Vecchia', '2026-01-01T00:00:00.000');
      await seedAged(2, 'Nuova', '2026-06-01T00:00:00.000');

      await helper.pruneCatalogCardsNotUpdatedSince(
          'yugioh', '2026-03-01T00:00:00.000');

      final prints = await db.query('yugioh_prints', columns: ['card_id']);
      expect(prints.map((r) => r['card_id']), [2]);
    });

    test('un download a vuoto non svuota il catalogo', () async {
      // Il caso che rende sicura l'inversione: se il remoto non ha risposto
      // nessuna carta risulta aggiornata, e potare vorrebbe dire cancellare
      // tutto. Deve essere un no-op.
      await seedAged(1, 'Prima', '2026-01-01T00:00:00.000');
      await seedAged(2, 'Seconda', '2026-01-01T00:00:00.000');

      final deleted = await helper.pruneCatalogCardsNotUpdatedSince(
          'yugioh', '2026-06-01T00:00:00.000');

      expect(deleted, 0);
      expect(await remainingIds(), [1, 2]);
    });

    test('una carta senza updated_at conta come vecchia', () async {
      await db.insert('yugioh_cards',
          {'id': 1, 'type': 'Trap', 'name': 'Senza data'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await seedAged(2, 'Nuova', '2026-06-01T00:00:00.000');

      await helper.pruneCatalogCardsNotUpdatedSince(
          'yugioh', '2026-03-01T00:00:00.000');

      expect(await remainingIds(), [2]);
    });

    test('un catalogo sconosciuto non tocca niente', () async {
      await seedAged(1, 'Intatta', '2026-01-01T00:00:00.000');

      expect(
        await helper.pruneCatalogCardsNotUpdatedSince('non-esiste', '2026-06-01T00:00:00.000'),
        0,
      );
      expect(await remainingIds(), [1]);
    });

    test('la riga di catalog_metadata sopravvive alla potatura', () async {
      // È quella la cui cancellazione anticipata faceva ricomparire il
      // "primo download" dopo un'interruzione.
      await helper.saveCatalogMetadata(
        catalogName: 'yugioh',
        version: 77,
        totalCards: 1,
        totalChunks: 47,
        lastUpdated: '2026-08-26T14:59:55.214Z',
      );
      await seedAged(1, 'Vecchia', '2026-01-01T00:00:00.000');
      await seedAged(2, 'Nuova', '2026-06-01T00:00:00.000');

      await helper.pruneCatalogCardsNotUpdatedSince(
          'yugioh', '2026-03-01T00:00:00.000');

      final meta = await helper.getCatalogMetadata('yugioh');
      expect(meta, isNotNull);
      expect(meta!['version'], 77);
    });
  });

  group('coda degli sblocchi collezione', () {
    setUp(() async => db.delete('pending_sync'));

    test('uno sblocco accodato è leggibile e non si duplica', () async {
      await helper.addPendingCollectionUnlock('pokemon');
      await helper.addPendingCollectionUnlock('pokemon');
      await helper.addPendingCollectionUnlock('onepiece');

      expect(await helper.getPendingCollectionUnlocks(), {'pokemon', 'onepiece'});
      final rows = await db.query('pending_sync',
          where: "table_name = 'collections'");
      expect(rows.length, 2, reason: 'la riaccodata sostituisce, non duplica');
    });

    test('la conferma toglie solo la collezione confermata', () async {
      await helper.addPendingCollectionUnlock('pokemon');
      await helper.addPendingCollectionUnlock('onepiece');

      await helper.clearPendingCollectionUnlock('pokemon');

      expect(await helper.getPendingCollectionUnlocks(), {'onepiece'});
    });

    test('gli sblocchi in coda contano come sync pendente', () async {
      // syncOnLogin usa getPendingSyncCount() per decidere se svuotare la
      // coda prima di riallineare i lucchetti al remoto.
      expect(await helper.getPendingSyncCount(), 0);
      await helper.addPendingCollectionUnlock('magic');
      expect(await helper.getPendingSyncCount(), 1);
    });
  });
}
