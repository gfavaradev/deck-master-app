import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/card_model.dart';
import '../models/collection_model.dart';
import '../models/album_model.dart';
import 'print_id.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static Completer<Database>? _initCompleter;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static const List<String> _validLanguages = ['EN', 'IT', 'FR', 'DE', 'PT', 'ES', 'SP', 'JP', 'KO', 'ZH'];

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Web doesn't support SQLite - throw clear error
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite database is not supported on Web. '
        'Use Firestore directly for web applications.',
      );
    }

    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path = join(await getDatabasesPath(), 'deck_master.db');

    final db = await openDatabase(
      path,
      version: 42,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // WAL mode: allows concurrent reads while catalog writes are in progress.
    // synchronous=NORMAL is safe with WAL (durability still guaranteed across
    // app crashes, only a rare OS-level crash could lose the last commit) and
    // avoids an fsync on every batch commit during catalog downloads.
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.rawQuery('PRAGMA synchronous=NORMAL');
    // Il download dei cataloghi gira in un isolate separato (foreground
    // service), che apre una propria connessione nativa allo stesso file: WAL
    // copre le letture concorrenti, ma due scrittori si contendono il lock e
    // senza attesa il secondo fallirebbe subito con SQLITE_BUSY. Trenta
    // secondi coprono abbondantemente la transazione più lunga (un batch di
    // insert del catalogo).
    await db.rawQuery('PRAGMA busy_timeout=30000');

    // Ensure essential indices exist (for development/existing dbs)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_catalog_card_sets_cardId ON catalog_card_sets (cardId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_catalog_cards_collection ON catalog_cards (collection)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_catalog_card_sets_lookup ON catalog_card_sets (cardId, setCode)');

    // Yugioh indices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_cards_type ON yugioh_cards(type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_cards_archetype ON yugioh_cards(archetype)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_cards_race ON yugioh_cards(race)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_cards_name ON yugioh_cards(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_prints_card_id ON yugioh_prints(card_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_prints_set_code ON yugioh_prints(set_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_prints_rarity ON yugioh_prints(rarity)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_prints_set_name ON yugioh_prints(set_name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yugioh_prices_print_id ON yugioh_prices(print_id)');

    // One Piece indices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_onepiece_cards_name ON onepiece_cards(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_onepiece_cards_color ON onepiece_cards(color)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_onepiece_cards_type ON onepiece_cards(card_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_onepiece_prints_card_id ON onepiece_prints(card_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_onepiece_prints_set_id ON onepiece_prints(set_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_onepiece_prints_card_set_id ON onepiece_prints(card_set_id)');

    // Pokemon indices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pokemon_cards_name ON pokemon_cards(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pokemon_cards_set_id ON pokemon_cards(set_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pokemon_cards_api_id ON pokemon_cards(api_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pokemon_prints_card_id ON pokemon_prints(card_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pokemon_prints_set_code ON pokemon_prints(set_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pokemon_prices_print_id ON pokemon_prices(print_id)');

    // Magic indices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_magic_cards_name ON magic_cards(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_magic_cards_api_id ON magic_cards(api_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_magic_cards_set_code ON magic_cards(set_code)');

    // cards table indices — critical for getCardsByCollection and getAlbumsByCollection
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_collection ON cards(collection)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_albumId ON cards(albumId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_catalogId ON cards(catalogId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_collection_albumId ON cards(collection, albumId)');

    return db;
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE cards ADD COLUMN name TEXT');
      await db.execute('ALTER TABLE cards ADD COLUMN type TEXT');
      await db.execute('ALTER TABLE cards ADD COLUMN description TEXT');
      await db.execute('ALTER TABLE cards ADD COLUMN collection TEXT');
      await db.execute('ALTER TABLE cards ADD COLUMN imageUrl TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE catalog_cards ADD COLUMN humanReadableCardType TEXT');
      await db.execute('ALTER TABLE catalog_cards ADD COLUMN scale INTEGER');
      await db.execute('ALTER TABLE catalog_cards ADD COLUMN linkval INTEGER');
      await db.execute('ALTER TABLE catalog_cards ADD COLUMN linkmarkers TEXT');
      await db.execute('ALTER TABLE catalog_cards ADD COLUMN imageUrlCropped TEXT');

      await db.execute('ALTER TABLE catalog_card_sets ADD COLUMN rarityCode TEXT');
      await db.execute('ALTER TABLE catalog_card_sets ADD COLUMN imageUrl TEXT');
      await db.execute('ALTER TABLE catalog_card_sets ADD COLUMN imageUrlSmall TEXT');
    }
    if (oldVersion < 4) {
      await _createYugiohTables(db);
      await _migrateYugiohData(db);
    }
    if (oldVersion < 5) {
      await _addFirestoreSyncSupport(db);
    }
    if (oldVersion < 6) {
      await _addCatalogMetadata(db);
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE yugioh_cards ADD COLUMN image_url TEXT');
    }
    if (oldVersion < 8) {
      await _createOnepieceTables(db);
    }
    if (oldVersion < 9) {
      await db.execute('ALTER TABLE cards ADD COLUMN added_at TEXT');
    }
    if (oldVersion < 10) {
      await _createPokemonTables(db);
    }
    if (oldVersion < 11) {
      // Ensure added_at column exists in cards table.
      // Fresh installs at v10 were missing this column, causing insertCard to fail
      // and Firestore sync (pullFromCloud) to silently leave the collection empty.
      final cols = await db.rawQuery('PRAGMA table_info(cards)');
      final hasAddedAt = cols.any((c) => c['name'] == 'added_at');
      if (!hasAddedAt) {
        await db.execute('ALTER TABLE cards ADD COLUMN added_at TEXT');
      }
    }
    if (oldVersion < 12) {
      // albums: maxCapacity non aveva migrazione
      await _addColumnIfMissing(db, 'albums', 'maxCapacity', 'INTEGER');

      // yugioh_cards: colonne lingua aggiunte dopo v4 senza migrazione
      await _addColumnIfMissing(db, 'yugioh_cards', 'name_it', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'description_it', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'name_fr', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'description_fr', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'name_de', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'description_de', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'name_pt', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'description_pt', 'TEXT');

      // yugioh_prints: colonne lingua aggiunte dopo v4 senza migrazione
      for (final lang in ['it', 'fr', 'de', 'pt']) {
        await _addColumnIfMissing(db, 'yugioh_prints', 'set_name_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'yugioh_prints', 'set_code_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'yugioh_prints', 'rarity_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'yugioh_prints', 'rarity_code_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'yugioh_prints', 'set_price_$lang', 'REAL');
      }

      // Assicura che le righe delle collezioni esistano per utenti che facevano upgrade
      await db.execute('''
        INSERT OR IGNORE INTO collections (id, name, isUnlocked)
        VALUES
          ('yugioh',   'Yu-Gi-Oh!',              0),
          ('pokemon',  'Pokémon',                 0),
          ('magic',    'Magic: The Gathering',    0),
          ('onepiece', 'One Piece',               0)
      ''');
    }
    if (oldVersion < 13) {
      // Spagnolo: nuove colonne per yugioh_cards
      await _addColumnIfMissing(db, 'yugioh_cards', 'name_sp', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_cards', 'description_sp', 'TEXT');

      // Spagnolo: nuove colonne per yugioh_prints
      await _addColumnIfMissing(db, 'yugioh_prints', 'set_name_sp', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_prints', 'set_code_sp', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_prints', 'rarity_sp', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_prints', 'rarity_code_sp', 'TEXT');
      await _addColumnIfMissing(db, 'yugioh_prints', 'set_price_sp', 'REAL');
    }
    if (oldVersion < 14) {
      // set_id: identificatore del set (es. "LOB" da "LOB-EN001")
      await _addColumnIfMissing(db, 'yugioh_prints', 'set_id', 'TEXT');
      // Popola dalle righe esistenti estraendo il prefisso prima del primo trattino
      await db.execute('''
        UPDATE yugioh_prints
        SET set_id = CASE
          WHEN INSTR(set_code, '-') > 0
            THEN SUBSTR(set_code, 1, INSTR(set_code, '-') - 1)
          ELSE set_code
        END
        WHERE set_id IS NULL AND set_code IS NOT NULL AND set_code != ''
      ''');
    }
    if (oldVersion < 15) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cardtrader_prices (
          blueprint_id    INTEGER NOT NULL,
          catalog         TEXT    NOT NULL,
          expansion_code  TEXT    NOT NULL,
          card_name_en    TEXT    NOT NULL,
          language        TEXT    NOT NULL,
          first_edition   INTEGER NOT NULL DEFAULT 0,
          min_price_nm_cents  INTEGER,
          min_price_any_cents INTEGER,
          listing_count   INTEGER NOT NULL DEFAULT 0,
          synced_at       TEXT    NOT NULL,
          PRIMARY KEY (blueprint_id, language, first_edition)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ct_prices_lookup '
        'ON cardtrader_prices(catalog, expansion_code, card_name_en)',
      );
    }
    if (oldVersion < 16) {
      // Recreate cardtrader_prices with rarity in the primary key.
      // This table is a pure cache — re-sync after upgrade.
      await db.execute('DROP TABLE IF EXISTS cardtrader_prices');
      await db.execute('''
        CREATE TABLE cardtrader_prices (
          blueprint_id        INTEGER NOT NULL,
          catalog             TEXT    NOT NULL,
          expansion_code      TEXT    NOT NULL,
          card_name_en        TEXT    NOT NULL,
          language            TEXT    NOT NULL,
          first_edition       INTEGER NOT NULL DEFAULT 0,
          rarity              TEXT    NOT NULL DEFAULT '',
          min_price_nm_cents  INTEGER,
          min_price_any_cents INTEGER,
          listing_count       INTEGER NOT NULL DEFAULT 0,
          synced_at           TEXT    NOT NULL,
          PRIMARY KEY (blueprint_id, language, first_edition, rarity)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ct_prices_lookup '
        'ON cardtrader_prices(catalog, expansion_code, card_name_en)',
      );
    }
    if (oldVersion < 17) {
      // Add collector_number for precise artwork-level price matching.
      // cardtrader_prices is a pure cache — safe to add with DEFAULT ''.
      await db.execute(
        "ALTER TABLE cardtrader_prices ADD COLUMN collector_number TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ct_prices_collector '
        'ON cardtrader_prices(catalog, expansion_code, collector_number)',
      );
    }
    if (oldVersion < 18) {
      // Create dedicated expansion/rarity tables and populate from existing prints data.
      await _createExpansionRarityTables(db);
      // Populate from existing data (best-effort — null expansions are skipped).
      await _populateExpansionsFromPrints(db, 'yugioh');
      await _populateExpansionsFromPrints(db, 'pokemon');
      await _populateExpansionsFromPrints(db, 'onepiece');
      await _populateRaritiesFromPrints(db, 'yugioh');
      await _populateRaritiesFromPrints(db, 'pokemon');
      await _populateRaritiesFromPrints(db, 'onepiece');
    }
    if (oldVersion < 19) {
      // Track previous CT price to show trend arrow in the UI.
      await db.execute(
        'ALTER TABLE cards ADD COLUMN previous_value REAL',
      );
    }
    if (oldVersion < 20) {
      // Colonna cardtrader_value mancante dalla migration — aggiunta al modello
      // senza ALTER TABLE corrispondente.
      await _addColumnIfMissing(db, 'cards', 'cardtrader_value', 'REAL');
    }
    if (oldVersion < 21) {
      // Aggiunge le collezioni "Prossimamente" presenti su CardTrader.
      await db.execute('''
        INSERT OR IGNORE INTO collections (id, name, isUnlocked) VALUES
          ('digimon',          'Digimon Card Game',     0),
          ('dragon-ball-super','Dragon Ball Super',      0),
          ('lorcana',          'Disney Lorcana',         0),
          ('flesh-and-blood',  'Flesh and Blood',        0),
          ('vanguard',         'Cardfight!! Vanguard',   0),
          ('star-wars',        'Star Wars: Unlimited',   0),
          ('riftbound',        'Riftbound',              0),
          ('gundam',           'Gundam Card Game',       0),
          ('union-arena',      'Union Arena',            0)
      ''');
    }
    if (oldVersion < 22) {
      // Aggiunge colonne lingua a onepiece_prints (fr rimane usata; le altre resteranno vuote)
      for (final lang in ['it', 'fr', 'de', 'pt', 'sp']) {
        await _addColumnIfMissing(db, 'onepiece_prints', 'set_name_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'onepiece_prints', 'rarity_$lang', 'TEXT');
      }
    }
    if (oldVersion < 23) {
      // Aggiunge giapponese a onepiece_prints (lingua ufficiale del TCG)
      await _addColumnIfMissing(db, 'onepiece_prints', 'set_name_jp', 'TEXT');
      await _addColumnIfMissing(db, 'onepiece_prints', 'rarity_jp', 'TEXT');
    }
    if (oldVersion < 24) {
      // Ripara le carte con collection NULL o vuoto usando la collection dell'album.
      // Causato da sync Firestore che non salvava correttamente il campo collection.
      await db.rawUpdate('''
        UPDATE cards
        SET collection = (
          SELECT a.collection FROM albums a WHERE a.id = cards.albumId
        )
        WHERE (collection IS NULL OR collection = '')
          AND albumId IS NOT NULL
          AND EXISTS (SELECT 1 FROM albums a WHERE a.id = cards.albumId)
      ''');
    }
    if (oldVersion < 25) {
      // Aggiunge spagnolo (ES) a pokemon_cards e pokemon_prints.
      // ES usa TCGdex /es/ endpoint; prezzi da cardtrader_prices language='es'.
      await _addColumnIfMissing(db, 'pokemon_cards', 'name_es', 'TEXT');
      await _addColumnIfMissing(db, 'pokemon_prints', 'set_code_es', 'TEXT');
      await _addColumnIfMissing(db, 'pokemon_prints', 'set_name_es', 'TEXT');
      await _addColumnIfMissing(db, 'pokemon_prints', 'rarity_es', 'TEXT');
      await _addColumnIfMissing(db, 'pokemon_prints', 'set_price_es', 'REAL');
    }
    if (oldVersion < 26) {
      // Aggiunge KO/ZH a onepiece_prints e alle tabelle di traduzioni condivise.
      // Aggiunge anche ES a catalog_expansions e catalog_rarities per il Pokémon.
      for (final lang in ['ko', 'zh']) {
        await _addColumnIfMissing(db, 'onepiece_prints', 'set_name_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'onepiece_prints', 'rarity_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'catalog_expansions', 'set_name_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'catalog_rarities', 'rarity_$lang', 'TEXT');
      }
      await _addColumnIfMissing(db, 'catalog_expansions', 'set_name_es', 'TEXT');
      await _addColumnIfMissing(db, 'catalog_rarities', 'rarity_es', 'TEXT');
    }
    if (oldVersion < 27) {
      // PERF #6 fix: indice composito per query filtrate per collezione + album.
      // Accelera getCardsByCollection quando si filtra poi per albumId (es. album view).
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cards_collection_albumId ON cards(collection, albumId)',
      );
    }
    if (oldVersion < 28) {
      // Fix: su DB creati prima che card_set_id/set_id fossero aggiunti alla
      // definizione di onepiece_prints, CREATE TABLE IF NOT EXISTS era no-op e
      // le colonne non esistevano mai. Aggiunge con DEFAULT '' / NULL e svuota
      // la tabella per forzare il re-download del catalogo.
      await _addColumnIfMissing(db, 'onepiece_prints', 'card_set_id', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'onepiece_prints', 'set_id', 'TEXT');
      await _addColumnIfMissing(db, 'onepiece_prints', 'market_price', 'REAL');
      await _addColumnIfMissing(db, 'onepiece_prints', 'artwork', 'TEXT');
      // Righe senza card_set_id valido sono inutilizzabili — forza re-download.
      await db.execute(
        "DELETE FROM onepiece_prints WHERE card_set_id IS NULL OR card_set_id = ''",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_onepiece_prints_card_set_id ON onepiece_prints(card_set_id)',
      );
    }
    if (oldVersion < 29) {
      // Prezzi per lingua su onepiece_prints: una sola stampa per carta (JP base)
      // con colonne separate per EN, FR, KO, ZH — stesso pattern di YuGiOh/Pokémon.
      // market_price (colonna esistente) = prezzo JP.
      for (final col in ['market_price_en', 'market_price_fr', 'market_price_ko', 'market_price_zh']) {
        await _addColumnIfMissing(db, 'onepiece_prints', col, 'REAL');
      }
    }
    if (oldVersion < 30) {
      // Metadati sync CT per stampa: data ultimo aggiornamento e contatore annunci attivi.
      // Usati per mostrare "prezzo storico + data" nella lista collezione.
      for (final table in ['yugioh_prints', 'onepiece_prints', 'pokemon_prints']) {
        await _addColumnIfMissing(db, table, 'ct_synced_at', 'TEXT');
        await _addColumnIfMissing(db, table, 'ct_listing_count', 'INTEGER');
      }
    }
    if (oldVersion < 31) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS price_history (
          blueprint_id  INTEGER NOT NULL,
          language      TEXT    NOT NULL,
          first_edition INTEGER NOT NULL DEFAULT 0,
          rarity        TEXT    NOT NULL DEFAULT '',
          price_cents   INTEGER NOT NULL,
          listing_count INTEGER NOT NULL DEFAULT 0,
          recorded_date TEXT    NOT NULL,
          PRIMARY KEY (blueprint_id, language, first_edition, rarity, recorded_date)
        )
      ''');
    }
    if (oldVersion < 32) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS collection_value_history (
          collection    TEXT    NOT NULL,
          total_cents   INTEGER NOT NULL,
          recorded_date TEXT    NOT NULL,
          PRIMARY KEY (collection, recorded_date)
        )
      ''');
    }
    if (oldVersion < 33) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS wishlist (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          catalogId    TEXT    NOT NULL,
          name         TEXT    NOT NULL,
          collection   TEXT    NOT NULL,
          imageUrl     TEXT,
          serialNumber TEXT,
          rarity       TEXT,
          target_price REAL,
          added_at     TEXT    NOT NULL
        )
      ''');
    }
    if (oldVersion < 34) {
      await _addColumnIfMissing(db, 'cards', 'purchase_price', 'REAL');
    }
    if (oldVersion < 35) {
      await _createMagicTables(db);
    }
    if (oldVersion < 36) {
      await _createNewCollectionTables(db);
      // dragon-ball-super, flesh-and-blood, star-wars were added to _onCreate but
      // missed the v21 migration — add them for existing users upgrading.
      await db.execute("INSERT OR IGNORE INTO collections(id,name,isUnlocked) VALUES('dragon-ball-super','Dragon Ball Super',0)");
      await db.execute("INSERT OR IGNORE INTO collections(id,name,isUnlocked) VALUES('flesh-and-blood','Flesh and Blood',0)");
      await db.execute("INSERT OR IGNORE INTO collections(id,name,isUnlocked) VALUES('star-wars','Star Wars: Unlimited',0)");
    }
    if (oldVersion < 37) {
      // Fix: dispositivi creati fresh alla versione 26-36 hanno onepiece_prints senza
      // le colonne lingua aggiunte dalle migration v22/v26 (CREATE TABLE IF NOT EXISTS
      // era già passato e quelle migration non giravano su fresh install recenti).
      for (final lang in ['it', 'de', 'pt', 'sp', 'ko', 'zh']) {
        await _addColumnIfMissing(db, 'onepiece_prints', 'set_name_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'onepiece_prints', 'rarity_$lang', 'TEXT');
      }
    }
    if (oldVersion < 38) {
      // Colonne pronte per future traduzioni Magic (Scryfall printed_name/
      // printed_type_line/printed_text) — popolamento in un task separato.
      for (final lang in ['it', 'fr', 'de', 'pt', 'sp', 'jp', 'ko', 'zh']) {
        await _addColumnIfMissing(db, 'magic_cards', 'name_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'magic_cards', 'type_line_$lang', 'TEXT');
        await _addColumnIfMissing(db, 'magic_cards', 'oracle_text_$lang', 'TEXT');
      }
    }
    if (oldVersion < 39) {
      // Fix: per i cataloghi generici sincronizzati via CardTrader (vanguard,
      // dragon-ball-super, star-wars, riftbound, gundam, union-arena), api_id è
      // l'id interno del blueprint CT, non il seriale reale della carta — che
      // veniva scaricato correttamente da downloadCardtraderGenericCatalog ma
      // scartato al sync perché non esisteva una colonna dove salvarlo, quindi
      // la UI mostrava l'id CT al posto del seriale.
      for (final prefix in _genericCatalogPrefixes) {
        await _addColumnIfMissing(db, '${prefix}_cards', 'card_number', 'TEXT');
      }
    }
    if (oldVersion < 40) {
      await _createPriceMatchKeys(db);
    }
    if (oldVersion < 41) {
      await _createUnifiedPriceTables(db);
    }
    if (oldVersion < 42) {
      // v42 — il blueprint CardTrader di una stampa One Piece diventa un campo
      // suo. Fino al rebuild del 03/09/2026 stava dentro `card_set_id`
      // ("OP01-244442"), che l'app mostra come seriale: adesso lì c'e' il
      // numero di collezione vero ("OP01-064") e il blueprint va conservato a
      // parte, altrimenti la stampa resta senza prezzo. Vedi [resolvePrintId].
      await _addColumnIfMissing(db, 'onepiece_prints', 'blueprint_id', 'TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_onepiece_prints_blueprint_id '
        'ON onepiece_prints(blueprint_id)',
      );
    }
  }

  /// Prezzi unificati (v41) — vedi REQUIREMENTS_prices_unified.md.
  ///
  /// Una sola tabella per tutti i 13 cataloghi, con `print_id` come chiave: il
  /// worker pubblica i prezzi gia' agganciati alla stampa, quindi qui non serve
  /// piu' alcuna colonna di normalizzazione per il matching (`name_norm`,
  /// `cn_lc`, …) ne' le passate per lingua di
  /// [syncCatalogPricesFromCardtrader].
  ///
  /// `price_set_versions` ricorda la versione di ogni set gia' scaricato: e' il
  /// gate che fa scaricare SOLO i set cambiati, invece dell'intero listino.
  Future<void> _createUnifiedPriceTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS card_prices(
        catalog    TEXT    NOT NULL,
        print_id   TEXT    NOT NULL,
        lang       TEXT    NOT NULL,
        set_code   TEXT,
        nm_cents   INTEGER,
        any_cents  INTEGER,
        listings   INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        PRIMARY KEY (catalog, print_id, lang)
      )
    ''');
    // Il lookup per (catalogo, stampa) e' la query calda: la chiave primaria la
    // copre. Questo indice serve invece a cancellare/aggiornare un set intero.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_card_prices_set ON card_prices(catalog, set_code)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_set_versions(
        catalog  TEXT    NOT NULL,
        set_code TEXT    NOT NULL,
        version  INTEGER NOT NULL,
        PRIMARY KEY (catalog, set_code)
      )
    ''');
  }

  // ============================================================
  // Prezzi unificati (v41) — REQUIREMENTS_prices_unified.md
  // ============================================================

  /// Scrive un blocco di prezzi arrivati da RTDB. Chiamata una volta per set:
  /// il volume e' quello di un'espansione (poche migliaia di righe al massimo),
  /// non dell'intero listino.
  Future<void> upsertUnifiedPrices(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'card_prices',
        {...r, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Sostituisce i prezzi di un set: cancella i vecchi e inserisce i nuovi in
  /// un'unica transazione, cosi' una stampa sparita dal listino non resta in
  /// giro con un prezzo fossile.
  Future<void> replaceSetPrices(
    String catalog,
    String setCode,
    List<Map<String, Object?>> rows,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'card_prices',
        where: 'catalog = ? AND set_code = ?',
        whereArgs: [catalog, setCode],
      );
      if (rows.isEmpty) return;
      final now = DateTime.now().toIso8601String();
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert(
          'card_prices',
          {...r, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Prezzo di una stampa. Lookup diretto sulla chiave primaria: nessun
  /// matching, nessuna scansione (era il costo del vecchio percorso).
  Future<Map<String, dynamic>?> getUnifiedPrice({
    required String catalog,
    required String printId,
    required String lang,
  }) async {
    if (printId.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'card_prices',
      where: 'catalog = ? AND print_id = ? AND lang = ?',
      whereArgs: [catalog, printId, lang.toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Tutti i prezzi di una stampa, una riga per lingua.
  Future<List<Map<String, dynamic>>> getUnifiedPricesForPrint({
    required String catalog,
    required String printId,
  }) async {
    if (printId.isEmpty) return const [];
    final db = await database;
    return db.query(
      'card_prices',
      where: 'catalog = ? AND print_id = ?',
      whereArgs: [catalog, printId],
      orderBy: 'lang ASC',
    );
  }

  /// Versioni dei set gia' scaricati per [catalog]: e' il gate che evita di
  /// riscaricare cio' che non e' cambiato.
  Future<Map<String, int>> getPriceSetVersions(String catalog) async {
    final db = await database;
    final rows = await db.query(
      'price_set_versions',
      columns: ['set_code', 'version'],
      where: 'catalog = ?',
      whereArgs: [catalog],
    );
    return {
      for (final r in rows) r['set_code'] as String: r['version'] as int,
    };
  }

  Future<void> setPriceSetVersion(
    String catalog,
    String setCode,
    int version,
  ) async {
    final db = await database;
    await db.insert(
      'price_set_versions',
      {'catalog': catalog, 'set_code': setCode, 'version': version},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Risolve il `print_id` di una carta a partire da cio' che la collezione
  /// utente conserva (`catalogId`, `serialNumber`, `rarity`).
  ///
  /// E' il ponte fra il mondo "carta posseduta" e i prezzi pubblicati dal
  /// worker. Per la maggior parte dei cataloghi non serve nemmeno una query:
  ///
  ///  - **flat (9 cataloghi)**: `getGenericCatalogCards` espone `api_id AS id`,
  ///    quindi `catalogId` E' gia' il blueprint CardTrader;
  ///  - **onepiece**: `getOnepieceCatalogCards` espone `op.card_set_id AS setCode`,
  ///    quindi `serialNumber` contiene il blueprint ("UP-244190" → 244190);
  ///  - **pokemon / magic**: `catalogId` e' l'id locale, serve un salto a `api_id`;
  ///  - **yugioh**: unico caso composito — servono `set_code` e `rarity_code`
  ///    della lingua giusta, e il seriale posseduto e' quello localizzato
  ///    (JUSH-IT040), quindi si cerca su tutte le colonne per lingua.
  ///
  /// Restituisce stringa vuota se non risolvibile: il chiamante ricade sul
  /// percorso storico invece di mostrare un prezzo sbagliato.
  Future<String> resolvePrintId({
    required String catalog,
    String? catalogId,
    String? serialNumber,
    String? rarity,
  }) async {
    final id = catalogId?.trim() ?? '';
    final serial = serialNumber?.trim() ?? '';

    switch (familyOf(catalog)) {
      case PrintFamily.flat:
        // `catalogId` E' quasi sempre gia' l'api_id (getGenericCatalogCards
        // espone `api_id AS id`), ma un id locale autoincrement e' anch'esso
        // numerico: senza consultare la tabella, "7" verrebbe scambiato per il
        // blueprint 7. La query risolve entrambi i casi in un colpo, ed e' su
        // colonne indicizzate (api_id UNIQUE, id PK).
        final viaTable = await _apiIdBlueprint(
          '${genericTablePrefix(catalog) ?? catalog}_cards',
          id,
        );
        if (viaTable.isNotEmpty) return viaTable;
        // Catalogo non scaricato o carta non in tabella: si prende il valore
        // cosi' com'e'. Se non e' un blueprint valido il lookup non trovera'
        // nulla, che e' preferibile al prezzo di un'altra stampa.
        final direct = blueprintFromCompositeId(id);
        return RegExp(r'^\d+$').hasMatch(direct) ? direct : '';

      case PrintFamily.onepiece:
        // Prima la tabella, POI il seriale. Dal rebuild del 03/09/2026
        // `card_set_id` e' il numero di collezione vero ("OP01-064"), non piu'
        // l'id del blueprint travestito ("OP01-244442"): dedurre il blueprint
        // dal seriale darebbe "064", cioe' il prezzo di un'altra carta. Il
        // seriale resta un ripiego per i cataloghi non ancora ricostruiti.
        final viaPrint = await _onepieceBlueprintFromCard(id, serial);
        if (viaPrint.isNotEmpty) return viaPrint;
        final fromSerial = blueprintFromCompositeId(serial);
        // Un blueprint CardTrader ha 5-6 cifre; "064" e' un numero di
        // collezione, e prenderlo per un blueprint significa mostrare il prezzo
        // di una carta a caso.
        return RegExp(r'^\d{5,}$').hasMatch(fromSerial) ? fromSerial : '';

      case PrintFamily.pokemon:
        return _apiIdBlueprint('pokemon_cards', id);

      case PrintFamily.magic:
        // Gli uuid Scryfall passano di qui senza query; un id locale no.
        if (id.contains('-') && !RegExp(r'^\d+$').hasMatch(id)) {
          return magicPrintId(id, foil: false);
        }
        final apiId = await _lookupApiId('magic_cards', id);
        return apiId.isEmpty ? '' : magicPrintId(apiId, foil: false);

      case PrintFamily.yugioh:
        return _yugiohPrintIdFor(id, serial, rarity);
    }
  }

  /// `api_id` → blueprint, per le tabelle che hanno la colonna.
  Future<String> _apiIdBlueprint(String table, String catalogId) async {
    final apiId = await _lookupApiId(table, catalogId);
    if (apiId.isEmpty) return '';
    final bp = blueprintFromCompositeId(apiId);
    return RegExp(r'^\d+$').hasMatch(bp) ? bp : '';
  }

  /// Cerca `api_id` per id locale oppure per api_id stesso: quale dei due
  /// finisca in `cards.catalogId` dipende dal catalogo, e provarli entrambi
  /// costa una query sola.
  Future<String> _lookupApiId(String table, String catalogId) async {
    if (catalogId.isEmpty) return '';
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT api_id FROM $table WHERE api_id = ? OR CAST(id AS TEXT) = ? '
        // A parita' di candidati vince il match esatto su api_id: senza ORDER BY
        // l'esito dipenderebbe dall'ordine di scansione.
        'ORDER BY CASE WHEN api_id = ? THEN 0 ELSE 1 END LIMIT 1',
        [catalogId, catalogId, catalogId],
      );
      return rows.isEmpty ? '' : (rows.first['api_id'] as String? ?? '');
    } catch (_) {
      // Tabella assente: catalogo mai scaricato.
      return '';
    }
  }

  /// Blueprint di una stampa One Piece: dalla colonna `blueprint_id` se c'e',
  /// altrimenti dal `card_set_id` dei cataloghi vecchi, dove il blueprint era
  /// il suffisso del seriale.
  ///
  /// La ricerca parte dal seriale, che identifica la stampa anche quando
  /// `catalogId` non e' quello locale: le carte gia' in collezione hanno il
  /// seriale con cui furono aggiunte.
  Future<String> _onepieceBlueprintFromCard(String catalogId, String serial) async {
    if (catalogId.isEmpty && serial.isEmpty) return '';
    try {
      final db = await database;
      final rows = serial.isNotEmpty
          ? await db.rawQuery(
              'SELECT card_set_id, blueprint_id FROM onepiece_prints '
              'WHERE card_set_id = ? OR card_id = ? LIMIT 20',
              [serial, catalogId],
            )
          : await db.rawQuery(
              'SELECT card_set_id, blueprint_id FROM onepiece_prints '
              'WHERE card_id = ? LIMIT 20',
              [catalogId],
            );
      // Se il seriale c'e', vince la riga che gli corrisponde: le altre sono
      // stampe diverse della stessa carta, con un prezzo diverso.
      final exact = rows.where((r) => r['card_set_id'] == serial);
      for (final r in [...exact, ...rows]) {
        final explicit = (r['blueprint_id'] as String? ?? '').trim();
        if (RegExp(r'^\d+$').hasMatch(explicit)) return explicit;
        final bp = blueprintFromCompositeId(r['card_set_id']);
        if (RegExp(r'^\d{5,}$').hasMatch(bp)) return bp;
      }
    } catch (_) {}
    return '';
  }

  /// Lingue con colonne dedicate in `yugioh_prints` (l'inglese sta nelle
  /// colonne senza suffisso). 'sp' e' lo spagnolo del catalogo, che CardTrader
  /// e quindi il worker chiamano 'es'.
  static const _yugiohLangSuffixes = ['', '_it', '_fr', '_de', '_pt', '_sp'];

  Future<String> _yugiohPrintIdFor(
    String catalogId,
    String serial,
    String? rarity,
  ) async {
    if (catalogId.isEmpty || serial.isEmpty) return '';
    final cols = <String>['card_id'];
    for (final suffix in _yugiohLangSuffixes) {
      cols.add('set_code$suffix');
      cols.add('rarity_code$suffix');
      cols.add('rarity$suffix');
    }
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT ${cols.join(', ')} FROM yugioh_prints WHERE card_id = ? LIMIT 60',
        [catalogId],
      );
      if (rows.isEmpty) return '';

      final wantedRarity = (rarity?.trim() ?? '').toLowerCase();
      final serialLc = serial.toLowerCase();
      Map<String, dynamic>? fallback;
      String fallbackSuffix = '';

      for (final row in rows) {
        for (final suffix in _yugiohLangSuffixes) {
          final code = (row['set_code$suffix'] as String? ?? '').toLowerCase();
          if (code.isEmpty || code != serialLc) continue;
          // Stesso set_code su piu' righe = stampe di rarita' diversa, con
          // prezzi molto distanti: si disambigua con la rarita' posseduta.
          final rowRarity =
              (row['rarity$suffix'] as String? ?? '').toLowerCase();
          if (wantedRarity.isNotEmpty && rowRarity != wantedRarity) {
            fallback ??= row;
            if (fallback == row) fallbackSuffix = suffix;
            continue;
          }
          return yugiohPrintId(
            row['card_id'],
            row['set_code$suffix'],
            row['rarity_code$suffix'],
          );
        }
      }
      if (fallback != null) {
        return yugiohPrintId(
          fallback['card_id'],
          fallback['set_code$fallbackSuffix'],
          fallback['rarity_code$fallbackSuffix'],
        );
      }
    } catch (_) {}
    return '';
  }

  /// Riporta al seriale vero le carte in collezione che ne avevano copiato uno
  /// finto, e restituisce quante righe ha corretto.
  ///
  /// Fino al 03/09/2026 i rebuild scrivevano l'id del blueprint CardTrader dove
  /// l'app mostra il seriale, perché leggevano un endpoint che non espone il
  /// collector number (vedi `deck-master-worker` 813dc65). Ricostruire il
  /// catalogo corregge lo scaffale ma non ciò che l'utente ha già in
  /// collezione: quelle carte hanno copiato il numero sbagliato al momento
  /// dell'aggiunta.
  ///
  /// Si tocca il dato dell'utente solo perché la corrispondenza è **esatta e
  /// deterministica** — il vecchio seriale ERA il blueprint (o
  /// "{set}-{blueprint}"), quindi la riga da correggere si riconosce senza
  /// ambiguità. Ogni seriale che non combacia resta dov'è.
  Future<int> repairOwnedSerials(String catalog) async {
    final db = await database;
    // Yu-Gi-Oh e Magic non sono mai passati da CardTrader per il seriale:
    // niente da riparare.
    final String sql;
    switch (catalog) {
      case 'onepiece':
        sql = '''
          UPDATE cards SET serialNumber = (
            SELECT op.card_set_id FROM onepiece_prints op
            WHERE op.blueprint_id IS NOT NULL
              AND op.set_id || '-' || op.blueprint_id = cards.serialNumber
              AND op.card_set_id != cards.serialNumber
            LIMIT 1)
          WHERE collection = 'onepiece' AND EXISTS (
            SELECT 1 FROM onepiece_prints op
            WHERE op.blueprint_id IS NOT NULL
              AND op.set_id || '-' || op.blueprint_id = cards.serialNumber
              AND op.card_set_id != cards.serialNumber)
        ''';
      case 'pokemon':
        // Il vecchio seriale era il blueprint nudo, che è anche il suffisso di
        // `api_id`: si accetta la riga solo se i due coincidono.
        sql = '''
          UPDATE cards SET serialNumber = (
            SELECT pp.set_code FROM pokemon_cards pc
            JOIN pokemon_prints pp ON pp.card_id = pc.id
            WHERE (pc.api_id = cards.catalogId OR CAST(pc.id AS TEXT) = cards.catalogId)
              AND SUBSTR(pc.api_id, LENGTH(pc.api_id) - LENGTH(cards.serialNumber))
                  = '-' || cards.serialNumber
              AND pp.set_code != cards.serialNumber
            LIMIT 1)
          WHERE collection = 'pokemon' AND EXISTS (
            SELECT 1 FROM pokemon_cards pc
            JOIN pokemon_prints pp ON pp.card_id = pc.id
            WHERE (pc.api_id = cards.catalogId OR CAST(pc.id AS TEXT) = cards.catalogId)
              AND SUBSTR(pc.api_id, LENGTH(pc.api_id) - LENGTH(cards.serialNumber))
                  = '-' || cards.serialNumber
              AND pp.set_code != cards.serialNumber)
        ''';
      default:
        final prefix = genericTablePrefix(catalog);
        if (prefix == null) return 0;
        // Nei cataloghi flat il seriale mostrato era `api_id` per mancanza di
        // `card_number`: si sostituisce solo dove il numero vero ora esiste.
        sql = '''
          UPDATE cards SET serialNumber = (
            SELECT gc.card_number FROM ${prefix}_cards gc
            WHERE gc.api_id = cards.serialNumber
              AND gc.card_number IS NOT NULL AND gc.card_number != ''
            LIMIT 1)
          WHERE collection = ? AND EXISTS (
            SELECT 1 FROM ${prefix}_cards gc
            WHERE gc.api_id = cards.serialNumber
              AND gc.card_number IS NOT NULL AND gc.card_number != '')
        ''';
    }
    try {
      final args = catalog == 'onepiece' || catalog == 'pokemon'
          ? <Object?>[]
          : <Object?>[catalog];
      return await db.rawUpdate(sql, args);
    } catch (_) {
      // Tabelle di catalogo assenti: catalogo mai scaricato, niente da fare.
      return 0;
    }
  }

  /// Codici espansione di cui l'utente possiede almeno una carta in [catalog],
  /// normalizzati come le chiavi dei set su RTDB (`/p/{cat}/s/{set}`).
  ///
  /// Serve a scaricare solo i set che servono davvero: su Yu-Gi-Oh sono una
  /// manciata contro 490. Un insieme vuoto significa "non lo so": chi chiama
  /// scarica tutto, che e' preferibile a lasciare la collezione senza prezzi.
  ///
  /// Da dove viene il codice espansione cambia per famiglia:
  ///  - yugioh e onepiece ce l'hanno nel seriale ("JUSH-IT040", "OP01-064");
  ///  - pokemon nel prefisso di `api_id` ("pr1-273488");
  ///  - flat e magic in una colonna della carta di catalogo.
  Future<Set<String>> getOwnedSetCodes(String catalog) async {
    final db = await database;
    // Prefisso del seriale fino al primo trattino, in minuscolo.
    const serialPrefix =
        "LOWER(SUBSTR(c.serialNumber, 1, INSTR(c.serialNumber, '-') - 1))";
    final sql = switch (catalog) {
      'yugioh' || 'onepiece' =>
        'SELECT DISTINCT $serialPrefix AS code FROM cards c '
            "WHERE c.collection = ? AND INSTR(c.serialNumber, '-') > 1",
      'pokemon' =>
        'SELECT DISTINCT LOWER(SUBSTR(pc.api_id, 1, '
            "INSTR(pc.api_id, '-') - 1)) AS code "
            'FROM cards c JOIN pokemon_cards pc '
            '  ON pc.api_id = c.catalogId OR CAST(pc.id AS TEXT) = c.catalogId '
            "WHERE c.collection = ? AND INSTR(pc.api_id, '-') > 1",
      'magic' => 'SELECT DISTINCT LOWER(mc.set_code) AS code '
          'FROM cards c JOIN magic_cards mc '
          '  ON mc.api_id = c.catalogId OR CAST(mc.id AS TEXT) = c.catalogId '
          "WHERE c.collection = ? AND mc.set_code IS NOT NULL AND mc.set_code != ''",
      _ => () {
          final prefix = genericTablePrefix(catalog);
          if (prefix == null) return null;
          return 'SELECT DISTINCT LOWER(gc.set_code) AS code '
              'FROM cards c JOIN ${prefix}_cards gc '
              '  ON gc.api_id = c.catalogId OR CAST(gc.id AS TEXT) = c.catalogId '
              "WHERE c.collection = ? AND gc.set_code IS NOT NULL AND gc.set_code != ''";
        }(),
    };
    if (sql == null) return const {};
    try {
      final rows = await db.rawQuery(sql, [catalog]);
      return {
        for (final r in rows)
          if ((r['code'] as String? ?? '').isNotEmpty) r['code'] as String,
      };
    } catch (_) {
      // Tabella di catalogo assente: non e' un errore, e' un catalogo mai
      // scaricato. Si scarica tutto.
      return const {};
    }
  }

  /// Le carte in collezione di [catalog], con i soli campi che servono a
  /// risolverne la stampa. Il volume e' quello della collezione dell'utente
  /// (centinaia di righe), non del catalogo.
  Future<List<Map<String, dynamic>>> getCollectionCardsForPricing(
    String catalog,
  ) async {
    final db = await database;
    return db.rawQuery(
      'SELECT id, catalogId, serialNumber, rarity, quantity, cardtrader_value '
      'FROM cards WHERE collection = ?',
      [catalog],
    );
  }

  /// Aggiorna `cardtrader_value` in blocco. [values] mappa l'id riga di `cards`
  /// al valore in euro.
  Future<int> updateCardtraderValues(Map<int, double?> values) async {
    if (values.isEmpty) return 0;
    final db = await database;
    var updated = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();
      values.forEach((id, value) {
        batch.update(
          'cards',
          {'cardtrader_value': value},
          where: 'id = ?',
          whereArgs: [id],
        );
        updated++;
      });
      await batch.commit(noResult: true);
    });
    return updated;
  }

  /// Quante righe prezzo sono in cache, per catalogo — diagnostica.
  Future<int> countUnifiedPrices(String catalog) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM card_prices WHERE catalog = ?',
      [catalog],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Table prefixes for all v36 "generic" catalog tables (see [genericTablePrefix]).
  static const _genericCatalogPrefixes = [
    'digimon', 'lorcana', 'fab', 'vanguard', 'dragonball',
    'starwars', 'riftbound', 'gundam', 'union_arena',
  ];

  Future<void> _addFirestoreSyncSupport(DatabaseExecutor db) async {
    // Add firestoreId columns to user data tables
    await db.execute('ALTER TABLE albums ADD COLUMN firestoreId TEXT');
    await db.execute('ALTER TABLE cards ADD COLUMN firestoreId TEXT');
    await db.execute('ALTER TABLE decks ADD COLUMN firestoreId TEXT');

    // Create pending_sync table for offline queue
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_sync(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        change_type TEXT NOT NULL,
        data TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_sync_table ON pending_sync(table_name)');
  }

  Future<void> _addCatalogMetadata(DatabaseExecutor db) async {
    // Create catalog_metadata table for tracking catalog versions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_metadata(
        catalog_name TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        total_cards INTEGER NOT NULL,
        total_chunks INTEGER NOT NULL,
        last_updated TEXT NOT NULL,
        downloaded_at TEXT NOT NULL
      )
    ''');
  }

  /// Aggiunge una colonna solo se non esiste già (sicuro da chiamare in migrazioni).
  Future<void> _addColumnIfMissing(DatabaseExecutor db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => c['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _createYugiohTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS yugioh_cards(
        id INTEGER PRIMARY KEY,
        type TEXT NOT NULL,
        human_readable_type TEXT,
        frame_type TEXT,
        race TEXT,
        archetype TEXT,
        ygoprodeck_url TEXT,
        atk INTEGER,
        def INTEGER,
        level INTEGER,
        attribute TEXT,
        scale INTEGER,
        linkval INTEGER,
        linkmarkers TEXT,
        name TEXT NOT NULL,
        description TEXT,
        image_url TEXT,
        name_it TEXT,
        description_it TEXT,
        name_fr TEXT,
        description_fr TEXT,
        name_de TEXT,
        description_de TEXT,
        name_pt TEXT,
        description_pt TEXT,
        name_sp TEXT,
        description_sp TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS yugioh_prints(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id INTEGER NOT NULL,
        set_code TEXT NOT NULL,
        set_name TEXT,
        rarity TEXT,
        rarity_code TEXT,
        set_price REAL,
        artwork TEXT,
        set_name_it TEXT,
        set_code_it TEXT,
        rarity_it TEXT,
        rarity_code_it TEXT,
        set_price_it REAL,
        set_name_fr TEXT,
        set_code_fr TEXT,
        rarity_fr TEXT,
        rarity_code_fr TEXT,
        set_price_fr REAL,
        set_name_de TEXT,
        set_code_de TEXT,
        rarity_de TEXT,
        rarity_code_de TEXT,
        set_price_de REAL,
        set_name_pt TEXT,
        set_code_pt TEXT,
        rarity_pt TEXT,
        rarity_code_pt TEXT,
        set_price_pt REAL,
        set_name_sp TEXT,
        set_code_sp TEXT,
        rarity_sp TEXT,
        rarity_code_sp TEXT,
        set_price_sp REAL,
        set_id TEXT,
        ct_synced_at TEXT,
        ct_listing_count INTEGER,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (card_id) REFERENCES yugioh_cards(id) ON DELETE CASCADE,
        UNIQUE(card_id, set_code, rarity)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS yugioh_prices(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        print_id INTEGER NOT NULL,
        language TEXT NOT NULL,
        cardmarket_price REAL,
        tcgplayer_price REAL,
        ebay_price REAL,
        amazon_price REAL,
        coolstuffinc_price REAL,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (print_id) REFERENCES yugioh_prints(id) ON DELETE CASCADE,
        UNIQUE(print_id, language)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_metadata(
        catalog_name TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        total_cards INTEGER NOT NULL,
        total_chunks INTEGER NOT NULL,
        last_updated TEXT NOT NULL,
        downloaded_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateYugiohData(Database db) async {
    // Check if there's any yugioh data to migrate
    final count = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM catalog_cards WHERE collection = 'yugioh'"
    );
    if ((count.first['cnt'] as int? ?? 0) == 0) return;

    // Migrate card definitions
    await db.execute('''
      INSERT OR IGNORE INTO yugioh_cards (
        id, type, human_readable_type, frame_type, race, archetype,
        ygoprodeck_url, atk, def, level, attribute, scale, linkval, linkmarkers,
        name, description, created_at, updated_at
      )
      SELECT CAST(id AS INTEGER), type, humanReadableCardType, frameType, race, archetype,
        ygoprodeck_url, atk, def, level, attribute, scale, linkval, linkmarkers,
        name, description, datetime('now'), datetime('now')
      FROM catalog_cards
      WHERE collection = 'yugioh'
    ''');

    // Migrate print/set data
    await db.execute('''
      INSERT OR IGNORE INTO yugioh_prints (
        card_id, set_code, set_name, rarity, rarity_code, set_price, artwork,
        created_at, updated_at
      )
      SELECT CAST(cardId AS INTEGER), setCode, setName, setRarity, rarityCode, setPrice, imageUrl,
        datetime('now'), datetime('now')
      FROM catalog_card_sets
      WHERE cardId IN (SELECT id FROM catalog_cards WHERE collection = 'yugioh')
    ''');

    // Clean up old yugioh data from generic tables
    await db.execute(
      "DELETE FROM catalog_card_sets WHERE cardId IN (SELECT id FROM catalog_cards WHERE collection = 'yugioh')"
    );
    await db.execute("DELETE FROM catalog_cards WHERE collection = 'yugioh'");
  }

  Future<void> _createOnepieceTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS onepiece_cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        card_type TEXT,
        color TEXT,
        cost INTEGER,
        power INTEGER,
        life INTEGER,
        sub_types TEXT,
        counter_amount INTEGER,
        attribute TEXT,
        card_text TEXT,
        image_url TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS onepiece_prints(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id INTEGER NOT NULL,
        card_set_id TEXT NOT NULL,
        blueprint_id TEXT,
        set_id TEXT,
        set_name TEXT,
        rarity TEXT,
        inventory_price REAL,
        market_price REAL,
        market_price_en REAL,
        market_price_fr REAL,
        market_price_ko REAL,
        market_price_zh REAL,
        artwork TEXT,
        set_name_jp TEXT,
        rarity_jp TEXT,
        set_name_fr TEXT,
        rarity_fr TEXT,
        set_name_it TEXT,
        rarity_it TEXT,
        set_name_de TEXT,
        rarity_de TEXT,
        set_name_pt TEXT,
        rarity_pt TEXT,
        set_name_sp TEXT,
        rarity_sp TEXT,
        set_name_ko TEXT,
        rarity_ko TEXT,
        set_name_zh TEXT,
        rarity_zh TEXT,
        ct_synced_at TEXT,
        ct_listing_count INTEGER,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (card_id) REFERENCES onepiece_cards(id) ON DELETE CASCADE,
        UNIQUE(card_set_id)
      )
    ''');
  }

  Future<void> _createPokemonTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pokemon_cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        api_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        supertype TEXT,
        subtype TEXT,
        hp INTEGER,
        types TEXT,
        rarity TEXT,
        set_id TEXT,
        set_name TEXT,
        set_series TEXT,
        number TEXT,
        image_url TEXT,
        name_it TEXT,
        name_fr TEXT,
        name_de TEXT,
        name_es TEXT,
        name_pt TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pokemon_prints(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id INTEGER NOT NULL,
        set_code TEXT NOT NULL,
        set_name TEXT,
        rarity TEXT,
        set_price REAL,
        artwork TEXT,
        set_code_it TEXT,
        set_name_it TEXT,
        rarity_it TEXT,
        set_price_it REAL,
        set_code_fr TEXT,
        set_name_fr TEXT,
        rarity_fr TEXT,
        set_price_fr REAL,
        set_code_de TEXT,
        set_name_de TEXT,
        rarity_de TEXT,
        set_price_de REAL,
        set_code_es TEXT,
        set_name_es TEXT,
        rarity_es TEXT,
        set_price_es REAL,
        set_code_pt TEXT,
        set_name_pt TEXT,
        rarity_pt TEXT,
        set_price_pt REAL,
        ct_synced_at TEXT,
        ct_listing_count INTEGER,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (card_id) REFERENCES pokemon_cards(id) ON DELETE CASCADE,
        UNIQUE(card_id, set_code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pokemon_prices(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        print_id INTEGER NOT NULL,
        language TEXT NOT NULL,
        cardmarket_price REAL,
        tcgplayer_price REAL,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (print_id) REFERENCES pokemon_prints(id) ON DELETE CASCADE,
        UNIQUE(print_id, language)
      )
    ''');
  }

  Future<void> _createMagicTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS magic_cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        api_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        mana_cost TEXT,
        cmc REAL,
        type_line TEXT,
        oracle_text TEXT,
        power TEXT,
        toughness TEXT,
        colors TEXT,
        rarity TEXT,
        set_code TEXT,
        set_name TEXT,
        collector_number TEXT,
        image_url TEXT,
        price_eur REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        name_it TEXT, type_line_it TEXT, oracle_text_it TEXT,
        name_fr TEXT, type_line_fr TEXT, oracle_text_fr TEXT,
        name_de TEXT, type_line_de TEXT, oracle_text_de TEXT,
        name_pt TEXT, type_line_pt TEXT, oracle_text_pt TEXT,
        name_sp TEXT, type_line_sp TEXT, oracle_text_sp TEXT,
        name_jp TEXT, type_line_jp TEXT, oracle_text_jp TEXT,
        name_ko TEXT, type_line_ko TEXT, oracle_text_ko TEXT,
        name_zh TEXT, type_line_zh TEXT, oracle_text_zh TEXT
      )
    ''');
  }

  Future<void> _createNewCollectionTables(DatabaseExecutor db) async {
    // Helper: creates a generic cards+prints pair for a collection.
    // tableName: e.g. 'digimon'  → creates digimon_cards + digimon_prints
    Future<void> createPair(String t) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${t}_cards(
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          api_id       TEXT    NOT NULL UNIQUE,
          name         TEXT    NOT NULL,
          card_type    TEXT,
          subtype      TEXT,
          rarity       TEXT,
          cost         TEXT,
          power        TEXT,
          defense      TEXT,
          effect       TEXT,
          set_code     TEXT,
          set_name     TEXT,
          card_number  TEXT,
          image_url    TEXT,
          name_it      TEXT,
          effect_it    TEXT,
          name_fr      TEXT,
          effect_fr    TEXT,
          name_de      TEXT,
          effect_de    TEXT,
          name_pt      TEXT,
          effect_pt    TEXT,
          created_at   TEXT NOT NULL,
          updated_at   TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${t}_prints(
          id                 INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id            INTEGER NOT NULL REFERENCES ${t}_cards(id) ON DELETE CASCADE,
          set_code           TEXT,
          set_name           TEXT,
          rarity             TEXT,
          set_price          REAL,
          set_name_it        TEXT,
          set_code_it        TEXT,
          rarity_it          TEXT,
          set_price_it       REAL,
          set_name_fr        TEXT,
          set_code_fr        TEXT,
          rarity_fr          TEXT,
          set_price_fr       REAL,
          set_name_de        TEXT,
          set_code_de        TEXT,
          rarity_de          TEXT,
          set_price_de       REAL,
          set_name_pt        TEXT,
          set_code_pt        TEXT,
          rarity_pt          TEXT,
          set_price_pt       REAL,
          ct_synced_at       TEXT,
          ct_listing_count   INTEGER,
          UNIQUE(card_id, set_code, rarity)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_cards_api_id ON ${t}_cards(api_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_prints_card_id ON ${t}_prints(card_id)');
    }

    await createPair('digimon');
    await createPair('dragonball');
    await createPair('lorcana');
    await createPair('fab');
    await createPair('vanguard');
    await createPair('starwars');
    await createPair('riftbound');
    await createPair('gundam');
    await createPair('union_arena');
  }

  /// Inserisce o aggiorna una carta Magic per api_id.
  Future<int> upsertMagicCard(Map<String, dynamic> card) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query('magic_cards', where: 'api_id = ?', whereArgs: [card['api_id']], limit: 1);
    if (existing.isNotEmpty) {
      await db.update('magic_cards', {...card, 'updated_at': now}, where: 'api_id = ?', whereArgs: [card['api_id']]);
      return existing.first['id'] as int;
    } else {
      return db.insert('magic_cards', {...card, 'created_at': now, 'updated_at': now});
    }
  }

  /// Bulk-insert carte Magic da Firestore. Usa INSERT OR REPLACE per aggiornare esistenti.
  Future<void> insertMagicCards(
    List<Map<String, dynamic>> cards, {
    void Function(double progress)? onProgress,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        await txn.insert('magic_cards', {
          'api_id':           card['api_id'] ?? card['id'],
          'name':             card['name'] ?? '',
          'mana_cost':        card['mana_cost'],
          'cmc':              card['cmc'],
          'type_line':        card['type'] ?? card['type_line'],
          'oracle_text':      card['oracle_text'],
          'power':            card['power'],
          'toughness':        card['toughness'],
          'colors':           card['colors'],
          'rarity':           card['rarity'],
          'set_code':         card['set_code'],
          'set_name':         card['set_name'],
          'collector_number': card['collector_number'],
          'image_url':        card['imageUrl'] ?? card['image_url'],
          'price_eur':        card['price_eur'],
          'created_at':       now,
          'updated_at':       now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (onProgress != null && i % 100 == 0) {
          onProgress(i / cards.length);
        }
      }
    });
    onProgress?.call(1.0);
  }

  Future<void> clearMagicCatalog() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('magic_cards');
      await txn.delete('catalog_metadata', where: 'catalog_name = ?', whereArgs: ['magic']);
    });
  }

  Future<void> deleteMagicCardsByApiIds(List<String> apiIds) async {
    if (apiIds.isEmpty) return;
    final db = await database;
    for (int i = 0; i < apiIds.length; i += 500) {
      final batch = apiIds.sublist(i, (i + 500 < apiIds.length) ? i + 500 : apiIds.length);
      final placeholders = batch.map((_) => '?').join(',');
      await db.delete('magic_cards', where: 'api_id IN ($placeholders)', whereArgs: batch);
    }
  }

  // ============================================================
  // Generic new-collection catalog methods (v36)
  // Maps: catalog key → SQL table prefix
  // ============================================================

  /// catalog key → SQL table name prefix for v36 collections.
  static String? genericTablePrefix(String catalogKey) => const {
    'digimon':          'digimon',
    'lorcana':          'lorcana',
    'flesh-and-blood':  'fab',
    'vanguard':         'vanguard',
    'dragon-ball-super':'dragonball',
    'star-wars':        'starwars',
    'riftbound':        'riftbound',
    'gundam':           'gundam',
    'union-arena':      'union_arena',
  }[catalogKey];

  /// Bulk-insert or replace cards into a generic v36 catalog table.
  /// [tablePrefix] is one of: digimon, lorcana, fab, vanguard, dragonball,
  /// starwars, riftbound, gundam, union_arena.
  Future<void> insertGenericCatalogCards(
    String tablePrefix,
    List<Map<String, dynamic>> cards, {
    void Function(double progress)? onProgress,
  }) async {
    if (cards.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (int i = 0; i < cards.length; i++) {
        final c = cards[i];
        await txn.insert(
          '${tablePrefix}_cards',
          {
            'api_id':    c['api_id']?.toString() ?? '',
            'name':      c['name']?.toString() ?? '',
            'card_type': c['card_type']?.toString(),
            'subtype':   c['subtype']?.toString(),
            'rarity':    c['rarity']?.toString(),
            'cost':      c['cost']?.toString(),
            'power':     c['power']?.toString(),
            'defense':   c['defense']?.toString(),
            'effect':    c['effect']?.toString(),
            'set_code':  c['set_code']?.toString(),
            'set_name':  c['set_name']?.toString(),
            'card_number': c['card_number']?.toString(),
            // La colonna esisteva dalla v36 e `getGenericCatalogCards` la
            // legge come `artwork`, ma nessuno ci scriveva: i nove cataloghi
            // generici restavano senza immagini qualunque cosa pubblicasse il
            // worker. Vale qualsiasi URL assoluto — quelli CardTrader si
            // caricano direttamente, e la migrazione li sostituira' con B2.
            'image_url': c['image_url']?.toString() ?? c['imageUrl']?.toString(),
            'name_it':   c['name_it']?.toString(),
            'effect_it': c['effect_it']?.toString(),
            'name_fr':   c['name_fr']?.toString(),
            'effect_fr': c['effect_fr']?.toString(),
            'name_de':   c['name_de']?.toString(),
            'effect_de': c['effect_de']?.toString(),
            'name_pt':   c['name_pt']?.toString(),
            'effect_pt': c['effect_pt']?.toString(),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (onProgress != null && i % 200 == 0) {
          onProgress(i / cards.length);
        }
      }
    });
    onProgress?.call(1.0);
  }

  Future<void> clearGenericCatalog(String catalogKey) async {
    final prefix = genericTablePrefix(catalogKey);
    if (prefix == null) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('${prefix}_cards');
      await txn.delete('catalog_metadata',
          where: 'catalog_name = ?', whereArgs: [catalogKey]);
    });
  }

  Future<void> deleteGenericCardsByApiIds(
      String tablePrefix, List<String> apiIds) async {
    if (apiIds.isEmpty) return;
    final db = await database;
    for (int i = 0; i < apiIds.length; i += 500) {
      final batch = apiIds.sublist(
          i, (i + 500 < apiIds.length) ? i + 500 : apiIds.length);
      final placeholders = batch.map((_) => '?').join(',');
      await db.delete('${tablePrefix}_cards',
          where: 'api_id IN ($placeholders)', whereArgs: batch);
    }
  }

  Future<Map<String, dynamic>?> getMagicCardById(int id) async {
    final db = await database;
    final rows = await db.query('magic_cards', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Restituisce i "prints" di una carta Magic come lista singola (Scryfall card = print unico).
  Future<List<Map<String, dynamic>>> getMagicCardPrints(int cardId) async {
    final db = await database;
    final rows = await db.query('magic_cards', where: 'id = ?', whereArgs: [cardId], limit: 1);
    if (rows.isEmpty) return [];
    final c = rows.first;
    final setCode = c['set_code'] as String? ?? '';
    final collector = c['collector_number'] as String? ?? '';
    return [{
      'setCode': '$setCode-$collector',
      'setName': c['set_name'] ?? '',
      'setRarity': c['rarity'] ?? '',
      'rarity': c['rarity'] ?? '',
      'marketPrice': (c['price_eur'] as num?)?.toDouble() ?? 0.0,
      'artwork': c['image_url'],
    }];
  }

  /// Queries local `magic_cards` table (downloaded from Firestore) and returns
  /// cards in the same map format used by the catalog page.
  ///
  /// [language] controls which localized columns (`name_<lang>`,
  /// `type_line_<lang>`, `oracle_text_<lang>`) are preferred via COALESCE —
  /// falls back to the EN base column when the translation hasn't been
  /// synced yet, so selecting a non-EN language never returns an empty list.
  Future<List<Map<String, dynamic>>> getMagicCardsLocal({
    String? query,
    String language = 'EN',
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final suffix = _langSuffix(language);
    final hasLang = suffix.isNotEmpty;

    final nameCol = hasLang ? 'COALESCE(name$suffix, name)' : 'name';
    final typeCol = hasLang ? 'COALESCE(type_line$suffix, type_line)' : 'type_line';
    final textCol = hasLang ? 'COALESCE(oracle_text$suffix, oracle_text)' : 'oracle_text';

    final String where;
    final List<dynamic> args;
    if (query != null && query.trim().isNotEmpty) {
      where = 'WHERE (name LIKE ? OR $nameCol LIKE ? OR api_id LIKE ? OR set_code LIKE ?)';
      args = ['%$query%', '%$query%', '%$query%', '%$query%'];
    } else {
      where = '';
      args = [];
    }
    final rows = await db.rawQuery('''
      SELECT id, api_id, name, type_line, oracle_text, rarity,
             set_code, set_name, collector_number, image_url, price_eur,
             $nameCol AS localized_name,
             $typeCol AS localized_type,
             $textCol AS localized_oracle_text
      FROM magic_cards
      $where
      ORDER BY set_code ASC, collector_number ASC
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);
    return rows.map((c) {
      final setCode  = (c['set_code']  as String? ?? '').toUpperCase();
      final collector = c['collector_number'] as String? ?? '';
      return {
        'id':                   c['id'],
        'catalogId':            c['api_id'],
        'name':                 c['name'],
        'localizedName':        c['localized_name'],
        'description':          c['oracle_text'],
        'localizedDescription': c['localized_oracle_text'],
        'type':                 c['type_line'],
        'localizedType':        c['localized_type'],
        'rarity':               c['rarity'],
        'setCode':              '$setCode-$collector',
        'localizedSetCode':     '$setCode-$collector',
        'setName':              c['set_name'],
        'localizedSetName':     c['set_name'],
        'setRarity':            c['rarity'],
        'localizedRarity':      c['rarity'],
        'marketPrice':          (c['price_eur'] as num?)?.toDouble() ?? 0.0,
        'artwork':              c['image_url'],
        'collection':           'magic',
        'isOwned':              0,
      };
    }).toList();
  }

  Future _onCreate(Database db, int version) async {
    // Prezzi unificati: le stesse tabelle create dalla migrazione v41, perche'
    // un'installazione nuova non passa da _onUpgrade.
    await _createUnifiedPriceTables(db);

    await db.execute('''
      CREATE TABLE albums(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        collection TEXT,
        maxCapacity INTEGER,
        firestoreId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        catalogId TEXT,
        name TEXT,
        type TEXT,
        description TEXT,
        collection TEXT,
        imageUrl TEXT,
        serialNumber TEXT,
        albumId INTEGER,
        rarity TEXT,
        quantity INTEGER,
        value REAL,
        previous_value REAL,
        cardtrader_value REAL,
        purchase_price REAL,
        firestoreId TEXT,
        added_at TEXT,
        FOREIGN KEY (albumId) REFERENCES albums (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE catalog_cards(
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        humanReadableCardType TEXT,
        frameType TEXT,
        description TEXT,
        atk INTEGER,
        def INTEGER,
        level INTEGER,
        race TEXT,
        attribute TEXT,
        archetype TEXT,
        scale INTEGER,
        linkval INTEGER,
        linkmarkers TEXT,
        ygoprodeck_url TEXT,
        collection TEXT,
        imageUrl TEXT,
        imageUrlSmall TEXT,
        imageUrlCropped TEXT,
        isOwned INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE catalog_card_sets(
        cardId TEXT,
        setName TEXT,
        setCode TEXT,
        setRarity TEXT,
        rarityCode TEXT,
        setPrice REAL,
        imageUrl TEXT,
        imageUrlSmall TEXT,
        quantity INTEGER DEFAULT 0,
        FOREIGN KEY (cardId) REFERENCES catalog_cards (id)
      )
    ''');

    await db.execute('CREATE INDEX idx_catalog_card_sets_cardId ON catalog_card_sets (cardId)');
    await db.execute('CREATE INDEX idx_catalog_cards_collection ON catalog_cards (collection)');
    await db.execute('CREATE INDEX idx_catalog_card_sets_lookup ON catalog_card_sets (cardId, setCode)');

    await db.execute('''
      CREATE TABLE decks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        collection TEXT,
        firestoreId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE deck_cards(
        deckId INTEGER,
        cardId INTEGER,
        quantity INTEGER,
        PRIMARY KEY (deckId, cardId),
        FOREIGN KEY (deckId) REFERENCES decks (id) ON DELETE CASCADE,
        FOREIGN KEY (cardId) REFERENCES cards (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE collections(
        id TEXT PRIMARY KEY,
        name TEXT,
        isUnlocked INTEGER
      )
    ''');

    await db.insert('collections', {'id': 'yugioh',          'name': 'Yu-Gi-Oh!',              'isUnlocked': 0});
    await db.insert('collections', {'id': 'pokemon',         'name': 'Pokémon',                 'isUnlocked': 0});
    await db.insert('collections', {'id': 'magic',           'name': 'Magic: The Gathering',    'isUnlocked': 0});
    await db.insert('collections', {'id': 'onepiece',        'name': 'One Piece',               'isUnlocked': 0});
    await db.insert('collections', {'id': 'digimon',         'name': 'Digimon Card Game',       'isUnlocked': 0});
    await db.insert('collections', {'id': 'dragon-ball-super','name': 'Dragon Ball Super',      'isUnlocked': 0});
    await db.insert('collections', {'id': 'lorcana',         'name': 'Disney Lorcana',          'isUnlocked': 0});
    await db.insert('collections', {'id': 'flesh-and-blood', 'name': 'Flesh and Blood',         'isUnlocked': 0});
    await db.insert('collections', {'id': 'vanguard',        'name': 'Cardfight!! Vanguard',    'isUnlocked': 0});
    await db.insert('collections', {'id': 'star-wars',       'name': 'Star Wars: Unlimited',    'isUnlocked': 0});
    await db.insert('collections', {'id': 'riftbound',       'name': 'Riftbound',               'isUnlocked': 0});
    await db.insert('collections', {'id': 'gundam',          'name': 'Gundam Card Game',        'isUnlocked': 0});
    await db.insert('collections', {'id': 'union-arena',     'name': 'Union Arena',             'isUnlocked': 0});

    // Create yugioh-specific tables
    await _createYugiohTables(db);

    // Create One Piece-specific tables
    await _createOnepieceTables(db);

    // Create Pokémon-specific tables
    await _createPokemonTables(db);

    // Create Magic: The Gathering tables
    await _createMagicTables(db);

    // Create new collection tables (v36)
    await _createNewCollectionTables(db);

    // Create pending_sync table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_sync(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        change_type TEXT NOT NULL,
        data TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_sync_table ON pending_sync(table_name)');

    // Create cardtrader_prices cache table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cardtrader_prices (
        blueprint_id        INTEGER NOT NULL,
        catalog             TEXT    NOT NULL,
        expansion_code      TEXT    NOT NULL,
        card_name_en        TEXT    NOT NULL,
        language            TEXT    NOT NULL,
        first_edition       INTEGER NOT NULL DEFAULT 0,
        rarity              TEXT    NOT NULL DEFAULT '',
        collector_number    TEXT    NOT NULL DEFAULT '',
        min_price_nm_cents  INTEGER,
        min_price_any_cents INTEGER,
        listing_count       INTEGER NOT NULL DEFAULT 0,
        synced_at           TEXT    NOT NULL,
        PRIMARY KEY (blueprint_id, language, first_edition, rarity)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ct_prices_lookup '
      'ON cardtrader_prices(catalog, expansion_code, card_name_en)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ct_prices_collector '
      'ON cardtrader_prices(catalog, expansion_code, collector_number)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_history (
        blueprint_id  INTEGER NOT NULL,
        language      TEXT    NOT NULL,
        first_edition INTEGER NOT NULL DEFAULT 0,
        rarity        TEXT    NOT NULL DEFAULT '',
        price_cents   INTEGER NOT NULL,
        listing_count INTEGER NOT NULL DEFAULT 0,
        recorded_date TEXT    NOT NULL,
        PRIMARY KEY (blueprint_id, language, first_edition, rarity, recorded_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS collection_value_history (
        collection    TEXT    NOT NULL,
        total_cents   INTEGER NOT NULL,
        recorded_date TEXT    NOT NULL,
        PRIMARY KEY (collection, recorded_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wishlist (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        catalogId    TEXT    NOT NULL,
        name         TEXT    NOT NULL,
        collection   TEXT    NOT NULL,
        imageUrl     TEXT,
        serialNumber TEXT,
        rarity       TEXT,
        target_price REAL,
        added_at     TEXT    NOT NULL
      )
    ''');

    // Dedicated expansion and rarity tables (v18)
    await _createExpansionRarityTables(db);

    // Colonne e indici di match per i prezzi CardTrader (v40)
    await _createPriceMatchKeys(db);
  }

  Future<void> _createExpansionRarityTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_expansions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        catalog     TEXT NOT NULL,
        set_id      TEXT,
        set_name    TEXT NOT NULL,
        set_name_it TEXT,
        set_name_fr TEXT,
        set_name_de TEXT,
        set_name_es TEXT,
        set_name_pt TEXT,
        set_name_sp TEXT,
        set_name_ko TEXT,
        set_name_zh TEXT,
        UNIQUE(catalog, set_name)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cat_expansions_catalog '
      'ON catalog_expansions(catalog)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_rarities (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        catalog     TEXT NOT NULL,
        rarity      TEXT NOT NULL,
        rarity_code TEXT,
        rarity_it   TEXT,
        rarity_fr   TEXT,
        rarity_de   TEXT,
        rarity_es   TEXT,
        rarity_pt   TEXT,
        rarity_sp   TEXT,
        rarity_ko   TEXT,
        rarity_zh   TEXT,
        UNIQUE(catalog, rarity)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cat_rarities_catalog '
      'ON catalog_rarities(catalog)',
    );
  }

  // ── Expansion / Rarity population helpers ───────────────────────────────────

  Future<void> _populateExpansionsFromPrints(DatabaseExecutor db, String catalog) async {
    List<Map<String, dynamic>> rows;
    if (catalog == 'yugioh') {
      rows = await db.rawQuery('''
        SELECT set_name,
               MIN(set_name_it) AS set_name_it,
               MIN(set_name_fr) AS set_name_fr,
               MIN(set_name_de) AS set_name_de,
               MIN(set_name_pt) AS set_name_pt,
               MIN(set_name_sp) AS set_name_sp,
               MIN(COALESCE(set_id,
                 CASE WHEN set_code != '' AND INSTR(set_code,'-') > 0
                      THEN SUBSTR(set_code,1,INSTR(set_code,'-')-1)
                      WHEN set_code != '' THEN set_code ELSE NULL END
               )) AS set_id
        FROM yugioh_prints
        WHERE set_name IS NOT NULL AND set_name != ''
        GROUP BY set_name
      ''');
    } else if (catalog == 'pokemon') {
      rows = await db.rawQuery('''
        SELECT pp.set_name,
               MIN(pp.set_name_it) AS set_name_it,
               MIN(pp.set_name_fr) AS set_name_fr,
               MIN(pp.set_name_de) AS set_name_de,
               MIN(pp.set_name_es) AS set_name_es,
               MIN(pp.set_name_pt) AS set_name_pt,
               NULL AS set_name_sp,
               MIN(pc.set_id) AS set_id
        FROM pokemon_prints pp
        JOIN pokemon_cards pc ON pp.card_id = pc.id
        WHERE pp.set_name IS NOT NULL AND pp.set_name != ''
        GROUP BY pp.set_name
      ''');
    } else if (catalog == 'onepiece') {
      rows = await db.rawQuery('''
        SELECT set_name,
               NULL AS set_name_it, NULL AS set_name_fr,
               NULL AS set_name_de, NULL AS set_name_pt, NULL AS set_name_sp,
               MIN(set_name_ko) AS set_name_ko, MIN(set_name_zh) AS set_name_zh,
               MIN(set_id) AS set_id
        FROM onepiece_prints
        WHERE set_name IS NOT NULL AND set_name != ''
        GROUP BY set_name
      ''');
    } else {
      return;
    }
    for (final row in rows) {
      await db.insert('catalog_expansions', {
        'catalog':     catalog,
        'set_id':      row['set_id'],
        'set_name':    row['set_name'],
        'set_name_it': row['set_name_it'],
        'set_name_fr': row['set_name_fr'],
        'set_name_de': row['set_name_de'],
        if (row.containsKey('set_name_es')) 'set_name_es': row['set_name_es'],
        'set_name_pt': row['set_name_pt'],
        'set_name_sp': row['set_name_sp'],
        if (row.containsKey('set_name_ko')) 'set_name_ko': row['set_name_ko'],
        if (row.containsKey('set_name_zh')) 'set_name_zh': row['set_name_zh'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _populateRaritiesFromPrints(DatabaseExecutor db, String catalog) async {
    List<Map<String, dynamic>> rows;
    if (catalog == 'yugioh') {
      rows = await db.rawQuery('''
        SELECT rarity, MIN(rarity_code) AS rarity_code,
               MIN(rarity_it) AS rarity_it, MIN(rarity_fr) AS rarity_fr,
               MIN(rarity_de) AS rarity_de, MIN(rarity_pt) AS rarity_pt,
               MIN(rarity_sp) AS rarity_sp
        FROM yugioh_prints
        WHERE rarity IS NOT NULL AND rarity != ''
        GROUP BY rarity
      ''');
    } else if (catalog == 'pokemon') {
      rows = await db.rawQuery('''
        SELECT rarity, NULL AS rarity_code,
               MIN(rarity_it) AS rarity_it, MIN(rarity_fr) AS rarity_fr,
               MIN(rarity_de) AS rarity_de, MIN(rarity_es) AS rarity_es,
               MIN(rarity_pt) AS rarity_pt, NULL AS rarity_sp
        FROM pokemon_prints
        WHERE rarity IS NOT NULL AND rarity != ''
        GROUP BY rarity
      ''');
    } else if (catalog == 'onepiece') {
      rows = await db.rawQuery('''
        SELECT rarity, NULL AS rarity_code,
               NULL AS rarity_it, NULL AS rarity_fr,
               NULL AS rarity_de, NULL AS rarity_pt, NULL AS rarity_sp,
               MIN(rarity_ko) AS rarity_ko, MIN(rarity_zh) AS rarity_zh
        FROM onepiece_prints
        WHERE rarity IS NOT NULL AND rarity != ''
        GROUP BY rarity
      ''');
    } else {
      return;
    }
    for (final row in rows) {
      await db.insert('catalog_rarities', {
        'catalog':    catalog,
        'rarity':     row['rarity'],
        'rarity_code':row['rarity_code'],
        'rarity_it':  row['rarity_it'],
        'rarity_fr':  row['rarity_fr'],
        'rarity_de':  row['rarity_de'],
        if (row.containsKey('rarity_es')) 'rarity_es': row['rarity_es'],
        'rarity_pt':  row['rarity_pt'],
        'rarity_sp':  row['rarity_sp'],
        if (row.containsKey('rarity_ko')) 'rarity_ko': row['rarity_ko'],
        if (row.containsKey('rarity_zh')) 'rarity_zh': row['rarity_zh'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ── Public expansion/rarity CRUD ────────────────────────────────────────────

  /// Returns all expansions for [catalog] ordered by set_name.
  Future<List<Map<String, dynamic>>> getExpansions(String catalog) async {
    final db = await database;
    return db.query('catalog_expansions',
        where: 'catalog = ?', whereArgs: [catalog], orderBy: 'set_name ASC');
  }

  /// Returns all rarities for [catalog] ordered by rarity.
  Future<List<Map<String, dynamic>>> getRarities(String catalog) async {
    final db = await database;
    return db.query('catalog_rarities',
        where: 'catalog = ?', whereArgs: [catalog], orderBy: 'rarity ASC');
  }

  /// Upserts a single expansion row (insert or replace on conflict).
  Future<void> upsertExpansion(String catalog, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('catalog_expansions', {'catalog': catalog, ...data},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Upserts a single rarity row.
  Future<void> upsertRarity(String catalog, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('catalog_rarities', {'catalog': catalog, ...data},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Rebuilds catalog_expansions and catalog_rarities from current prints data.
  /// Called after a full catalog download to keep tables in sync.
  Future<void> rebuildExpansionsAndRarities(String catalog) async {
    final db = await database;
    await db.delete('catalog_expansions', where: 'catalog = ?', whereArgs: [catalog]);
    await db.delete('catalog_rarities',   where: 'catalog = ?', whereArgs: [catalog]);
    await _populateExpansionsFromPrints(db, catalog);
    await _populateRaritiesFromPrints(db, catalog);
  }

  /// Renames an expansion's EN name and propagates to all matching prints.
  Future<void> renameExpansion(String catalog, String oldName, String newName) async {
    if (oldName == newName || newName.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('catalog_expansions', {'set_name': newName},
          where: 'catalog = ? AND set_name = ?', whereArgs: [catalog, oldName]);
      await txn.update('${catalog}_prints', {'set_name': newName},
          where: 'set_name = ?', whereArgs: [oldName]);
    });
  }

  /// Updates translation columns for an expansion and propagates to all prints.
  Future<void> updateExpansionTranslations(
      String catalog, String setName, Map<String, String> translations) async {
    final db = await database;
    final updates = <String, dynamic>{};
    for (final e in translations.entries) {
      updates['set_name_${e.key}'] = e.value.isNotEmpty ? e.value : null;
    }
    if (updates.isEmpty) return;
    await db.transaction((txn) async {
      await txn.update('catalog_expansions', updates,
          where: 'catalog = ? AND set_name = ?', whereArgs: [catalog, setName]);
      await txn.update('${catalog}_prints', updates,
          where: 'set_name = ?', whereArgs: [setName]);
    });
  }

  /// Renames a rarity's EN name and propagates to all matching prints.
  Future<void> renameRarityEntry(String catalog, String oldRarity, String newRarity) async {
    if (oldRarity == newRarity || newRarity.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('catalog_rarities', {'rarity': newRarity},
          where: 'catalog = ? AND rarity = ?', whereArgs: [catalog, oldRarity]);
      await txn.update('${catalog}_prints', {'rarity': newRarity},
          where: 'rarity = ?', whereArgs: [oldRarity]);
    });
  }

  /// Updates translation columns for a rarity and propagates to all prints.
  Future<void> updateRarityEntryTranslations(
      String catalog, String rarity, Map<String, String> translations) async {
    final db = await database;
    final updates = <String, dynamic>{};
    for (final e in translations.entries) {
      updates['rarity_${e.key}'] = e.value.isNotEmpty ? e.value : null;
    }
    if (updates.isEmpty) return;
    await db.transaction((txn) async {
      await txn.update('catalog_rarities', updates,
          where: 'catalog = ? AND rarity = ?', whereArgs: [catalog, rarity]);
      await txn.update('${catalog}_prints', updates,
          where: 'rarity = ?', whereArgs: [rarity]);
    });
  }

  Future<void> clearAllCardData() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('cards');
      await txn.delete('catalog_cards');
      await txn.delete('catalog_card_sets');
      await txn.delete('deck_cards');
      await txn.delete('yugioh_prices');
      await txn.delete('yugioh_prints');
      await txn.delete('yugioh_cards');
    });
  }

  // ============================================================
  // Album Methods
  // ============================================================

  Future<int> insertAlbum(AlbumModel album) async {
    Database db = await database;
    return await db.insert('albums', album.toMap());
  }

  Future<List<AlbumModel>> getAlbumsByCollection(String collection) async {
    Database db = await database;
    // LEFT JOIN + GROUP BY is a single pass; avoids N correlated subqueries
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.id, a.name, a.collection, a.maxCapacity, a.firestoreId,
             COALESCE(SUM(c.quantity), 0) as currentCount
      FROM albums a
      LEFT JOIN cards c ON c.albumId = a.id
      WHERE a.collection = ?
      GROUP BY a.id, a.name, a.collection, a.maxCapacity, a.firestoreId
    ''', [collection]);
    return List.generate(maps.length, (i) => AlbumModel.fromMap(maps[i]));
  }

  Future<int> updateAlbum(AlbumModel album) async {
    Database db = await database;
    return await db.update(
      'albums',
      album.toMap(),
      where: 'id = ?',
      whereArgs: [album.id],
    );
  }

  Future<int> deleteAlbum(int id) async {
    Database db = await database;
    return await db.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // Card Methods (user-owned instances)
  // ============================================================

  Future<int> insertCard(CardModel card) async {
    Database db = await database;
    return await db.transaction((txn) async {
      final map = card.toMap()
        ..['added_at'] = DateTime.now().toIso8601String();
      int id = await txn.insert('cards', map);

      if (card.catalogId != null && card.collection != 'yugioh') {
        // Legacy catalog tracking for non-yugioh collections
        await txn.execute('''
          UPDATE catalog_cards SET isOwned = 1 WHERE id = ?
        ''', [card.catalogId]);

        await txn.execute('''
          UPDATE catalog_card_sets
          SET quantity = quantity + ?
          WHERE cardId = ? AND setCode = ?
        ''', [card.quantity, card.catalogId, card.serialNumber]);
      }

      return id;
    });
  }

  /// Returns the completion ratio (0.0–1.0) for each collection based on unique
  /// catalog entries owned vs total catalog entries in SQLite.
  Future<Map<String, double>> getCollectionCompletions() async {
    final db = await database;
    final completions = <String, double>{};

    int firstInt(List<Map<String, Object?>> rows) {
      if (rows.isEmpty) return 0;
      final v = rows.first.values.first;
      if (v is int) return v;
      return 0;
    }

    Future<double> ratio(String collection, String ownedQuery, List<dynamic> ownedArgs,
        String totalQuery) async {
      final owned = firstInt(await db.rawQuery(ownedQuery, ownedArgs));
      final total = firstInt(await db.rawQuery(totalQuery));
      return total > 0 ? (owned / total).clamp(0.0, 1.0) : 0.0;
    }

    completions['yugioh'] = await ratio(
      'yugioh',
      'SELECT COUNT(DISTINCT CAST(catalogId AS INTEGER)) FROM cards WHERE collection=? AND catalogId IS NOT NULL',
      ['yugioh'],
      'SELECT COUNT(*) FROM yugioh_cards',
    );

    completions['pokemon'] = await ratio(
      'pokemon',
      'SELECT COUNT(DISTINCT catalogId) FROM cards WHERE collection=? AND catalogId IS NOT NULL',
      ['pokemon'],
      'SELECT COUNT(*) FROM pokemon_cards',
    );

    completions['onepiece'] = await ratio(
      'onepiece',
      'SELECT COUNT(DISTINCT CAST(catalogId AS INTEGER)) FROM cards WHERE collection=? AND catalogId IS NOT NULL',
      ['onepiece'],
      'SELECT COUNT(*) FROM onepiece_cards',
    );

    // Collections without a local catalog yet — always 0% until catalog is added
    for (final key in [
      'magic', 'lorcana', 'riftbound', 'flesh_blood', 'starwars_unlimited',
      'digimon', 'dragonball', 'vanguard', 'weiss_schwarz', 'final_fantasy',
      'force_of_will', 'battle_spirits', 'wow', 'starwars_destiny',
      'dragoborne', 'little_pony', 'the_spoils',
    ]) {
      completions[key] = 0.0;
    }

    return completions;
  }

  /// Returns game-specific stats for a card (ATK/DEF for YGO, HP for Pokémon,
  /// Power/Cost for One Piece). Returns null when catalogId is missing/unknown.
  Future<Map<String, dynamic>?> getCardExtraInfo(
      String collection, String? catalogId) async {
    if (catalogId == null || catalogId.isEmpty) return null;
    final db = await database;

    if (collection == 'yugioh') {
      final id = int.tryParse(catalogId);
      if (id == null) return null;
      final rows = await db.query(
        'yugioh_cards',
        columns: ['atk', 'def', 'level', 'attribute', 'race',
                  'linkval', 'scale', 'human_readable_type'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }

    if (collection == 'onepiece') {
      final id = int.tryParse(catalogId);
      if (id == null) return null;
      final rows = await db.query(
        'onepiece_cards',
        columns: ['cost', 'power', 'color', 'counter_amount', 'attribute', 'life'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }

    if (collection == 'pokemon') {
      final id = int.tryParse(catalogId);
      final rows = id != null
          ? await db.query('pokemon_cards',
              columns: ['hp', 'types', 'supertype', 'subtype'],
              where: 'id = ?', whereArgs: [id], limit: 1)
          : await db.query('pokemon_cards',
              columns: ['hp', 'types', 'supertype', 'subtype'],
              where: 'api_id = ?', whereArgs: [catalogId], limit: 1);
      return rows.isEmpty ? null : rows.first;
    }

    return null;
  }

  // Returns all owned card instances for a collection.
  // Used only to build _ownedQuantityMap (needs catalogId, serialNumber, quantity).
  // All fields are already stored in the cards table at insert time.
  Future<List<CardModel>> getCardsWithCatalog(String collection) async {
    Database db = await database;
    final maps = await db.rawQuery('''
      SELECT c.*
      FROM cards c
      LEFT JOIN albums a ON a.id = c.albumId
      WHERE c.collection = ? OR a.collection = ?
    ''', [collection, collection]);
    return maps.map((row) => CardModel.fromMap(row)).toList();
  }

  /// Returns a lightweight map of catalogId+serialNumber → total quantity owned
  /// for a collection. Used by the catalog page badge overlay without loading
  /// full CardModel objects into memory.
  Future<Map<String, int>> getOwnedQuantityMap(String collection) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT c.catalogId, c.serialNumber, SUM(c.quantity) as qty
      FROM cards c
      LEFT JOIN albums a ON a.id = c.albumId
      WHERE c.collection = ? OR a.collection = ?
      GROUP BY c.catalogId, c.serialNumber
    ''', [collection, collection]);
    final map = <String, int>{};
    for (final r in rows) {
      final key = '${r['catalogId']}-${r['serialNumber']}';
      map[key] = (r['qty'] as num?)?.toInt() ?? 0;
    }
    return map;
  }

  /// Finds cards matching the given serial+rarity+catalogId inside a set of album IDs.
  /// Used by adjustCardQuantity to avoid loading the entire collection into memory.
  Future<List<CardModel>> findCardsInAlbumsBySerial(
    Set<int> albumIds,
    String serialNumber,
    String rarity,
    String? catalogId,
  ) async {
    if (albumIds.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(albumIds.length, '?').join(',');
    final args = <dynamic>[...albumIds, serialNumber.toLowerCase(), rarity.toLowerCase()];
    final catalogClause = catalogId != null ? 'AND (catalogId IS NULL OR catalogId = ?)' : '';
    if (catalogId != null) args.add(catalogId);
    final rows = await db.rawQuery('''
      SELECT * FROM cards
      WHERE albumId IN ($placeholders)
        AND LOWER(serialNumber) = ?
        AND LOWER(rarity) = ?
        $catalogClause
    ''', args);
    return rows.map(CardModel.fromMap).toList();
  }

  /// Finds all cards across all albums matching serial+rarity+catalogId for a collection.
  Future<List<CardModel>> findRelatedCardsBySerial(
    String collection,
    String serialNumber,
    String rarity,
    String? catalogId,
  ) async {
    final db = await database;
    final args = <dynamic>[collection, serialNumber.toLowerCase(), rarity.toLowerCase()];
    final catalogClause = catalogId != null ? 'AND (catalogId IS NULL OR catalogId = ?)' : '';
    if (catalogId != null) args.add(catalogId);
    final rows = await db.rawQuery('''
      SELECT c.* FROM cards c
      LEFT JOIN albums a ON a.id = c.albumId
      WHERE (c.collection = ? OR a.collection = ?)
        AND LOWER(c.serialNumber) = ?
        AND LOWER(c.rarity) = ?
        $catalogClause
    ''', [collection, collection, ...args.skip(1)]);
    return rows.map(CardModel.fromMap).toList();
  }

  /// Deletes multiple cards by ID in a single SQL statement.
  Future<void> batchDeleteCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawDelete('DELETE FROM cards WHERE id IN ($placeholders)', ids);
  }

  Future<List<CardModel>> getCardsByCollection(String collection, {String language = 'en'}) async {
    Database db = await database;
    if (collection == 'yugioh') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, yc.name) as name,
               COALESCE(u.type, yc.type) as type,
               COALESCE(
                 CASE '$language'
                   WHEN 'it' THEN NULLIF(yc.description_it, '')
                   WHEN 'fr' THEN NULLIF(yc.description_fr, '')
                   WHEN 'de' THEN NULLIF(yc.description_de, '')
                   WHEN 'pt' THEN NULLIF(yc.description_pt, '')
                   WHEN 'es' THEN NULLIF(yc.description_sp, '')
                   WHEN 'sp' THEN NULLIF(yc.description_sp, '')
                 END,
                 u.description,
                 yc.description
               ) as description,
               COALESCE(u.collection, a.collection, 'yugioh') as collection,
               COALESCE(
                 NULLIF(u.value, 0),
                 (SELECT CASE
                    WHEN set_code_it = u.serialNumber THEN COALESCE(set_price_it, set_price)
                    WHEN set_code_fr = u.serialNumber THEN COALESCE(set_price_fr, set_price)
                    WHEN set_code_de = u.serialNumber THEN COALESCE(set_price_de, set_price)
                    WHEN set_code_pt = u.serialNumber THEN COALESCE(set_price_pt, set_price)
                    WHEN set_code_sp = u.serialNumber THEN COALESCE(set_price_sp, set_price)
                    ELSE set_price
                  END
                  FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber OR set_code_sp = u.serialNumber)
                  LIMIT 1)
               ) as value,
               COALESCE(
                 (SELECT artwork FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber OR set_code_sp = u.serialNumber)
                  LIMIT 1),
                 u.imageUrl
               ) as imageUrl,
               COALESCE(
                 (SELECT CASE
                    WHEN set_code_it = u.serialNumber THEN COALESCE(set_price_it, set_price)
                    WHEN set_code_fr = u.serialNumber THEN COALESCE(set_price_fr, set_price)
                    WHEN set_code_de = u.serialNumber THEN COALESCE(set_price_de, set_price)
                    WHEN set_code_pt = u.serialNumber THEN COALESCE(set_price_pt, set_price)
                    WHEN set_code_sp = u.serialNumber THEN COALESCE(set_price_sp, set_price)
                    ELSE set_price
                  END
                  FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber OR set_code_sp = u.serialNumber)
                  LIMIT 1),
                 u.cardtrader_value
               ) as cardtrader_value,
               (SELECT ct_synced_at FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber OR set_code_sp = u.serialNumber)
                  LIMIT 1) as ct_synced_at,
               (SELECT ct_listing_count FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber OR set_code_sp = u.serialNumber)
                  LIMIT 1) as ct_listing_count
        FROM cards u
        LEFT JOIN yugioh_cards yc ON yc.id = CAST(u.catalogId AS INTEGER)
        LEFT JOIN albums a ON a.id = u.albumId
        WHERE u.collection = 'yugioh' OR a.collection = 'yugioh'
      ''');
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    if (collection == 'onepiece') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, oc.name) as name,
               COALESCE(u.type, oc.card_type) as type,
               COALESCE(u.description, oc.card_text) as description,
               COALESCE(u.collection, a.collection, 'onepiece') as collection,
               COALESCE(
                 NULLIF(u.value, 0),
                 CASE '$language'
                   WHEN 'en' THEN COALESCE(op.market_price_en, op.market_price)
                   WHEN 'fr' THEN COALESCE(op.market_price_fr, op.market_price)
                   WHEN 'ko' THEN COALESCE(op.market_price_ko, op.market_price)
                   WHEN 'zh' THEN COALESCE(op.market_price_zh, op.market_price)
                   ELSE op.market_price
                 END
               ) as value,
               COALESCE(op.artwork, oc.image_url, u.imageUrl) as imageUrl,
               COALESCE(
                 CASE '$language'
                   WHEN 'en' THEN COALESCE(op.market_price_en, op.market_price)
                   WHEN 'fr' THEN COALESCE(op.market_price_fr, op.market_price)
                   WHEN 'ko' THEN COALESCE(op.market_price_ko, op.market_price)
                   WHEN 'zh' THEN COALESCE(op.market_price_zh, op.market_price)
                   ELSE op.market_price
                 END,
                 u.cardtrader_value
               ) as cardtrader_value,
               op.ct_synced_at,
               op.ct_listing_count
        FROM cards u
        LEFT JOIN onepiece_cards oc ON oc.id = CAST(u.catalogId AS INTEGER)
        LEFT JOIN onepiece_prints op ON op.card_id = oc.id AND op.card_set_id = u.serialNumber
        LEFT JOIN albums a ON a.id = u.albumId
        WHERE u.collection = 'onepiece' OR a.collection = 'onepiece'
      ''');
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    if (collection == 'pokemon') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, pc.name) as name,
               COALESCE(u.type, pc.supertype) as type,
               COALESCE(u.collection, a.collection, 'pokemon') as collection,
               COALESCE(
                 NULLIF(u.value, 0),
                 (SELECT CASE '$language'
                    WHEN 'it' THEN COALESCE(set_price_it, set_price)
                    WHEN 'fr' THEN COALESCE(set_price_fr, set_price)
                    WHEN 'de' THEN COALESCE(set_price_de, set_price)
                    WHEN 'es' THEN COALESCE(set_price_es, set_price)
                    WHEN 'pt' THEN COALESCE(set_price_pt, set_price)
                    ELSE set_price
                  END
                  FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_es = u.serialNumber OR set_code_pt = u.serialNumber)
                  LIMIT 1)
               ) as value,
               COALESCE(
                 (SELECT artwork FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_es = u.serialNumber OR set_code_pt = u.serialNumber)
                  LIMIT 1),
                 pc.image_url,
                 u.imageUrl
               ) as imageUrl,
               COALESCE(
                 (SELECT CASE '$language'
                      WHEN 'it' THEN COALESCE(set_price_it, set_price)
                      WHEN 'fr' THEN COALESCE(set_price_fr, set_price)
                      WHEN 'de' THEN COALESCE(set_price_de, set_price)
                      WHEN 'es' THEN COALESCE(set_price_es, set_price)
                      WHEN 'pt' THEN COALESCE(set_price_pt, set_price)
                      ELSE set_price
                    END
                    FROM pokemon_prints
                    WHERE card_id = pc.id
                      AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                        OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                        OR set_code_es = u.serialNumber OR set_code_pt = u.serialNumber)
                    LIMIT 1),
                 u.cardtrader_value
               ) as cardtrader_value,
               (SELECT ct_synced_at FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_es = u.serialNumber OR set_code_pt = u.serialNumber)
                  LIMIT 1) as ct_synced_at,
               (SELECT ct_listing_count FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_es = u.serialNumber OR set_code_pt = u.serialNumber)
                  LIMIT 1) as ct_listing_count
        FROM cards u
        LEFT JOIN pokemon_cards pc ON (pc.id = CAST(u.catalogId AS INTEGER) OR pc.api_id = u.catalogId)
        LEFT JOIN albums a ON a.id = u.albumId
        WHERE u.collection = 'pokemon' OR a.collection = 'pokemon'
      ''');
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    // v36 generic catalogs (digimon, lorcana, fab, etc.) use {prefix}_cards tables,
    // not catalog_cards. Join directly to get localized effect/description.
    final prefix = genericTablePrefix(collection);
    if (prefix != null) {
      final effectCol = switch (language) {
        'it' => 'effect_it',
        'fr' => 'effect_fr',
        'de' => 'effect_de',
        'pt' => 'effect_pt',
        _    => null,
      };
      final descExpr = effectCol != null
          ? 'COALESCE(NULLIF(gc.$effectCol, ""), gc.effect, u.description)'
          : 'COALESCE(gc.effect, u.description)';
      final maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(gc.name, u.name)        as name,
               COALESCE(gc.card_type, u.type)   as type,
               $descExpr                         as description,
               COALESCE(u.collection, a.collection, ?) as collection,
               COALESCE(gc.image_url, u.imageUrl) as imageUrl
        FROM cards u
        LEFT JOIN ${prefix}_cards gc ON gc.id = CAST(u.catalogId AS INTEGER)
        LEFT JOIN albums a ON a.id = u.albumId
        WHERE u.collection = ? OR a.collection = ?
      ''', [collection, collection, collection]);
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    // Legacy catalog_cards fallback (old YGO-style schema).
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT u.*,
             COALESCE(c.name, u.name) as name,
             COALESCE(c.type, u.type) as type,
             COALESCE(c.description, u.description) as description,
             COALESCE(c.collection, u.collection) as collection,
             COALESCE(c.imageUrl, u.imageUrl) as imageUrl
      FROM cards u
      LEFT JOIN catalog_cards c ON u.catalogId = c.id
      LEFT JOIN albums a ON a.id = u.albumId
      WHERE u.collection = ? OR a.collection = ?
    ''', [collection, collection]);
    return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
  }

  Future<List<CardModel>> findOwnedInstances(String collection, String name, String serialNumber, String rarity) async {
    Database db = await database;
    if (collection == 'yugioh') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, yc.name) as name,
               COALESCE(u.type, yc.type) as type,
               COALESCE(u.description, yc.description) as description,
               u.collection,
               COALESCE(
                 (SELECT artwork FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber OR set_code_sp = u.serialNumber)
                  LIMIT 1),
                 u.imageUrl
               ) as imageUrl
        FROM cards u
        LEFT JOIN yugioh_cards yc ON yc.id = CAST(u.catalogId AS INTEGER)
        WHERE u.collection = 'yugioh' AND (yc.name = ? OR u.name = ?) AND u.serialNumber = ? AND u.rarity = ?
      ''', [name, name, serialNumber, rarity]);
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    if (collection == 'onepiece') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, oc.name) as name,
               COALESCE(u.type, oc.card_type) as type,
               COALESCE(u.description, oc.card_text) as description,
               u.collection,
               COALESCE(
                 op.artwork,
                 oc.image_url,
                 u.imageUrl
               ) as imageUrl
        FROM cards u
        LEFT JOIN onepiece_cards oc ON oc.id = CAST(u.catalogId AS INTEGER)
        LEFT JOIN onepiece_prints op ON op.card_id = oc.id AND op.card_set_id = u.serialNumber
        WHERE u.collection = 'onepiece' AND (oc.name = ? OR u.name = ?) AND u.serialNumber = ? AND u.rarity = ?
      ''', [name, name, serialNumber, rarity]);
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    if (collection == 'pokemon') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, pc.name) as name,
               COALESCE(u.type, pc.supertype) as type,
               u.collection,
               COALESCE(
                 (SELECT artwork FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber)
                  LIMIT 1),
                 pc.image_url,
                 u.imageUrl
               ) as imageUrl
        FROM cards u
        LEFT JOIN pokemon_cards pc ON (pc.id = CAST(u.catalogId AS INTEGER) OR pc.api_id = u.catalogId)
        WHERE u.collection = 'pokemon' AND (pc.name = ? OR u.name = ?) AND u.serialNumber = ? AND u.rarity = ?
      ''', [name, name, serialNumber, rarity]);
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT u.*,
             COALESCE(c.name, u.name) as name,
             COALESCE(c.type, u.type) as type,
             COALESCE(c.description, u.description) as description,
             COALESCE(c.collection, u.collection) as collection,
             COALESCE(c.imageUrl, u.imageUrl) as imageUrl
      FROM cards u
      LEFT JOIN catalog_cards c ON u.catalogId = c.id
      WHERE u.collection = ? AND (c.name = ? OR u.name = ?) AND u.serialNumber = ? AND u.rarity = ?
    ''', [collection, name, name, serialNumber, rarity]);
    return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
  }

  Future<int> deleteCard(int id) async {
    Database db = await database;

    return await db.transaction((txn) async {
      final List<Map<String, dynamic>> cards = await txn.query('cards', where: 'id = ?', whereArgs: [id]);
      if (cards.isNotEmpty) {
        final card = cards.first;
        final String? catalogId = card['catalogId'] as String?;
        final String collection = card['collection'] as String? ?? '';
        final String serialNumber = card['serialNumber'] as String? ?? '';
        final int quantity = card['quantity'] as int;

        if (catalogId != null && collection != 'yugioh') {
          // Legacy catalog tracking for non-yugioh
          await txn.execute('''
            UPDATE catalog_card_sets
            SET quantity = quantity - ?
            WHERE cardId = ? AND setCode = ?
          ''', [quantity, catalogId, serialNumber]);

          final List<Map<String, dynamic>> remaining = await txn.rawQuery('''
            SELECT SUM(quantity) as total FROM cards WHERE catalogId = ? AND id != ?
          ''', [catalogId, id]);

          int totalRemaining = (remaining.first['total'] as num?)?.toInt() ?? 0;
          if (totalRemaining <= 0) {
            await txn.execute('UPDATE catalog_cards SET isOwned = 0 WHERE id = ?', [catalogId]);
          }
        }
      }
      return await txn.delete('cards', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> updateCard(CardModel card) async {
    Database db = await database;

    return await db.transaction((txn) async {
      final List<Map<String, dynamic>> oldCards = await txn.query('cards', where: 'id = ?', whereArgs: [card.id]);
      if (oldCards.isNotEmpty && card.catalogId != null && card.collection != 'yugioh') {
        // Legacy catalog tracking for non-yugioh
        final int oldQty = oldCards.first['quantity'] as int;
        final int delta = card.quantity - oldQty;

        await txn.execute('''
          UPDATE catalog_card_sets
          SET quantity = quantity + ?
          WHERE cardId = ? AND setCode = ?
        ''', [delta, card.catalogId, card.serialNumber]);

        final List<Map<String, dynamic>> totalResult = await txn.rawQuery('''
          SELECT (SELECT SUM(quantity) FROM cards WHERE catalogId = ? AND id != ?) + ? as total
        ''', [card.catalogId, card.id, card.quantity]);

        int totalOwned = (totalResult.first['total'] as num?)?.toInt() ?? card.quantity;

        await txn.execute(
          'UPDATE catalog_cards SET isOwned = ? WHERE id = ?',
          [totalOwned > 0 ? 1 : 0, card.catalogId]
        );
      }

      return await txn.update(
        'cards',
        card.toMap(),
        where: 'id = ?',
        whereArgs: [card.id],
      );
    });
  }

  Future<int> getCardCountByAlbum(int albumId) async {
    Database db = await database;
    final result = await db.rawQuery('SELECT SUM(quantity) as total FROM cards WHERE albumId = ?', [albumId]);
    return result.first['total'] as int? ?? 0;
  }

  /// Returns the total number of rows in the catalog table for [collectionKey].
  /// Returns 0 if the collection is unsupported or the table is empty.
  Future<int> getCatalogCardCount(String collectionKey) async {
    final table = switch (collectionKey) {
      'yugioh'   => 'yugioh_cards',
      'pokemon'  => 'pokemon_cards',
      'onepiece' => 'onepiece_cards',
      'magic'    => 'magic_cards',
      _          => null,
    };
    final db = await database;
    if (table != null) {
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $table');
      return result.first['cnt'] as int? ?? 0;
    }
    // v36 generic tables
    final prefix = genericTablePrefix(collectionKey);
    if (prefix == null) return 0;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM ${prefix}_cards');
    return result.first['cnt'] as int? ?? 0;
  }

  /// Queries a v36 generic catalog table and returns cards in the format
  /// expected by CatalogPage (same field names as the YGO/Pokemon/OP queries).
  Future<List<Map<String, dynamic>>> getGenericCatalogCards(
    String catalogKey, {
    String? query,
    String language = 'EN',
    int limit = 100,
    int offset = 0,
  }) async {
    final prefix = genericTablePrefix(catalogKey);
    if (prefix == null) return [];
    final db = await database;
    final langCol = switch (language.toUpperCase()) {
      'IT' => 'name_it',
      'FR' => 'name_fr',
      'DE' => 'name_de',
      'PT' => 'name_pt',
      _ => null,
    };
    final nameExpr = langCol != null
        ? 'COALESCE(NULLIF($langCol, ""), name)'
        : 'name';
    final effectCol = langCol?.replaceFirst('name_', 'effect_');
    final effectExpr = effectCol != null
        ? 'COALESCE(NULLIF($effectCol, ""), effect)'
        : 'effect';
    final where = (query != null && query.isNotEmpty)
        ? 'WHERE name LIKE ? OR $nameExpr LIKE ? OR api_id LIKE ?'
        : '';
    final args = (query != null && query.isNotEmpty)
        ? ['%$query%', '%$query%', '%$query%']
        : <dynamic>[];
    final rows = await db.rawQuery('''
      SELECT
        api_id          AS id,
        $nameExpr       AS name,
        COALESCE(NULLIF(card_number, ''), api_id) AS setCode,
        rarity,
        rarity          AS setRarity,
        image_url       AS artwork,
        card_type,
        $effectExpr     AS effect,
        set_code,
        set_name
      FROM ${prefix}_cards
      $where
      ORDER BY $nameExpr, api_id
      LIMIT $limit OFFSET $offset
    ''', args);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Returns an existing card in [albumId] with the same [catalogId], [serialNumber] and [rarity], or null.
  Future<CardModel?> findCardInAlbum(int albumId, String? catalogId, String serialNumber, String rarity) async {
    Database db = await database;
    final results = await db.query(
      'cards',
      where: 'albumId = ? AND catalogId = ? AND serialNumber = ? AND rarity = ?',
      whereArgs: [albumId, catalogId, serialNumber, rarity],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return CardModel.fromMap(results.first);
  }

  // ============================================================
  // Generic Catalog Methods (Pokemon, Magic, One Piece)
  // ============================================================

  Future<void> insertCatalogCards(List<Map<String, dynamic>> cards, {Function(double)? onProgress}) async {
    Database db = await database;

    await db.transaction((txn) async {
      int total = cards.length;
      const int batchSize = 500;

      for (int i = 0; i < total; i += batchSize) {
        int end = (i + batchSize < total) ? i + batchSize : total;
        List<Map<String, dynamic>> chunk = cards.sublist(i, end);

        Batch batch = txn.batch();
        for (var card in chunk) {
          final cardData = Map<String, dynamic>.from(card);
          final sets = cardData.remove('sets') as List<dynamic>?;

          batch.insert('catalog_cards', cardData, conflictAlgorithm: ConflictAlgorithm.ignore);
          batch.update('catalog_cards', cardData, where: 'id = ?', whereArgs: [cardData['id']]);

          if (sets != null) {
            for (var set in sets) {
              final String setCode = set['set_code'] ?? '';
              final setData = {
                'cardId': cardData['id'],
                'setName': set['set_name'],
                'setCode': setCode,
                'setRarity': set['set_rarity'],
                'rarityCode': set['set_rarity_code'],
                'setPrice': double.tryParse(set['set_price'].toString()) ?? 0.0,
                'imageUrl': set['image_url'],
                'imageUrlSmall': set['image_url_small'],
              };

              batch.update('catalog_card_sets', setData,
                  where: 'cardId = ? AND setCode = ?',
                  whereArgs: [cardData['id'], setCode]);

              batch.insert('catalog_card_sets', {
                ...setData,
                'quantity': 0,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
        await batch.commit(noResult: true);

        if (onProgress != null) {
          onProgress(end / total);
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCatalogCards(String collection, {String? query}) async {
    Database db = await database;
    if (query == null || query.isEmpty) {
      return await db.rawQuery('''
        SELECT c.*,
          s.setCode,
          s.setName,
          s.setRarity,
          s.rarityCode,
          s.setPrice,
          s.quantity as setQuantity,
          s.imageUrl as setImageUrl,
          s.imageUrlSmall as setImageUrlSmall
        FROM catalog_cards c
        INNER JOIN catalog_card_sets s ON c.id = s.cardId
        WHERE c.collection = ?
        ORDER BY c.name, s.setCode
      ''', [collection]);
    }

    return await db.rawQuery('''
      SELECT c.*,
        s.setCode,
        s.setName,
        s.setRarity,
        s.rarityCode,
        s.setPrice,
        s.quantity as setQuantity,
        s.imageUrl as setImageUrl,
        s.imageUrlSmall as setImageUrlSmall
      FROM catalog_cards c
      INNER JOIN catalog_card_sets s ON c.id = s.cardId
      WHERE c.collection = ? AND (c.name LIKE ? OR s.setCode LIKE ?)
      ORDER BY c.name, s.setCode
    ''', [collection, '%$query%', '%$query%']);
  }

  Future<List<Map<String, dynamic>>> getCardSets(String cardId) async {
    Database db = await database;
    return await db.query('catalog_card_sets', where: 'cardId = ?', whereArgs: [cardId]);
  }

  Future<int> getCatalogCount(String collection) async {
    if (collection == 'yugioh') {
      return getYugiohCatalogCount(); // yugioh_cards = carte uniche
    }
    if (collection == 'pokemon') {
      return getPokemonCatalogCount(); // pokemon_cards = carte uniche
    }
    if (collection == 'onepiece') {
      return getOnepieceCatalogCount(); // onepiece_cards = carte uniche
    }
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM catalog_cards WHERE collection = ?', [collection]);
    return result.first['count'] as int? ?? 0;
  }

  /// CTE `card_values`: il prezzo effettivo di ogni carta in collezione, per
  /// tutte le statistiche di valore (totale, per collezione, per rarità,
  /// snapshot storico).
  ///
  /// Parte da **tutte** le carte. Fino al 03/09/2026 era l'unione di tre SELECT
  /// (`WHERE collection = 'yugioh' | 'onepiece' | 'pokemon'`): le carte degli
  /// altri dieci cataloghi non comparivano proprio nella CTE, quindi Digimon,
  /// Lorcana, Flesh and Blood e compagnia valevano zero ovunque — mentre
  /// l'intestazione della lista, che calcola per conto suo
  /// ([_getEffectiveValue] in card_list_page), mostrava un prezzo per carta.
  /// Da qui la stranezza per cui una collezione con i prezzi in lista aveva
  /// totale zero.
  ///
  /// Ordine delle fonti, dal più affidabile:
  ///  1. `cardtrader_value` — prezzo di mercato del percorso unificato,
  ///     aggiornato a ogni sync prezzi. È l'unica fonte che esiste per tutti
  ///     e tredici i cataloghi.
  ///  2. il prezzo incorporato nelle tabelle di stampa, dove c'è (i tre
  ///     cataloghi storici).
  ///  3. `c.value`, che è solo un'istantanea del momento in cui la carta è
  ///     stata aggiunta (card_dialogs.dart la precompila col prezzo di catalogo
  ///     e non la aggiorna più): per una collezione tenuta a lungo si allontana
  ///     dal prezzo vero, quindi resta l'ultima spiaggia.
  static String _cardEffectiveValueCTE() => '''
    WITH card_values AS (
      SELECT c.collection, c.rarity, c.quantity,
        COALESCE(
          NULLIF(c.cardtrader_value, 0),
          CASE c.collection
            WHEN 'yugioh' THEN
              (SELECT CASE
                 WHEN yp.set_code_it = c.serialNumber THEN yp.set_price_it
                 WHEN yp.set_code_fr = c.serialNumber THEN yp.set_price_fr
                 WHEN yp.set_code_de = c.serialNumber THEN yp.set_price_de
                 WHEN yp.set_code_pt = c.serialNumber THEN yp.set_price_pt
                 WHEN yp.set_code_sp = c.serialNumber THEN yp.set_price_sp
                 ELSE yp.set_price
               END
               FROM yugioh_prints yp
               WHERE yp.card_id = CAST(c.catalogId AS INTEGER)
                 AND (yp.set_code = c.serialNumber OR yp.set_code_it = c.serialNumber
                   OR yp.set_code_fr = c.serialNumber OR yp.set_code_de = c.serialNumber
                   OR yp.set_code_pt = c.serialNumber OR yp.set_code_sp = c.serialNumber)
               LIMIT 1)
            WHEN 'onepiece' THEN
              (SELECT NULLIF(op.market_price, 0)
               FROM onepiece_prints op
               WHERE op.card_set_id = c.serialNumber
                  OR op.card_id = CAST(c.catalogId AS INTEGER)
               LIMIT 1)
            WHEN 'pokemon' THEN
              (SELECT CASE
                 WHEN pp.set_code_it = c.serialNumber THEN pp.set_price_it
                 WHEN pp.set_code_fr = c.serialNumber THEN pp.set_price_fr
                 WHEN pp.set_code_de = c.serialNumber THEN pp.set_price_de
                 WHEN pp.set_code_es = c.serialNumber THEN pp.set_price_es
                 WHEN pp.set_code_pt = c.serialNumber THEN pp.set_price_pt
                 ELSE pp.set_price
               END
               FROM pokemon_prints pp
               WHERE (pp.card_id = CAST(c.catalogId AS INTEGER)
                   OR pp.card_id = (SELECT id FROM pokemon_cards WHERE api_id = c.catalogId LIMIT 1))
                 AND (pp.set_code = c.serialNumber OR pp.set_code_it = c.serialNumber
                   OR pp.set_code_fr = c.serialNumber OR pp.set_code_de = c.serialNumber
                   OR pp.set_code_pt = c.serialNumber OR pp.set_code_es = c.serialNumber)
               LIMIT 1)
          END,
          NULLIF(c.value, 0),
          0
        ) AS effective_price
      FROM cards c
    )
  ''';

  Future<Map<String, dynamic>> getGlobalStats({String? collection}) async {
    Database db = await database;
    final colFilter = collection != null ? ' WHERE collection = ?' : '';
    final colArgs   = collection != null ? [collection] : <Object?>[];

    final totalCards = await db.rawQuery('SELECT SUM(quantity) as total FROM cards$colFilter', colArgs);
    final duplicateCards = await db.rawQuery(
      'SELECT SUM(c.quantity) as total FROM cards c '
      "JOIN albums a ON a.id = c.albumId WHERE a.name = 'Doppioni'"
      '${collection != null ? " AND c.collection = ?" : ""}',
      colArgs,
    );
    final totalValue  = await db.rawQuery('''
      ${_cardEffectiveValueCTE()}
      SELECT SUM(effective_price * quantity) as total FROM card_values${collection != null ? ' WHERE collection = ?' : ''}
    ''', colArgs);
    final collections = await db.rawQuery('SELECT COUNT(*) as total FROM collections WHERE isUnlocked = 1');

    return {
      'totalCards': (totalCards.first['total'] as num?)?.toInt() ?? 0,
      'duplicateCards': (duplicateCards.first['total'] as num?)?.toInt() ?? 0,
      'totalValue': (totalValue.first['total'] as num?)?.toDouble() ?? 0.0,
      'unlockedCollections': collections.first['total'] as int? ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getStatsPerCollection() async {
    final db = await database;
    return await db.rawQuery('''
      ${_cardEffectiveValueCTE()}
      SELECT collection,
             SUM(quantity) as totalCards,
             SUM(effective_price * quantity) as totalValue
      FROM card_values
      GROUP BY collection
      ORDER BY totalValue DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getStatsPerRarity({String? collection}) async {
    final db = await database;
    final colArgs = collection != null ? [collection] : <Object?>[];
    return await db.rawQuery('''
      ${_cardEffectiveValueCTE()}
      SELECT rarity,
             SUM(quantity) as count,
             SUM(effective_price * quantity) as totalValue
      FROM card_values
      WHERE rarity != ''${collection != null ? ' AND collection = ?' : ''}
      GROUP BY rarity
      ORDER BY count DESC
      LIMIT 10
    ''', colArgs);
  }

  /// Saves today's total value per collection into [collection_value_history].
  /// Uses INSERT OR IGNORE so multiple calls on the same day are no-ops.
  Future<void> saveCollectionValueSnapshot() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.rawQuery('''
      ${_cardEffectiveValueCTE()}
      SELECT collection,
             CAST(ROUND(SUM(effective_price * quantity) * 100) AS INTEGER) AS total_cents
      FROM card_values
      GROUP BY collection
    ''');
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final row in rows) {
      final cents = (row['total_cents'] as int?) ?? 0;
      if (cents <= 0) continue;
      batch.rawInsert('''
        INSERT OR IGNORE INTO collection_value_history (collection, total_cents, recorded_date)
        VALUES (?, ?, ?)
      ''', [row['collection'], cents, today]);
    }
    await batch.commit(noResult: true);
  }

  /// Returns daily total-value snapshots for [collection] (or global sum if null).
  Future<List<Map<String, dynamic>>> getCollectionValueHistory({
    String? collection,
    required String from,
  }) async {
    final db = await database;
    if (collection != null) {
      return db.rawQuery('''
        SELECT recorded_date, total_cents
        FROM collection_value_history
        WHERE collection = ? AND recorded_date >= ?
        ORDER BY recorded_date ASC
      ''', [collection, from]);
    }
    return db.rawQuery('''
      SELECT recorded_date, SUM(total_cents) AS total_cents
      FROM collection_value_history
      WHERE recorded_date >= ?
      GROUP BY recorded_date
      ORDER BY recorded_date ASC
    ''', [from]);
  }

  /// Returns ROI summary: total invested, current CT value, gain, ROI%.
  /// Only cards with purchase_price > 0 are included in invested/ROI figures.
  Future<Map<String, dynamic>> getRoiSummary() async {
    final db = await database;

    // Current portfolio value (CT price or catalog price for all cards)
    final valueRows = await db.rawQuery('''
      ${_cardEffectiveValueCTE()}
      SELECT SUM(effective_price * quantity) AS total_value FROM card_values
    ''');
    final currentValue = (valueRows.first['total_value'] as num?)?.toDouble() ?? 0.0;

    // Invested cost (only cards with purchase_price set)
    final investedRows = await db.rawQuery('''
      SELECT COALESCE(SUM(purchase_price * quantity), 0) AS total_invested
      FROM cards WHERE purchase_price > 0
    ''');
    final totalInvested = (investedRows.first['total_invested'] as num?)?.toDouble() ?? 0.0;

    // Current CT value only for cards with purchase_price set (fair comparison for ROI)
    final ownedValueRows = await db.rawQuery('''
      SELECT
        SUM(COALESCE(c.cardtrader_value, c.value, 0) * c.quantity) AS owned_value,
        COUNT(*) AS card_count
      FROM cards c WHERE c.purchase_price > 0
    ''');

    final ownedValue = (ownedValueRows.first['owned_value'] as num?)?.toDouble() ?? 0.0;
    final cardCount = (ownedValueRows.first['card_count'] as num?)?.toInt() ?? 0;

    final gain = ownedValue - totalInvested;
    final roiPct = totalInvested > 0 ? (gain / totalInvested) * 100 : 0.0;

    return {
      'currentValue': currentValue,
      'totalInvested': totalInvested,
      'ownedValue': ownedValue,
      'gain': gain,
      'roiPct': roiPct,
      'cardCount': cardCount,
    };
  }

  /// Returns top cards by ROI% (only where purchase_price > 0).
  Future<List<Map<String, dynamic>>> getRoiCardList({
    String? collection,
    int limit = 50,
  }) async {
    final db = await database;
    final collectionFilter = collection != null ? "AND c.collection = '$collection'" : '';
    return db.rawQuery('''
      SELECT
        c.id, c.name, c.serialNumber, c.rarity, c.collection, c.imageUrl,
        c.quantity, c.purchase_price,
        COALESCE(c.cardtrader_value, c.value, 0) AS current_price,
        (COALESCE(c.cardtrader_value, c.value, 0) - c.purchase_price) * c.quantity AS gain_euros,
        CASE WHEN c.purchase_price > 0
          THEN ((COALESCE(c.cardtrader_value, c.value, 0) - c.purchase_price) / c.purchase_price) * 100
          ELSE 0
        END AS roi_pct
      FROM cards c
      WHERE c.purchase_price > 0 $collectionFilter
      ORDER BY gain_euros DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<int> updateCardPurchasePrice(int cardId, double? price) async {
    final db = await database;
    return db.update(
      'cards',
      {'purchase_price': price},
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllCardsForExport() async {
    final db = await database;
    return await db.rawQuery(
      'SELECT name, serialNumber, collection, rarity, quantity, value FROM cards ORDER BY collection, name',
    );
  }

  // ============================================================
  // Yu-Gi-Oh Catalog Methods
  // ============================================================

  String _langSuffix(String language) {
    final lang = language.toUpperCase();
    if (!_validLanguages.contains(lang) || lang == 'EN') return '';
    return '_${lang.toLowerCase()}';
  }

  /// Aggiorna il campo value di tutte le carte in collezione con i prezzi
  /// aggiornati dal catalogo appena scaricato, per garantire coerenza tra
  /// dispositivi diversi (il valore live dalla query può differire per via
  /// del LIMIT 1 non deterministico).
  Future<void> refreshCardValuesFromCatalog(String collection) async {
    final db = await database;
    if (collection == 'yugioh') {
      await db.execute('''
        UPDATE cards
        SET value = COALESCE(
          (SELECT p.set_price
           FROM yugioh_prints p
           WHERE p.card_id = CAST(cards.catalogId AS INTEGER)
             AND (p.set_code = cards.serialNumber
               OR p.set_code_it = cards.serialNumber
               OR p.set_code_fr = cards.serialNumber
               OR p.set_code_de = cards.serialNumber
               OR p.set_code_pt = cards.serialNumber
               OR p.set_code_sp = cards.serialNumber)
           ORDER BY p.set_price DESC
           LIMIT 1),
          value
        )
        WHERE collection = 'yugioh' AND catalogId IS NOT NULL
      ''');
    } else if (collection == 'onepiece') {
      await db.execute('''
        UPDATE cards
        SET value = COALESCE(
          (SELECT p.market_price
           FROM onepiece_prints p
           WHERE p.card_id = CAST(cards.catalogId AS INTEGER)
             AND p.card_set_id = cards.serialNumber
           ORDER BY p.market_price DESC
           LIMIT 1),
          value
        )
        WHERE collection = 'onepiece' AND catalogId IS NOT NULL
      ''');
    } else if (collection == 'pokemon') {
      // set_price è null per le carte TCGDex (nessuna fonte prezzi disponibile);
      // l'aggiornamento preserva il valore inserito manualmente dall'utente.
      await db.execute('''
        UPDATE cards
        SET value = COALESCE(
          (SELECT p.set_price
           FROM pokemon_prints p
           WHERE p.card_id = CAST(cards.catalogId AS INTEGER)
             AND (p.set_code = cards.serialNumber
               OR p.set_code_it = cards.serialNumber
               OR p.set_code_fr = cards.serialNumber
               OR p.set_code_de = cards.serialNumber
               OR p.set_code_pt = cards.serialNumber)
           ORDER BY p.set_price DESC
           LIMIT 1),
          value
        )
        WHERE collection = 'pokemon' AND catalogId IS NOT NULL
      ''');
    }
  }

  /// Cancella tutto il catalogo Yu-Gi-Oh (carte, print, prezzi)
  /// Rimuove dal catalogo [catalog] le carte che un ridownload completo non ha
  /// toccato, cioè quelle sparite dal remoto.
  ///
  /// Sostituisce il `clear` che i `redownload*` facevano **prima** di scaricare.
  /// Quella sequenza aveva una finestra di perdita dati larga quanto l'intero
  /// download: catalogo e riga di `catalog_metadata` venivano cancellati
  /// subito, e se il download si interrompeva a metà — app uccisa, rete persa —
  /// l'utente restava senza catalogo e all'avvio dopo si ritrovava un "primo
  /// download" da rifare da capo. Scaricando prima (le insert sono tutte
  /// INSERT OR REPLACE, quindi il catalogo resta consultabile per tutto il
  /// tempo) e potando dopo, un'interruzione non toglie niente a nessuno.
  ///
  /// [since] è il timestamp ISO8601 preso *prima* di far partire il download:
  /// `updated_at` viene riscritto a ogni insert, quindi tutto ciò che è rimasto
  /// indietro non è stato ripubblicato dal remoto.
  ///
  /// Non fa nulla se nessuna carta risulta aggiornata da [since] in poi: un
  /// download andato a vuoto (remoto irraggiungibile, chunk vuoti) non deve
  /// poter svuotare un catalogo che funziona.
  Future<int> pruneCatalogCardsNotUpdatedSince(
    String catalog,
    String since,
  ) async {
    final genericPrefix = genericTablePrefix(catalog);
    final cardsTable = switch (catalog) {
      'yugioh' => 'yugioh_cards',
      'pokemon' => 'pokemon_cards',
      'onepiece' => 'onepiece_cards',
      'magic' => 'magic_cards',
      _ => genericPrefix == null ? null : '${genericPrefix}_cards',
    };
    if (cardsTable == null) return 0;

    final db = await database;

    final freshRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $cardsTable WHERE updated_at >= ?',
      [since],
    );
    final fresh = (freshRows.first['c'] as int?) ?? 0;
    if (fresh == 0) return 0;

    const staleWhere = 'updated_at IS NULL OR updated_at < ?';
    var deleted = 0;

    await db.transaction((txn) async {
      final stale = 'SELECT id FROM $cardsTable WHERE $staleWhere';

      switch (catalog) {
        case 'yugioh':
          // yugioh_prices punta alle stampe, non alle carte: va sfoltito per
          // primo o resterebbero righe orfane (i vincoli FK non sono attivi).
          await txn.rawDelete(
            'DELETE FROM yugioh_prices WHERE print_id IN '
            '(SELECT id FROM yugioh_prints WHERE card_id IN ($stale))',
            [since],
          );
          await txn.rawDelete(
            'DELETE FROM yugioh_prints WHERE card_id IN ($stale)',
            [since],
          );
        case 'pokemon':
          await txn.rawDelete(
            'DELETE FROM pokemon_prices WHERE print_id IN '
            '(SELECT id FROM pokemon_prints WHERE card_id IN ($stale))',
            [since],
          );
          await txn.rawDelete(
            'DELETE FROM pokemon_prints WHERE card_id IN ($stale)',
            [since],
          );
        case 'onepiece':
          await txn.rawDelete(
            'DELETE FROM onepiece_prints WHERE card_id IN ($stale)',
            [since],
          );
        default:
          // Cataloghi generici v36: la FK verso {prefix}_cards dichiara
          // ON DELETE CASCADE, ma senza `PRAGMA foreign_keys=ON` non scatta —
          // le stampe vanno tolte a mano. (`clearGenericCatalog` non lo fa e
          // lascia stampe orfane: qui invece si pulisce.)
          if (genericPrefix != null) {
            await txn.rawDelete(
              'DELETE FROM ${genericPrefix}_prints WHERE card_id IN ($stale)',
              [since],
            );
          }
      }

      deleted = await txn.rawDelete(
        'DELETE FROM $cardsTable WHERE $staleWhere',
        [since],
      );
    });

    return deleted;
  }

  /// Svuota completamente il catalogo Yu-Gi-Oh locale.
  ///
  /// NON usarlo prima di un ridownload: cancella anche la riga di
  /// `catalog_metadata`, quindi un download interrotto lascia l'utente senza
  /// catalogo e con un "primo download" da rifare. Per rimpiazzare il catalogo
  /// usa il ridownload, che scarica e poi chiama
  /// [pruneCatalogCardsNotUpdatedSince]. Questo resta per la pulizia esplicita
  /// (spazio occupato, catalogo corrotto), dove svuotare è proprio l'intento.
  Future<void> clearYugiohCatalog() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('yugioh_prices');
      await txn.delete('yugioh_prints');
      await txn.delete('yugioh_cards');
      await txn.delete('catalog_metadata', where: 'catalog_name = ?', whereArgs: ['yugioh']);
    });
  }

  /// Delete specific Yu-Gi-Oh cards by their IDs (incremental catalog update).
  /// Also removes associated prints and prices since FK cascades are not enabled.
  Future<void> deleteYugiohCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM yugioh_prices WHERE print_id IN (SELECT id FROM yugioh_prints WHERE card_id IN ($placeholders))',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM yugioh_prints WHERE card_id IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM yugioh_cards WHERE id IN ($placeholders)',
        ids,
      );
    });
  }

  Future<void> saveCatalogMetadata({
    required String catalogName,
    required int version,
    required int totalCards,
    required int totalChunks,
    required String lastUpdated,
  }) async {
    Database db = await database;
    await db.insert(
      'catalog_metadata',
      {
        'catalog_name': catalogName,
        'version': version,
        'total_cards': totalCards,
        'total_chunks': totalChunks,
        'last_updated': lastUpdated,
        'downloaded_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCatalogMetadata(String catalogName) async {
    Database db = await database;
    final results = await db.query(
      'catalog_metadata',
      where: 'catalog_name = ?',
      whereArgs: [catalogName],
    );
    return results.isEmpty ? null : results.first;
  }

  Future<void> insertYugiohCards(List<Map<String, dynamic>> cards, {Function(double)? onProgress}) async {
    Database db = await database;
    final now = DateTime.now().toIso8601String();

    int total = cards.length;
    const int batchSize = 200;

    for (int i = 0; i < total; i += batchSize) {
      int end = (i + batchSize < total) ? i + batchSize : total;
      List<Map<String, dynamic>> chunk = cards.sublist(i, end);

      await db.transaction((txn) async {

        Batch batch = txn.batch();
        for (var card in chunk) {
          final cardData = Map<String, dynamic>.from(card);
          final prints = cardData.remove('prints') as List<dynamic>?;

          batch.insert('yugioh_cards', {
            'id': cardData['id'],
            'type': cardData['type'],
            'human_readable_type': cardData['human_readable_type'],
            'frame_type': cardData['frame_type'],
            'race': cardData['race'],
            'archetype': cardData['archetype'],
            'ygoprodeck_url': cardData['ygoprodeck_url'],
            'atk': cardData['atk'],
            'def': cardData['def'],
            'level': cardData['level'],
            'attribute': cardData['attribute'],
            'scale': cardData['scale'],
            'linkval': cardData['linkval'],
            'linkmarkers': cardData['linkmarkers'],
            'name': cardData['name'],
            'description': cardData['description'],
            'image_url': cardData['imageUrl'] ?? cardData['image_url'],
            'name_it': cardData['name_it'],
            'description_it': cardData['description_it'],
            'name_fr': cardData['name_fr'],
            'description_fr': cardData['description_fr'],
            'name_de': cardData['name_de'],
            'description_de': cardData['description_de'],
            'name_pt': cardData['name_pt'],
            'description_pt': cardData['description_pt'],
            'name_sp': cardData['name_sp'],
            'description_sp': cardData['description_sp'],
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          if (prints != null) {
            // Cancella i print esistenti per questa carta prima di reinserirli.
            // Garantisce che i set rimossi da una carta vengano eliminati anche
            // in locale durante gli aggiornamenti incrementali.
            batch.rawDelete(
              'DELETE FROM yugioh_prices WHERE print_id IN (SELECT id FROM yugioh_prints WHERE card_id = ?)',
              [cardData['id']],
            );
            batch.rawDelete(
              'DELETE FROM yugioh_prints WHERE card_id = ?',
              [cardData['id']],
            );
            for (var p in prints) {
              final cardId = cardData['id'];
              final setCode = p['set_code'] ?? '';
              final rarity = p['rarity'];
              // Identificatore del set: prefisso prima del primo trattino (es. "LOB" da "LOB-EN001")
              final setId = setCode.contains('-')
                  ? setCode.substring(0, setCode.indexOf('-'))
                  : setCode;

              // Insert print
              batch.rawInsert('''
                INSERT OR REPLACE INTO yugioh_prints (
                  card_id, set_code, set_name, rarity, rarity_code, set_price, artwork,
                  set_name_it, set_code_it, rarity_it, rarity_code_it, set_price_it,
                  set_name_fr, set_code_fr, rarity_fr, rarity_code_fr, set_price_fr,
                  set_name_de, set_code_de, rarity_de, rarity_code_de, set_price_de,
                  set_name_pt, set_code_pt, rarity_pt, rarity_code_pt, set_price_pt,
                  set_name_sp, set_code_sp, rarity_sp, rarity_code_sp, set_price_sp,
                  set_id, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ''', [
                cardId, setCode, p['set_name'],
                rarity, p['rarity_code'],
                p['set_price'] is num ? p['set_price'] : double.tryParse(p['set_price']?.toString() ?? ''),
                p['artwork'],
                p['set_name_it'], p['set_code_it'], p['rarity_it'], p['rarity_code_it'],
                p['set_price_it'] is num ? p['set_price_it'] : double.tryParse(p['set_price_it']?.toString() ?? ''),
                p['set_name_fr'], p['set_code_fr'], p['rarity_fr'], p['rarity_code_fr'],
                p['set_price_fr'] is num ? p['set_price_fr'] : double.tryParse(p['set_price_fr']?.toString() ?? ''),
                p['set_name_de'], p['set_code_de'], p['rarity_de'], p['rarity_code_de'],
                p['set_price_de'] is num ? p['set_price_de'] : double.tryParse(p['set_price_de']?.toString() ?? ''),
                p['set_name_pt'], p['set_code_pt'], p['rarity_pt'], p['rarity_code_pt'],
                p['set_price_pt'] is num ? p['set_price_pt'] : double.tryParse(p['set_price_pt']?.toString() ?? ''),
                p['set_name_sp'], p['set_code_sp'], p['rarity_sp'], p['rarity_code_sp'],
                p['set_price_sp'] is num ? p['set_price_sp'] : double.tryParse(p['set_price_sp']?.toString() ?? ''),
                setId.isNotEmpty ? setId : null,
                now, now,
              ]);

              // Insert prices inline using subquery for print_id (no second pass needed)
              final pricesMap = p['prices'] as Map<String, dynamic>? ?? {};
              for (var lang in _validLanguages) {
                final langPrices = pricesMap[lang] as Map<String, dynamic>?;
                if (langPrices == null || langPrices.isEmpty) continue;

                batch.rawInsert('''
                  INSERT OR REPLACE INTO yugioh_prices (
                    print_id, language,
                    cardmarket_price, tcgplayer_price, ebay_price, amazon_price, coolstuffinc_price,
                    created_at, updated_at
                  ) VALUES (
                    (SELECT id FROM yugioh_prints WHERE card_id = ? AND set_code = ? AND rarity IS ?),
                    ?, ?, ?, ?, ?, ?, ?, ?
                  )
                ''', [
                  cardId, setCode, rarity,
                  lang,
                  langPrices['cardmarketPrice'] is num ? langPrices['cardmarketPrice'] : double.tryParse(langPrices['cardmarketPrice']?.toString() ?? ''),
                  langPrices['tcgplayerPrice'] is num ? langPrices['tcgplayerPrice'] : double.tryParse(langPrices['tcgplayerPrice']?.toString() ?? ''),
                  langPrices['ebayPrice'] is num ? langPrices['ebayPrice'] : double.tryParse(langPrices['ebayPrice']?.toString() ?? ''),
                  langPrices['amazonPrice'] is num ? langPrices['amazonPrice'] : double.tryParse(langPrices['amazonPrice']?.toString() ?? ''),
                  langPrices['coolstuffincPrice'] is num ? langPrices['coolstuffincPrice'] : double.tryParse(langPrices['coolstuffincPrice']?.toString() ?? ''),
                  now, now,
                ]);
              }
            }
          }
        }
        await batch.commit(noResult: true);
      });

      await Future.delayed(const Duration(milliseconds: 20)); // yield between batches
      onProgress?.call(end / total);
    }
  }

  Future<List<Map<String, dynamic>>> getYugiohCatalogCards({
    String? query,
    required String language,
    int limit = 60,
    int offset = 0,
  }) async {
    Database db = await database;
    final suffix = _langSuffix(language);
    final hasLang = suffix.isNotEmpty; // true for non-EN languages

    // Build localized column expressions
    final nameCol = hasLang ? 'COALESCE(yc.name$suffix, yc.name)' : 'yc.name';
    final descCol = hasLang ? 'COALESCE(yc.description$suffix, yc.description)' : 'yc.description';
    final setNameCol = hasLang ? 'COALESCE(yp.set_name$suffix, yp.set_name)' : 'yp.set_name';
    final setCodeCol = hasLang ? 'COALESCE(yp.set_code$suffix, yp.set_code)' : 'yp.set_code';
    final rarityCol = hasLang ? 'COALESCE(yp.rarity$suffix, yp.rarity)' : 'yp.rarity';
    final rarityCodeCol = hasLang ? 'COALESCE(yp.rarity_code$suffix, yp.rarity_code)' : 'yp.rarity_code';
    final setPriceCol = hasLang ? 'COALESCE(yp.set_price$suffix, yp.set_price)' : 'yp.set_price';

    final hasQuery = query != null && query.isNotEmpty;

    // Build WHERE clause based on language and search type
    String whereClause;
    List<dynamic> whereArgs = [];

    if (!hasQuery) {
      // No search: when a non-EN language is selected, show only prints that have
      // a localized version — hides EN-only prints that would appear with EN codes.
      whereClause = hasLang ? 'WHERE yp.set_code$suffix IS NOT NULL' : '';
    } else {
      final q = '%$query%';
      // Search by name (localized or EN) + all set codes (all languages).
      // EN-only prints are intentionally included in search results so the user
      // can still find cards that have no localized print.
      if (hasLang) {
        whereClause = '''WHERE (
          $nameCol LIKE ?
          OR yc.name LIKE ?
          OR yp.set_code LIKE ?
          OR yp.set_code_it LIKE ?
          OR yp.set_code_fr LIKE ?
          OR yp.set_code_de LIKE ?
          OR yp.set_code_pt LIKE ?
          OR yp.set_code_sp LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q, q, q];
      } else {
        // EN: search name + all set codes
        whereClause = '''WHERE (
          yc.name LIKE ?
          OR yp.set_code LIKE ?
          OR yp.set_code_it LIKE ?
          OR yp.set_code_fr LIKE ?
          OR yp.set_code_de LIKE ?
          OR yp.set_code_pt LIKE ?
          OR yp.set_code_sp LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q, q];
      }
    }

    // Flag to indicate if this print is in the user's selected language
    final isLocalizedPrint = hasLang ? 'CASE WHEN yp.set_name$suffix IS NOT NULL THEN 1 ELSE 0 END' : '1';

    final sql = '''
      SELECT
        yc.id,
        yc.name,
        $nameCol AS localizedName,
        yc.description,
        $descCol AS localizedDescription,
        yc.type, yc.human_readable_type AS humanReadableCardType, yc.frame_type AS frameType,
        yc.race, yc.archetype, yc.attribute,
        yc.atk, yc.def, yc.level, yc.scale, yc.linkval, yc.linkmarkers,
        yc.ygoprodeck_url,
        COALESCE(yp.artwork, yc.image_url) AS imageUrl,
        yp.id AS printId,
        yp.set_code AS setCode,
        $setCodeCol AS localizedSetCode,
        yp.set_name AS setName,
        $setNameCol AS localizedSetName,
        yp.rarity AS setRarity,
        $rarityCol AS localizedRarity,
        yp.rarity_code AS rarityCode,
        $rarityCodeCol AS localizedRarityCode,
        yp.set_price AS setPrice,
        $setPriceCol AS localizedSetPrice,
        yp.artwork,
        'yugioh' AS collection,
        $isLocalizedPrint AS isLocalizedPrint,
        EXISTS(SELECT 1 FROM cards WHERE catalogId = CAST(yc.id AS TEXT) AND collection = 'yugioh') AS isOwned
      FROM yugioh_cards yc
      INNER JOIN yugioh_prints yp ON yc.id = yp.card_id
      $whereClause
      GROUP BY yc.id, $setCodeCol, $rarityCodeCol, COALESCE(yp.artwork, 0)
      ORDER BY yc.name, $setCodeCol
      LIMIT ? OFFSET ?
    ''';

    return await db.rawQuery(sql, [...whereArgs, limit, offset]);
  }

  Future<List<Map<String, dynamic>>> getYugiohCardPrints(int cardId, {required String language}) async {
    Database db = await database;
    final suffix = _langSuffix(language);
    final hasLang = suffix.isNotEmpty;

    final setNameCol = hasLang ? 'COALESCE(set_name$suffix, set_name)' : 'set_name';
    final setCodeCol = hasLang ? 'COALESCE(set_code$suffix, set_code)' : 'set_code';
    final rarityCol = hasLang ? 'COALESCE(rarity$suffix, rarity)' : 'rarity';
    final rarityCodeCol = hasLang ? 'COALESCE(rarity_code$suffix, rarity_code)' : 'rarity_code';
    final setPriceCol = hasLang ? 'COALESCE(set_price$suffix, set_price)' : 'set_price';

    return await db.rawQuery('''
      SELECT
        id, card_id AS cardId, set_code AS setCode, set_name AS setName,
        rarity, rarity_code AS rarityCode, set_price AS setPrice, artwork,
        $setNameCol AS localizedSetName,
        $setCodeCol AS localizedSetCode,
        $rarityCol AS localizedRarity,
        $rarityCodeCol AS localizedRarityCode,
        $setPriceCol AS localizedSetPrice
      FROM yugioh_prints
      WHERE card_id = ?
      ORDER BY set_code
    ''', [cardId]);
  }

  Future<int> getYugiohCatalogCount() async {
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM yugioh_cards');
    return result.first['count'] as int? ?? 0;
  }

  /// Restituisce le lingue che hanno dati effettivi nel catalogo locale.
  /// Controlla le colonne localizzate nella tabella prints della collezione.
  Future<Set<String>> getAvailableCatalogLanguages(String collectionKey) async {
    final result = <String>{'EN'};
    if (collectionKey == 'yugioh') {
      final db = await database;
      const langs = ['it', 'fr', 'de', 'pt', 'sp'];
      for (final lang in langs) {
        // Prima il nome carta tradotto, poi il codice set localizzato.
        //
        // Guardare solo `set_code_$lang` faceva sparire quasi tutte le lingue:
        // l'array `card_sets` di YGOProDeck contiene codici praticamente solo
        // inglesi anche quando lo si interroga con `language=it|fr|de|pt`
        // (misurato: ~198 EN e 0 IT su 214 set nella risposta italiana), e il
        // rebuild del worker separa le lingue proprio dal prefisso di quel
        // codice. Risultato: restavano EN e PT — quest'ultima solo grazie a una
        // manciata di codici `-PT` sparsi nei dati.
        //
        // Le traduzioni però ci sono davvero, su un'altra dimensione: le
        // chiamate per lingua restituiscono nome e descrizione tradotti, che il
        // worker scrive in `name_$lang`. È lo stesso criterio già usato da
        // Pokémon, Magic e dai cataloghi generici — Yu-Gi-Oh era l'unico a
        // chiedere la cosa sbagliata.
        final cardRows = await db.rawQuery(
          "SELECT 1 FROM yugioh_cards WHERE name_$lang IS NOT NULL AND name_$lang != '' LIMIT 1",
        );
        if (cardRows.isNotEmpty) {
          result.add(lang.toUpperCase());
          continue;
        }
        final printRows = await db.rawQuery(
          "SELECT 1 FROM yugioh_prints WHERE set_code_$lang IS NOT NULL AND set_code_$lang != '' LIMIT 1",
        );
        if (printRows.isNotEmpty) result.add(lang.toUpperCase());
      }
    } else if (collectionKey == 'pokemon') {
      final db = await database;
      const langs = ['it', 'fr', 'de', 'es', 'pt'];
      for (final lang in langs) {
        // Check either the card name OR the set_name for this language.
        // set_code_* is always equal to EN (same api_id), so it's always non-null.
        // A language is "available" if at least one card OR one print has localized data.
        final cardRows = await db.rawQuery(
          "SELECT 1 FROM pokemon_cards WHERE name_$lang IS NOT NULL AND name_$lang != '' LIMIT 1",
        );
        if (cardRows.isNotEmpty) {
          result.add(lang.toUpperCase());
          continue;
        }
        final printRows = await db.rawQuery(
          "SELECT 1 FROM pokemon_prints WHERE set_name_$lang IS NOT NULL AND set_name_$lang != '' LIMIT 1",
        );
        if (printRows.isNotEmpty) result.add(lang.toUpperCase());
      }
    } else if (collectionKey == 'onepiece') {
      final db = await database;
      // JP: prints dove il collector-number inizia con cifra (es. OP01-001)
      // EN/FR/etc: prints dove il collector-number inizia con il codice a 2 lettere
      // La lingua si ricava dal card_set_id, NON dalle colonne set_name_jp ecc.
      // che invece contengono traduzioni supplementari del nome del set.
      final jpRows = await db.rawQuery('''
        SELECT 1 FROM onepiece_prints
        WHERE card_set_id LIKE '%-%'
          AND SUBSTR(card_set_id, INSTR(card_set_id, '-') + 1, 1) BETWEEN '0' AND '9'
        LIMIT 1
      ''');
      if (jpRows.isNotEmpty) result.add('JP');

      for (final lang in ['EN', 'FR', 'KO', 'ZH']) {
        final rows = await db.rawQuery('''
          SELECT 1 FROM onepiece_prints
          WHERE INSTR(card_set_id, '-') > 0
            AND UPPER(SUBSTR(card_set_id, INSTR(card_set_id, '-') + 1, 2)) = ?
          LIMIT 1
        ''', [lang]);
        if (rows.isNotEmpty) result.add(lang);
      }
    } else if (collectionKey == 'magic') {
      final db = await database;
      const langs = ['it', 'fr', 'de', 'pt', 'sp', 'jp', 'ko', 'zh'];
      for (final lang in langs) {
        final rows = await db.rawQuery(
          "SELECT 1 FROM magic_cards WHERE name_$lang IS NOT NULL AND name_$lang != '' LIMIT 1",
        );
        if (rows.isNotEmpty) result.add(lang.toUpperCase());
      }
    } else {
      final prefix = genericTablePrefix(collectionKey);
      if (prefix != null) {
        final db = await database;
        for (final entry in const {'IT': 'name_it', 'FR': 'name_fr', 'DE': 'name_de', 'PT': 'name_pt'}.entries) {
          final rows = await db.rawQuery(
            "SELECT 1 FROM ${prefix}_cards WHERE ${entry.value} IS NOT NULL AND ${entry.value} != '' LIMIT 1",
          );
          if (rows.isNotEmpty) result.add(entry.key);
        }
      }
    }
    return result;
  }

  // ============================================================
  // Pokémon Catalog Methods
  // ============================================================

  Future<void> clearPokemonCatalog() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('pokemon_prices');
      await txn.delete('pokemon_prints');
      await txn.delete('pokemon_cards');
      await txn.delete('catalog_metadata', where: 'catalog_name = ?', whereArgs: ['pokemon']);
    });
  }

  Future<void> deletePokemonCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM pokemon_prices WHERE print_id IN (SELECT id FROM pokemon_prints WHERE card_id IN ($placeholders))',
        ids,
      );
      await txn.rawDelete('DELETE FROM pokemon_prints WHERE card_id IN ($placeholders)', ids);
      await txn.rawDelete('DELETE FROM pokemon_cards WHERE id IN ($placeholders)', ids);
    });
  }

  Future<void> insertPokemonCards(List<Map<String, dynamic>> cards, {Function(double)? onProgress}) async {
    Database db = await database;
    final now = DateTime.now().toIso8601String();

    int total = cards.length;
    const int batchSize = 200;

    for (int i = 0; i < total; i += batchSize) {
      int end = (i + batchSize < total) ? i + batchSize : total;
      List<Map<String, dynamic>> chunk = cards.sublist(i, end);

      await db.transaction((txn) async {
        Batch batch = txn.batch();
        for (var card in chunk) {
          final cardData = Map<String, dynamic>.from(card);
          final prints = cardData.remove('prints') as List<dynamic>?;

          batch.rawInsert('''
            INSERT OR REPLACE INTO pokemon_cards (
              api_id, name, supertype, subtype, hp, types, rarity,
              set_id, set_name, set_series, number, image_url,
              name_it, name_fr, name_de, name_es, name_pt,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
            cardData['api_id'],
            cardData['name'],
            cardData['supertype'],
            cardData['subtype'],
            cardData['hp'],
            cardData['types'],
            cardData['rarity'],
            cardData['set_id'],
            cardData['set_name'],
            cardData['set_series'],
            cardData['number'],
            // Dopo l'upload su Storage il campo diventa camelCase 'imageUrl';
            // prima dell'upload (o se fallisce) rimane 'image_url'
            cardData['imageUrl'] ?? cardData['image_url'],
            cardData['name_it'],
            cardData['name_fr'],
            cardData['name_de'],
            cardData['name_es'],
            cardData['name_pt'],
            now, now,
          ]);

          if (prints != null) {
            for (var p in prints) {
              final setCode = p['set_code'] ?? '';
              batch.rawInsert('''
                INSERT OR REPLACE INTO pokemon_prints (
                  card_id, set_code, set_name, rarity, set_price, artwork,
                  set_code_it, set_name_it, rarity_it, set_price_it,
                  set_code_fr, set_name_fr, rarity_fr, set_price_fr,
                  set_code_de, set_name_de, rarity_de, set_price_de,
                  set_code_es, set_name_es, rarity_es, set_price_es,
                  set_code_pt, set_name_pt, rarity_pt, set_price_pt,
                  created_at, updated_at
                ) VALUES (
                  (SELECT id FROM pokemon_cards WHERE api_id = ?),
                  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
              ''', [
                cardData['api_id'],
                setCode, p['set_name'],
                p['rarity'],
                p['set_price'] is num ? p['set_price'] : double.tryParse(p['set_price']?.toString() ?? ''),
                p['artwork'],
                p['set_code_it'], p['set_name_it'], p['rarity_it'],
                p['set_price_it'] is num ? p['set_price_it'] : double.tryParse(p['set_price_it']?.toString() ?? ''),
                p['set_code_fr'], p['set_name_fr'], p['rarity_fr'],
                p['set_price_fr'] is num ? p['set_price_fr'] : double.tryParse(p['set_price_fr']?.toString() ?? ''),
                p['set_code_de'], p['set_name_de'], p['rarity_de'],
                p['set_price_de'] is num ? p['set_price_de'] : double.tryParse(p['set_price_de']?.toString() ?? ''),
                p['set_code_es'], p['set_name_es'], p['rarity_es'],
                p['set_price_es'] is num ? p['set_price_es'] : double.tryParse(p['set_price_es']?.toString() ?? ''),
                p['set_code_pt'], p['set_name_pt'], p['rarity_pt'],
                p['set_price_pt'] is num ? p['set_price_pt'] : double.tryParse(p['set_price_pt']?.toString() ?? ''),
                now, now,
              ]);

              // Prices per language
              final pricesMap = p['prices'] as Map<String, dynamic>? ?? {};
              for (var lang in _validLanguages) {
                final langPrices = pricesMap[lang] as Map<String, dynamic>?;
                if (langPrices == null || langPrices.isEmpty) continue;
                batch.rawInsert('''
                  INSERT OR REPLACE INTO pokemon_prices (
                    print_id, language, cardmarket_price, tcgplayer_price,
                    created_at, updated_at
                  ) VALUES (
                    (SELECT pp.id FROM pokemon_prints pp
                     JOIN pokemon_cards pc ON pc.id = pp.card_id
                     WHERE pc.api_id = ? AND pp.set_code = ?),
                    ?, ?, ?, ?, ?
                  )
                ''', [
                  cardData['api_id'], setCode,
                  lang,
                  langPrices['cardmarketPrice'] is num ? langPrices['cardmarketPrice'] : double.tryParse(langPrices['cardmarketPrice']?.toString() ?? ''),
                  langPrices['tcgplayerPrice'] is num ? langPrices['tcgplayerPrice'] : double.tryParse(langPrices['tcgplayerPrice']?.toString() ?? ''),
                  now, now,
                ]);
              }
            }
          }
        }
        await batch.commit(noResult: true);
      });

      await Future.delayed(const Duration(milliseconds: 20)); // yield between batches
      onProgress?.call(end / total);
    }
  }

  Future<List<Map<String, dynamic>>> getPokemonCatalogCards({
    String? query,
    required String language,
    int limit = 60,
    int offset = 0,
  }) async {
    Database db = await database;
    final suffix = _langSuffix(language);
    final hasLang = suffix.isNotEmpty;

    final nameCol = hasLang ? 'COALESCE(pc.name$suffix, pc.name)' : 'pc.name';
    final setNameCol = hasLang ? 'COALESCE(pp.set_name$suffix, pp.set_name)' : 'pp.set_name';
    final setCodeCol = hasLang ? 'COALESCE(pp.set_code$suffix, pp.set_code)' : 'pp.set_code';
    final rarityCol = hasLang ? 'COALESCE(pp.rarity$suffix, pp.rarity)' : 'pp.rarity';
    final setPriceCol = hasLang ? 'COALESCE(pp.set_price$suffix, pp.set_price)' : 'pp.set_price';

    final hasQuery = query != null && query.isNotEmpty;
    String whereClause;
    List<dynamic> whereArgs = [];

    if (!hasQuery) {
      // No search: when a non-EN language is selected, show only localized prints.
      whereClause = hasLang ? 'WHERE pp.set_code$suffix IS NOT NULL' : '';
    } else {
      final q = '%$query%';
      if (hasLang) {
        whereClause = '''WHERE (
          $nameCol LIKE ?
          OR pc.name LIKE ?
          OR pc.name_it LIKE ? OR pc.name_fr LIKE ? OR pc.name_de LIKE ?
          OR pc.name_es LIKE ? OR pc.name_pt LIKE ?
          OR pp.set_code LIKE ?
          OR pp.set_name LIKE ? OR pp.set_name_it LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q, q, q, q, q];
      } else {
        whereClause = '''WHERE (
          pc.name LIKE ?
          OR pc.name_it LIKE ? OR pc.name_fr LIKE ? OR pc.name_de LIKE ?
          OR pc.name_es LIKE ? OR pc.name_pt LIKE ?
          OR pp.set_code LIKE ?
          OR pp.set_name LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q, q, q];
      }
    }

    final isLocalizedPrint = hasLang ? 'CASE WHEN pp.set_name$suffix IS NOT NULL THEN 1 ELSE 0 END' : '1';
    // CT price language: use selected language if valid, else fall back to EN
    final ctLang = hasLang ? language.toLowerCase() : 'en';

    final sql = '''
      SELECT
        pc.id,
        pc.api_id AS apiId,
        pc.name,
        $nameCol AS localizedName,
        pc.supertype AS type,
        pc.subtype,
        pc.hp,
        pc.types,
        pc.rarity,
        pc.set_id AS setId,
        pc.set_name AS cardSetName,
        pc.number,
        COALESCE(pp.artwork, pc.image_url) AS imageUrl,
        pp.id AS printId,
        pp.set_code AS setCode,
        $setCodeCol AS localizedSetCode,
        pp.set_name AS setName,
        $setNameCol AS localizedSetName,
        pp.rarity AS setRarity,
        $rarityCol AS localizedRarity,
        -- Prefer CT marketplace price (EUR) over TCGdex Cardmarket price when available
        COALESCE(ctp.ct_price_cents / 100.0, pp.set_price) AS setPrice,
        COALESCE(ctp.ct_price_cents / 100.0, $setPriceCol) AS localizedSetPrice,
        pp.artwork,
        'pokemon' AS collection,
        $isLocalizedPrint AS isLocalizedPrint,
        EXISTS(SELECT 1 FROM cards WHERE catalogId = CAST(pc.id AS TEXT) AND collection = 'pokemon') AS isOwned
      FROM pokemon_cards pc
      LEFT JOIN pokemon_prints pp ON pc.id = pp.card_id
      LEFT JOIN (
        SELECT
          expansion_code,
          CAST(collector_number AS INTEGER) AS cn_int,
          MIN(min_price_any_cents) AS ct_price_cents
        FROM cardtrader_prices
        WHERE catalog = 'pokemon' AND language = '$ctLang'
          AND min_price_any_cents IS NOT NULL
        GROUP BY expansion_code, cn_int
      ) ctp ON (
        LOWER(pc.set_id) = ctp.expansion_code
        AND CAST(pc.number AS INTEGER) = ctp.cn_int
      )
      $whereClause
      ORDER BY pc.name, $setCodeCol
      LIMIT ? OFFSET ?
    ''';

    return await db.rawQuery(sql, [...whereArgs, limit, offset]);
  }

  Future<List<Map<String, dynamic>>> getPokemonCardPrints(int cardId, {required String language}) async {
    Database db = await database;
    final suffix = _langSuffix(language);
    final hasLang = suffix.isNotEmpty;

    final setNameCol = hasLang ? 'COALESCE(set_name$suffix, set_name)' : 'set_name';
    final setCodeCol = hasLang ? 'COALESCE(set_code$suffix, set_code)' : 'set_code';
    final rarityCol = hasLang ? 'COALESCE(rarity$suffix, rarity)' : 'rarity';
    final setPriceCol = hasLang ? 'COALESCE(set_price$suffix, set_price)' : 'set_price';

    return await db.rawQuery('''
      SELECT
        id, card_id AS cardId, set_code AS setCode, set_name AS setName,
        rarity, set_price AS setPrice, artwork,
        $setNameCol AS localizedSetName,
        $setCodeCol AS localizedSetCode,
        $rarityCol AS localizedRarity,
        $setPriceCol AS localizedSetPrice
      FROM pokemon_prints
      WHERE card_id = ?
      ORDER BY set_code
    ''', [cardId]);
  }

  Future<int> getPokemonCatalogCount() async {
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM pokemon_cards');
    return result.first['count'] as int? ?? 0;
  }

  Future<int> getOnepieceCatalogCount() async {
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM onepiece_cards');
    return result.first['count'] as int? ?? 0;
  }

  // ============================================================
  // Collection Methods
  // ============================================================

  Future<List<CollectionModel>> getCollections() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('collections');
    return List.generate(maps.length, (i) => CollectionModel.fromMap(maps[i]));
  }

  Future<int> unlockCollection(String id) async {
    Database db = await database;
    return await db.update(
      'collections',
      {'isUnlocked': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // Deck Methods
  // ============================================================

  Future<int> insertDeck(String name, String collection) async {
    Database db = await database;
    return await db.insert('decks', {'name': name, 'collection': collection});
  }

  Future<Map<String, dynamic>?> getDeckByFirestoreId(String firestoreId) async {
    final db = await database;
    final r = await db.query('decks', where: 'firestoreId = ?', whereArgs: [firestoreId]);
    return r.isNotEmpty ? r.first : null;
  }

  Future<void> renameDeck(int id, String name) async {
    final db = await database;
    await db.update('decks', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDeckFields(String firestoreId, String name, String collection) async {
    final db = await database;
    await db.update(
      'decks',
      {'name': name, 'collection': collection},
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<List<Map<String, dynamic>>> getDecksByCollection(String collection) async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT d.*, COUNT(dc.cardId) AS card_count
      FROM decks d
      LEFT JOIN deck_cards dc ON dc.deckId = d.id
      WHERE d.collection = ?
      GROUP BY d.id
    ''', [collection]);
  }

  Future<int> deleteDeck(int id) async {
    Database db = await database;
    return await db.delete('decks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addCardToDeck(int deckId, int cardId, int quantity) async {
    Database db = await database;
    // INSERT or INCREMENT: if the card is already in the deck, increase its quantity
    await db.rawInsert('''
      INSERT INTO deck_cards (deckId, cardId, quantity)
      VALUES (?, ?, ?)
      ON CONFLICT(deckId, cardId) DO UPDATE SET quantity = quantity + excluded.quantity
    ''', [deckId, cardId, quantity]);
  }

  Future<List<Map<String, dynamic>>> getDeckCards(int deckId) async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT dc.quantity as deckQuantity, c.*
      FROM deck_cards dc
      JOIN cards c ON dc.cardId = c.id
      WHERE dc.deckId = ?
    ''', [deckId]);
  }

  Future<List<Map<String, dynamic>>> getDecksForCard(int cardId) async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT d.id, d.name, dc.quantity
      FROM deck_cards dc
      JOIN decks d ON dc.deckId = d.id
      WHERE dc.cardId = ?
    ''', [cardId]);
  }

  Future<void> removeCardFromDeck(int deckId, int cardId) async {
    Database db = await database;
    await db.delete('deck_cards', where: 'deckId = ? AND cardId = ?', whereArgs: [deckId, cardId]);
  }

  /// Decrementa di 1 la quantità di una carta nel deck; se arriva a 0 rimuove la riga.
  Future<void> decrementCardInDeck(int deckId, int cardId) async {
    Database db = await database;
    await db.rawUpdate(
      'UPDATE deck_cards SET quantity = quantity - 1 WHERE deckId = ? AND cardId = ?',
      [deckId, cardId],
    );
    await db.delete(
      'deck_cards',
      where: 'deckId = ? AND cardId = ? AND quantity <= 0',
      whereArgs: [deckId, cardId],
    );
  }

  // ============================================================
  // Set / Espansioni Methods
  // ============================================================

  /// Statistiche completamento per ogni set della collezione.
  /// Ritorna: [{setName, setCode (OP only), totalCards, ownedCards}]
  Future<List<Map<String, dynamic>>> getSetStats(String collection, {String lang = 'en'}) async {
    Database db = await database;
    if (collection == 'yugioh') {
      final l = lang.toLowerCase();
      final nameExpr = (l == 'en')
          ? "COALESCE(p.set_name, '?')"
          : "COALESCE(MIN(p.set_name_$l), p.set_name, '?')";
      return db.rawQuery('''
        SELECT $nameExpr as setName,
               p.set_name as setQueryId,
               MIN(COALESCE(
                 p.set_id,
                 CASE WHEN p.set_code != '' AND INSTR(p.set_code, '-') > 0
                      THEN SUBSTR(p.set_code, 1, INSTR(p.set_code, '-') - 1)
                      WHEN p.set_code != '' THEN p.set_code
                      ELSE NULL END
               )) as setCode,
               COUNT(DISTINCT p.card_id) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN p.card_id END) as ownedCards,
               MAX(c.added_at) as completedAt
        FROM yugioh_prints p
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'yugioh'
          AND (c.serialNumber = p.set_code
            OR c.serialNumber = p.set_code_it
            OR c.serialNumber = p.set_code_fr
            OR c.serialNumber = p.set_code_de
            OR c.serialNumber = p.set_code_pt
            OR c.serialNumber = p.set_code_sp)
        WHERE p.set_name IS NOT NULL
        GROUP BY p.set_name
        ORDER BY $nameExpr
      ''');
    } else if (collection == 'onepiece') {
      // card_set_id non è localizzato → match diretto
      return db.rawQuery('''
        SELECT COALESCE(p.set_name, p.set_id, '?') as setName,
               p.set_id as setCode,
               COUNT(DISTINCT p.card_id) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN p.card_id END) as ownedCards,
               MAX(c.added_at) as completedAt
        FROM onepiece_prints p
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'onepiece'
          AND c.serialNumber = p.card_set_id
        WHERE p.set_id IS NOT NULL
        GROUP BY p.set_id
        ORDER BY p.set_name
      ''');
    } else if (collection == 'pokemon') {
      final l = lang.toLowerCase();
      final nameExpr = (l == 'en')
          ? "COALESCE(pc.set_name, pc.set_id, '?')"
          : "COALESCE(MIN(pp.set_name_$l), pc.set_name, pc.set_id, '?')";
      return db.rawQuery('''
        SELECT $nameExpr as setName,
               pc.set_id as setQueryId,
               pc.set_id as setCode,
               COUNT(DISTINCT pp.card_id) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN pp.card_id END) as ownedCards,
               MAX(c.added_at) as completedAt
        FROM pokemon_prints pp
        JOIN pokemon_cards pc ON pc.id = pp.card_id
        LEFT JOIN cards c ON (CAST(c.catalogId AS INTEGER) = pp.card_id OR c.catalogId = (SELECT api_id FROM pokemon_cards WHERE id = pp.card_id LIMIT 1))
          AND c.collection = 'pokemon'
          AND (c.serialNumber = pp.set_code
            OR c.serialNumber = pp.set_code_it
            OR c.serialNumber = pp.set_code_fr
            OR c.serialNumber = pp.set_code_de
            OR c.serialNumber = pp.set_code_pt)
        WHERE pc.set_id IS NOT NULL
        GROUP BY pc.set_id
        ORDER BY $nameExpr
      ''');
    } else {
      return db.rawQuery('''
        SELECT cs.setName,
               COUNT(DISTINCT cs.cardId) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN cs.cardId END) as ownedCards,
               MAX(c.added_at) as completedAt
        FROM catalog_card_sets cs
        JOIN catalog_cards cc ON cc.id = cs.cardId AND cc.collection = ?
        LEFT JOIN cards c ON c.catalogId = cs.cardId AND c.collection = ?
        WHERE cs.setName IS NOT NULL
        GROUP BY cs.setName
        ORDER BY cs.setName
      ''', [collection, collection]);
    }
  }

  /// Legge le traduzioni esistenti di un nome set dal DB locale.
  /// Ritorna mappa lang → nome tradotto (solo lingue non vuote).
  Future<Map<String, String>> getSetTranslations(String collection, String setName) async {
    final db = await database;
    final langs = _collectionLangs(collection);
    if (langs.isEmpty) return {};
    final table = '${collection}_prints';
    final rows = await db.rawQuery(
      'SELECT ${langs.map((l) => 'MIN(set_name_$l) AS set_name_$l').join(', ')} '
      'FROM $table WHERE set_name = ? LIMIT 1',
      [setName],
    );
    if (rows.isEmpty) return {};
    final row = rows.first;
    return {
      for (final l in langs)
        if (row['set_name_$l'] != null && (row['set_name_$l'] as String).isNotEmpty)
          l: row['set_name_$l'] as String,
    };
  }

  /// Legge le traduzioni esistenti di una rarità dal DB locale.
  Future<Map<String, String>> getRarityTranslations(String collection, String rarity) async {
    final db = await database;
    final langs = _collectionLangs(collection);
    if (langs.isEmpty) return {};
    final table = '${collection}_prints';
    final rows = await db.rawQuery(
      'SELECT ${langs.map((l) => 'MIN(rarity_$l) AS rarity_$l').join(', ')} '
      'FROM $table WHERE rarity = ? LIMIT 1',
      [rarity],
    );
    if (rows.isEmpty) return {};
    final row = rows.first;
    return {
      for (final l in langs)
        if (row['rarity_$l'] != null && (row['rarity_$l'] as String).isNotEmpty)
          l: row['rarity_$l'] as String,
    };
  }

  // Legacy wrappers kept for backward compat — delegate to the new table methods.

  /// Rinomina il nome set inglese (cascade su prints + catalog_expansions).
  Future<void> renameSetName(String collection, String oldName, String newName) =>
      renameExpansion(collection, oldName, newName);

  /// Rinomina la rarità inglese (cascade su prints + catalog_rarities).
  Future<void> renameRarity(String collection, String oldName, String newName) =>
      renameRarityEntry(collection, oldName, newName);

  /// Aggiorna le traduzioni del set (cascade su prints + catalog_expansions).
  Future<void> updateSetTranslations(
          String collection, String setName, Map<String, String> translations) =>
      updateExpansionTranslations(collection, setName, translations);

  /// Aggiorna le traduzioni della rarità (cascade su prints + catalog_rarities).
  Future<void> updateRarityTranslations(
          String collection, String rarity, Map<String, String> translations) =>
      updateRarityEntryTranslations(collection, rarity, translations);

  /// Lingue disponibili per una collezione (suffissi colonne, lowercase).
  List<String> _collectionLangs(String collection) {
    switch (collection) {
      case 'yugioh':   return ['it', 'fr', 'de', 'pt', 'sp'];
      case 'pokemon':  return ['it', 'fr', 'de', 'es', 'pt'];
      case 'onepiece': return ['fr', 'ko', 'zh'];
      default:         return [];
    }
  }

  /// Restituisce tutte le espansioni per una collezione (dalla tabella dedicata).
  /// Campi restituiti compatibili con i vecchi consumatori: set_name, set_code, set_name_XX.
  Future<List<Map<String, dynamic>>> getDistinctSets(String collection) async {
    final rows = await getExpansions(collection);
    // Remap set_id → set_code per compatibilità con l'editor set/rarità
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['set_code'] = m['set_id'];
      return m;
    }).toList();
  }

  /// Restituisce tutte le rarità per una collezione (dalla tabella dedicata).
  Future<List<Map<String, dynamic>>> getDistinctRarities(String collection) =>
      getRarities(collection);

  /// Dettaglio carte in un set specifico con stato di possesso.
  /// [setIdentifier]: set_name (YGO), set_id (OP), setName (generico)
  /// Ritorna: [{id, name, imageUrl, serialNumber, rarity, isOwned}]
  Future<List<Map<String, dynamic>>> getSetDetail(String collection, String setIdentifier, {String lang = 'en'}) async {
    Database db = await database;
    if (collection == 'yugioh') {
      final l = lang.toLowerCase();
      final rarityExpr  = (l == 'en') ? 'p.rarity' : 'COALESCE(p.rarity_$l, p.rarity)';
      final serialExpr  = (l == 'en') ? 'p.set_code' : 'COALESCE(p.set_code_$l, p.set_code)';
      return db.rawQuery('''
        SELECT yc.id, yc.name, COALESCE(p.artwork, yc.image_url) as imageUrl,
               $serialExpr as serialNumber, $rarityExpr as rarity,
               CASE WHEN c.id IS NOT NULL THEN 1 ELSE 0 END as isOwned
        FROM yugioh_prints p
        JOIN yugioh_cards yc ON yc.id = p.card_id
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'yugioh'
          AND (c.serialNumber = p.set_code
            OR c.serialNumber = p.set_code_it
            OR c.serialNumber = p.set_code_fr
            OR c.serialNumber = p.set_code_de
            OR c.serialNumber = p.set_code_pt
            OR c.serialNumber = p.set_code_sp)
        WHERE p.set_name = ?
        ORDER BY p.set_code
      ''', [setIdentifier]);
    } else if (collection == 'onepiece') {
      return db.rawQuery('''
        SELECT oc.id, oc.name, COALESCE(p.artwork, oc.image_url) as imageUrl,
               p.card_set_id as serialNumber, p.rarity,
               CASE WHEN c.id IS NOT NULL THEN 1 ELSE 0 END as isOwned
        FROM onepiece_prints p
        JOIN onepiece_cards oc ON oc.id = p.card_id
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'onepiece'
          AND c.serialNumber = p.card_set_id
        WHERE p.set_id = ?
        ORDER BY p.card_set_id
      ''', [setIdentifier]);
    } else if (collection == 'pokemon') {
      final l = lang.toLowerCase();
      final rarityExpr = (l == 'en') ? 'pp.rarity' : 'COALESCE(pp.rarity_$l, pp.rarity)';
      final serialExpr = (l == 'en') ? 'pp.set_code' : 'COALESCE(pp.set_code_$l, pp.set_code)';
      return db.rawQuery('''
        SELECT pc.id, pc.name, pp.artwork as imageUrl,
               $serialExpr as serialNumber, $rarityExpr as rarity,
               CASE WHEN c.id IS NOT NULL THEN 1 ELSE 0 END as isOwned
        FROM pokemon_prints pp
        JOIN pokemon_cards pc ON pc.id = pp.card_id
        LEFT JOIN cards c ON (CAST(c.catalogId AS INTEGER) = pp.card_id OR c.catalogId = (SELECT api_id FROM pokemon_cards WHERE id = pp.card_id LIMIT 1))
          AND c.collection = 'pokemon'
          AND (c.serialNumber = pp.set_code
            OR c.serialNumber = pp.set_code_it
            OR c.serialNumber = pp.set_code_fr
            OR c.serialNumber = pp.set_code_de
            OR c.serialNumber = pp.set_code_pt)
        WHERE pc.set_id = ?
        ORDER BY pp.set_code
      ''', [setIdentifier]);
    } else {
      return db.rawQuery('''
        SELECT cc.id, cc.name, cs.imageUrlSmall as imageUrl,
               cs.setCode as serialNumber, cs.setRarity as rarity,
               CASE WHEN c.id IS NOT NULL THEN 1 ELSE 0 END as isOwned
        FROM catalog_card_sets cs
        JOIN catalog_cards cc ON cc.id = cs.cardId AND cc.collection = ?
        LEFT JOIN cards c ON c.catalogId = cs.cardId AND c.collection = ?
        WHERE cs.setName = ?
        ORDER BY cs.setCode
      ''', [collection, collection, setIdentifier]);
    }
  }

  /// Controlla se il set a cui appartiene la carta appena aggiunta è ora completo al 100%.
  /// [serialNumber]: codice carta (es. "LOB-IT001" per YGO, "OP01-001" per OP).
  /// Ritorna {setName, setCode?, totalCards, ownedCards} se completato, null altrimenti.
  Future<Map<String, dynamic>?> checkSetCompletion(String collection, String serialNumber) async {
    Database db = await database;
    List<Map<String, dynamic>> result;
    if (collection == 'yugioh') {
      result = await db.rawQuery('''
        SELECT p.set_name as setName,
               COUNT(DISTINCT p.card_id) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN p.card_id END) as ownedCards
        FROM yugioh_prints p
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'yugioh'
          AND (c.serialNumber = p.set_code
            OR c.serialNumber = p.set_code_it
            OR c.serialNumber = p.set_code_fr
            OR c.serialNumber = p.set_code_de
            OR c.serialNumber = p.set_code_pt
            OR c.serialNumber = p.set_code_sp)
        WHERE p.set_name IN (
          SELECT set_name FROM yugioh_prints
          WHERE set_code = ? OR set_code_it = ? OR set_code_fr = ? OR set_code_de = ?
            OR set_code_pt = ? OR set_code_sp = ?
        )
        GROUP BY p.set_name
        HAVING ownedCards >= totalCards AND totalCards > 0
      ''', [serialNumber, serialNumber, serialNumber, serialNumber, serialNumber, serialNumber]);
    } else if (collection == 'onepiece') {
      result = await db.rawQuery('''
        SELECT COALESCE(p.set_name, p.set_id, '?') as setName, p.set_id as setCode,
               COUNT(DISTINCT p.card_id) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN p.card_id END) as ownedCards
        FROM onepiece_prints p
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'onepiece'
          AND c.serialNumber = p.card_set_id
        WHERE p.set_id IN (
          SELECT set_id FROM onepiece_prints WHERE card_set_id = ?
        )
        GROUP BY p.set_id
        HAVING ownedCards >= totalCards AND totalCards > 0
      ''', [serialNumber]);
    } else if (collection == 'pokemon') {
      result = await db.rawQuery('''
        SELECT COALESCE(pc.set_name, pc.set_id, '?') as setName, pc.set_id as setCode,
               COUNT(DISTINCT pp.card_id) as totalCards,
               COUNT(DISTINCT CASE WHEN c.id IS NOT NULL THEN pp.card_id END) as ownedCards
        FROM pokemon_prints pp
        JOIN pokemon_cards pc ON pc.id = pp.card_id
        LEFT JOIN cards c ON (CAST(c.catalogId AS INTEGER) = pp.card_id OR c.catalogId = (SELECT api_id FROM pokemon_cards WHERE id = pp.card_id LIMIT 1))
          AND c.collection = 'pokemon'
          AND (c.serialNumber = pp.set_code
            OR c.serialNumber = pp.set_code_it
            OR c.serialNumber = pp.set_code_fr
            OR c.serialNumber = pp.set_code_de
            OR c.serialNumber = pp.set_code_pt)
        WHERE pc.set_id IN (
          SELECT pc2.set_id FROM pokemon_prints pp2
          JOIN pokemon_cards pc2 ON pc2.id = pp2.card_id
          WHERE pp2.set_code = ? OR pp2.set_code_it = ?
            OR pp2.set_code_fr = ? OR pp2.set_code_de = ? OR pp2.set_code_pt = ?
        )
        GROUP BY pc.set_id
        HAVING ownedCards >= totalCards AND totalCards > 0
      ''', [serialNumber, serialNumber, serialNumber, serialNumber, serialNumber]);
    } else {
      return null;
    }
    return result.isEmpty ? null : Map<String, dynamic>.from(result.first);
  }

  /// Sposta tutte le carte di un set a un album diverso.
  /// [setIdentifier]: set_name per YGO, set_id per OP.
  Future<void> moveSetCardsToAlbum(String collection, String setIdentifier, int albumId) async {
    Database db = await database;
    if (collection == 'yugioh') {
      await db.rawUpdate('''
        UPDATE cards SET albumId = ?
        WHERE collection = 'yugioh'
          AND CAST(catalogId AS INTEGER) IN (
            SELECT card_id FROM yugioh_prints WHERE set_name = ?
          )
      ''', [albumId, setIdentifier]);
    } else if (collection == 'onepiece') {
      await db.rawUpdate('''
        UPDATE cards SET albumId = ?
        WHERE collection = 'onepiece'
          AND CAST(catalogId AS INTEGER) IN (
            SELECT card_id FROM onepiece_prints WHERE set_id = ?
          )
      ''', [albumId, setIdentifier]);
    } else if (collection == 'pokemon') {
      await db.rawUpdate('''
        UPDATE cards SET albumId = ?
        WHERE collection = 'pokemon'
          AND CAST(catalogId AS INTEGER) IN (
            SELECT pp.card_id FROM pokemon_prints pp
            JOIN pokemon_cards pc ON pc.id = pp.card_id
            WHERE pc.set_id = ?
          )
      ''', [albumId, setIdentifier]);
    }
  }

  // ============================================================
  // Firestore Sync Helper Methods
  // ============================================================

  Future<void> updateFirestoreId(String tableName, int localId, String firestoreId) async {
    Database db = await database;
    await db.update(
      tableName,
      {'firestoreId': firestoreId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<String?> getFirestoreId(String tableName, int localId) async {
    Database db = await database;
    final result = await db.query(tableName, columns: ['firestoreId'], where: 'id = ?', whereArgs: [localId]);
    if (result.isNotEmpty) {
      return result.first['firestoreId'] as String?;
    }
    return null;
  }

  Future<AlbumModel?> getAlbumByFirestoreId(String firestoreId) async {
    Database db = await database;
    final r = await db.query('albums', where: 'firestoreId = ?', whereArgs: [firestoreId]);
    return r.isNotEmpty ? AlbumModel.fromMap(r.first) : null;
  }

  Future<CardModel?> getCardByFirestoreId(String firestoreId) async {
    Database db = await database;
    final r = await db.query('cards', where: 'firestoreId = ?', whereArgs: [firestoreId]);
    return r.isNotEmpty ? CardModel.fromMap(r.first) : null;
  }

  Future<void> deleteAlbumByFirestoreId(String firestoreId) async {
    Database db = await database;
    await db.delete('albums', where: 'firestoreId = ?', whereArgs: [firestoreId]);
  }

  Future<void> deleteCardByFirestoreId(String firestoreId) async {
    Database db = await database;
    final r = await db.query('cards', columns: ['id'], where: 'firestoreId = ?', whereArgs: [firestoreId]);
    if (r.isNotEmpty) await deleteCard(r.first['id'] as int);
  }

  /// Delete albums and cards that have NO firestoreId and are NOT in pending_sync.
  /// These are orphaned rows (sync was lost) — they would duplicate remote items
  /// when pullFromCloud() inserts them with a firestoreId.
  Future<void> deleteOrphanedItems() async {
    // Safe to call only after Firestore is confirmed reachable (called inside
    // pullFromCloud after the fetch succeeds). Deletes rows that have no
    // firestoreId AND are not in pending_sync — those are true orphans left
    // by a partial/timed-out push where Firestore accepted the write but the
    // local updateFirestoreId never ran. Without this, pullFromCloud() sees
    // them as "not in Firestore" → inserts a fresh copy → duplicate.
    // Records in pending_sync are offline additions waiting to be pushed → kept.
    final db = await database;
    await db.rawDelete('''
      DELETE FROM cards
      WHERE firestoreId IS NULL
        AND id NOT IN (
          SELECT local_id FROM pending_sync WHERE table_name = 'cards'
        )
    ''');
    await db.rawDelete('''
      DELETE FROM albums
      WHERE firestoreId IS NULL
        AND id NOT IN (
          SELECT local_id FROM pending_sync WHERE table_name = 'albums'
        )
    ''');
  }

  /// Find a local card with no firestoreId matching the given print.
  /// Used by pullFromCloud() to claim a pending-sync card as the pulled one
  /// instead of inserting a duplicate.
  Future<CardModel?> findOrphanCard({
    required String serialNumber,
    required String collection,
  }) async {
    final db = await database;
    final r = await db.query(
      'cards',
      where: 'serialNumber = ? AND collection = ? AND firestoreId IS NULL',
      whereArgs: [serialNumber, collection],
      limit: 1,
    );
    return r.isNotEmpty ? CardModel.fromMap(r.first) : null;
  }

  /// Find a local album with no firestoreId matching the given name+collection.
  /// Used by pullFromCloud() to avoid inserting a duplicate album.
  Future<AlbumModel?> findOrphanAlbum({
    required String name,
    required String collection,
  }) async {
    final db = await database;
    final r = await db.query(
      'albums',
      where: 'name = ? AND collection = ? AND firestoreId IS NULL',
      whereArgs: [name, collection],
      limit: 1,
    );
    return r.isNotEmpty ? AlbumModel.fromMap(r.first) : null;
  }

  /// Delete albums that have a firestoreId but it's NOT in [keepIds].
  /// Albums without a firestoreId (offline-created, not yet synced) are untouched.
  Future<void> deleteAlbumsNotInFirestoreIds(List<String> keepIds) async {
    if (keepIds.isEmpty) {
      // Remote returned nothing — could be offline or a transient error.
      // Do NOT delete local data: we can't distinguish "user deleted all" from "fetch failed".
      return;
    }
    final db = await database;
    final placeholders = keepIds.map((_) => '?').join(',');
    await db.rawDelete(
      'DELETE FROM albums WHERE firestoreId IS NOT NULL AND firestoreId NOT IN ($placeholders)',
      keepIds,
    );
  }

  /// Delete cards that have a firestoreId but it's NOT in [keepIds].
  /// Cards without a firestoreId (offline-created, not yet synced) are untouched.
  Future<void> deleteCardsNotInFirestoreIds(List<String> keepIds) async {
    if (keepIds.isEmpty) {
      // Remote returned nothing — do NOT delete local data (same reason as albums above).
      return;
    }
    final db = await database;
    final placeholders = keepIds.map((_) => '?').join(',');
    await db.rawDelete(
      'DELETE FROM cards WHERE firestoreId IS NOT NULL AND firestoreId NOT IN ($placeholders)',
      keepIds,
    );
  }

  Future<void> addPendingSync(String tableName, int localId, String changeType, {String? data}) async {
    Database db = await database;
    await db.insert('pending_sync', {
      'table_name': tableName,
      'local_id': localId,
      'change_type': changeType,
      'data': data,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSync() async {
    Database db = await database;
    return await db.query('pending_sync', orderBy: 'created_at ASC');
  }

  /// Accoda uno sblocco collezione non ancora confermato da Firestore.
  ///
  /// `pending_sync` non aveva una riga per gli sblocchi: il push era
  /// best-effort e, se falliva (offline, App Check, regole), lo sblocco
  /// restava solo locale — finché `pullFromCloud` non lo revocava, perché
  /// riallinea lo stato dei lucchetti a quello che dice il remoto. Per
  /// l'utente significava perdere una collezione appena sbloccata guardando
  /// una rewarded per intero.
  ///
  /// La chiave della collezione sta in `data`: `local_id` non serve, gli
  /// sblocchi sono identificati da una stringa e non da un id di riga.
  Future<void> addPendingCollectionUnlock(String collectionKey) async {
    Database db = await database;
    await db.delete(
      'pending_sync',
      where: "table_name = 'collections' AND change_type = 'unlock' AND data = ?",
      whereArgs: [collectionKey],
    );
    await db.insert('pending_sync', {
      'table_name': 'collections',
      'local_id': 0,
      'change_type': 'unlock',
      'data': collectionKey,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Collezioni sbloccate localmente ma non ancora confermate dal remoto.
  Future<Set<String>> getPendingCollectionUnlocks() async {
    Database db = await database;
    final rows = await db.query(
      'pending_sync',
      columns: ['data'],
      where:
          "table_name = 'collections' AND change_type = 'unlock' AND data IS NOT NULL",
    );
    return rows.map((r) => r['data'] as String).toSet();
  }

  /// Rimuove dalla coda lo sblocco di [collectionKey], una volta confermato.
  Future<void> clearPendingCollectionUnlock(String collectionKey) async {
    Database db = await database;
    await db.delete(
      'pending_sync',
      where: "table_name = 'collections' AND change_type = 'unlock' AND data = ?",
      whereArgs: [collectionKey],
    );
  }

  Future<int> getPendingSyncCount() async {
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM pending_sync');
    return result.first['count'] as int? ?? 0;
  }

  /// Restituisce il timestamp più recente tra cards e albums (updated_at),
  /// utile per capire se il locale ha dati più aggiornati del cloud.
  Future<DateTime?> getMaxLocalUpdatedAt() async {
    Database db = await database;
    final result = await db.rawQuery('''
      SELECT MAX(updated_at) as max_ts FROM (
        SELECT updated_at FROM cards
        UNION ALL
        SELECT updated_at FROM albums
      )
    ''');
    final ts = result.first['max_ts'] as String?;
    if (ts == null) return null;
    return DateTime.tryParse(ts);
  }

  Future<void> clearPendingSync({int? id}) async {
    Database db = await database;
    if (id != null) {
      await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.delete('pending_sync');
    }
  }

  Future<List<AlbumModel>> getAllAlbums() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, (SELECT COALESCE(SUM(c.quantity), 0) FROM cards c WHERE c.albumId = a.id) as currentCount
      FROM albums a
    ''');
    return List.generate(maps.length, (i) => AlbumModel.fromMap(maps[i]));
  }

  Future<List<CardModel>> getAllCards() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query('cards');
    return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
  }

  Future<List<Map<String, dynamic>>> getAllCardtraderPrices(String catalog) async {
    final db = await database;
    return db.query('cardtrader_prices', where: 'catalog = ?', whereArgs: [catalog]);
  }

  /// Returns CT coverage stats for each collection.
  /// Each map has: catalog, localCards, ctBlueprints, ctPriced.
  Future<List<Map<String, dynamic>>> getCardtraderCoverageStats() async {
    final db = await database;

    // Count local catalog cards per collection (includes all v36 tables)
    final localCounts = <String, int>{};
    try {
      for (final row in await db.rawQuery('''
        SELECT 'yugioh'           AS catalog, COUNT(*) AS n FROM yugioh_cards
        UNION ALL SELECT 'pokemon',           COUNT(*) FROM pokemon_cards
        UNION ALL SELECT 'onepiece',          COUNT(*) FROM onepiece_cards
        UNION ALL SELECT 'magic',             COUNT(*) FROM magic_cards
        UNION ALL SELECT 'digimon',           COUNT(*) FROM digimon_cards
        UNION ALL SELECT 'lorcana',           COUNT(*) FROM lorcana_cards
        UNION ALL SELECT 'flesh-and-blood',   COUNT(*) FROM fab_cards
        UNION ALL SELECT 'vanguard',          COUNT(*) FROM vanguard_cards
        UNION ALL SELECT 'dragon-ball-super', COUNT(*) FROM dragonball_cards
        UNION ALL SELECT 'star-wars',         COUNT(*) FROM starwars_cards
        UNION ALL SELECT 'riftbound',         COUNT(*) FROM riftbound_cards
        UNION ALL SELECT 'gundam',            COUNT(*) FROM gundam_cards
        UNION ALL SELECT 'union-arena',       COUNT(*) FROM union_arena_cards
      ''')) {
        localCounts[row['catalog'] as String] = (row['n'] as int? ?? 0);
      }
    } catch (_) {
      // Fallback per DB non ancora migrati a v36
      for (final row in await db.rawQuery('''
        SELECT 'yugioh' AS catalog, COUNT(*) AS n FROM yugioh_cards
        UNION ALL SELECT 'pokemon', COUNT(*) FROM pokemon_cards
        UNION ALL SELECT 'onepiece', COUNT(*) FROM onepiece_cards
      ''')) {
        localCounts[row['catalog'] as String] = (row['n'] as int? ?? 0);
      }
    }

    // Count distinct CT blueprints per catalog (blueprint_id is per-card, not per-language)
    final ctRows = await db.rawQuery('''
      SELECT catalog,
             COUNT(DISTINCT blueprint_id) AS ct_blueprints,
             COUNT(DISTINCT CASE WHEN min_price_any_cents IS NOT NULL THEN blueprint_id END) AS ct_priced
      FROM cardtrader_prices
      GROUP BY catalog
    ''');
    final ctMap = <String, Map<String, int>>{};
    for (final row in ctRows) {
      final cat = row['catalog'] as String;
      ctMap[cat] = {
        'ct_blueprints': row['ct_blueprints'] as int? ?? 0,
        'ct_priced': row['ct_priced'] as int? ?? 0,
      };
    }

    // Include all known CT-syncable catalogs, skip those with 0 local cards AND 0 CT blueprints
    const allCatalogs = [
      'yugioh', 'pokemon', 'onepiece', 'magic',
      'digimon', 'lorcana', 'flesh-and-blood', 'vanguard',
      'dragon-ball-super', 'star-wars', 'riftbound', 'gundam', 'union-arena',
    ];

    return allCatalogs
        .map((cat) => {
              'catalog': cat,
              'localCards': localCounts[cat] ?? 0,
              'ctBlueprints': ctMap[cat]?['ct_blueprints'] ?? 0,
              'ctPriced': ctMap[cat]?['ct_priced'] ?? 0,
            })
        .where((r) =>
            (r['localCards'] as int) > 0 ||
            (r['ctBlueprints'] as int) > 0)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAllDecks() async {
    Database db = await database;
    return await db.query('decks');
  }

  Future<List<Map<String, dynamic>>> getAllDeckCards() async {
    Database db = await database;
    return await db.query('deck_cards');
  }

  Future<void> resetCollectionsLockState() async {
    Database db = await database;
    await db.update('collections', {'isUnlocked': 0});
  }

  Future<void> clearUserData() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('deck_cards');
      await txn.delete('decks');
      await txn.delete('cards');
      await txn.delete('albums');
      await txn.delete('pending_sync');
      // Reset all collections to locked - unlock state is per-user
      await txn.update('collections', {'isUnlocked': 0});
    });
  }

  /// Clear ALL data including user data and catalog (for logout/account switch)
  /// CRITICAL for privacy: prevents data leaks between different accounts
  Future<void> clearAllData() async {
    Database db = await database;
    await db.transaction((txn) async {
      // User data tables
      await txn.delete('deck_cards');
      await txn.delete('decks');
      await txn.delete('cards');
      await txn.delete('albums');
      await txn.delete('pending_sync');

      // Catalog tables (will be re-downloaded on next login)
      await txn.delete('catalog_cards');
      await txn.delete('catalog_card_sets');
      await txn.delete('catalog_metadata');

      // Yu-Gi-Oh specific tables
      await txn.delete('yugioh_cards');
      await txn.delete('yugioh_prints');
      await txn.delete('yugioh_prices');
    });
  }

  // ─────────────────────────────────────────────────────────────
  // One Piece catalog
  // ─────────────────────────────────────────────────────────────

  Future<void> clearOnepieceCatalog() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('onepiece_prints');
      await txn.delete('onepiece_cards');
      await txn.delete('catalog_metadata', where: 'catalog_name = ?', whereArgs: ['onepiece']);
    });
  }

  Future<void> deleteOnepieceCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.rawDelete('DELETE FROM onepiece_prints WHERE card_id IN ($placeholders)', ids);
      await txn.rawDelete('DELETE FROM onepiece_cards WHERE id IN ($placeholders)', ids);
    });
  }

  Future<void> insertOnepieceCards(
    List<Map<String, dynamic>> cards, {
    void Function(double progress)? onProgress,
  }) async {
    if (cards.isEmpty) return;
    final db = await database;

    const batchSize = 200;
    int processed = 0;

    for (int i = 0; i < cards.length; i += batchSize) {
      final batch = cards.sublist(i, (i + batchSize).clamp(0, cards.length));
      await db.transaction((txn) async {
        for (final card in batch) {
          final prints = card['prints'] as List<dynamic>? ?? [];
          final now = DateTime.now().toIso8601String();

          // Resolve image URL: prefer Cloudinary (imageUrl), then raw image_url.
          // CT download (uploadImages:false) stores no URL → reconstruct OPTCG fallback
          // from first print's card_set_id so SQLite has something before migration.
          String? resolvedImageUrl = card['imageUrl'] as String? ?? card['image_url'] as String?;
          if (resolvedImageUrl == null || resolvedImageUrl.isEmpty) {
            final firstPrint = prints.isNotEmpty ? prints.first as Map? : null;
            final cardSetId = firstPrint?['card_set_id'] as String?;
            if (cardSetId != null && cardSetId.isNotEmpty) {
              resolvedImageUrl =
                  'https://en.onepiece-cardgame.com/images/cardlist/card/$cardSetId.png';
            }
          }

          // Usa ON CONFLICT DO UPDATE invece di REPLACE per evitare che la
          // CASCADE DELETE cancelli i print esistenti (con artwork Firebase).
          int cardId;
          if (card['id'] != null) {
            await txn.rawInsert('''
              INSERT INTO onepiece_cards
                (id, name, card_type, color, cost, power, life,
                 sub_types, counter_amount, attribute, card_text, image_url,
                 created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                name           = excluded.name,
                card_type      = excluded.card_type,
                color          = excluded.color,
                cost           = excluded.cost,
                power          = excluded.power,
                life           = excluded.life,
                sub_types      = excluded.sub_types,
                counter_amount = excluded.counter_amount,
                attribute      = excluded.attribute,
                card_text      = excluded.card_text,
                image_url      = excluded.image_url,
                updated_at     = excluded.updated_at
            ''', [
              card['id'], card['name'] ?? '',
              card['card_type'], card['color'],
              card['cost'], card['power'], card['life'],
              card['sub_types'], card['counter_amount'],
              card['attribute'], card['card_text'], resolvedImageUrl,
              now, now,
            ]);
            cardId = card['id'] as int;
          } else {
            cardId = await txn.insert(
              'onepiece_cards',
              {
                'name': card['name'] ?? '',
                'card_type': card['card_type'],
                'color': card['color'],
                'cost': card['cost'],
                'power': card['power'],
                'life': card['life'],
                'sub_types': card['sub_types'],
                'counter_amount': card['counter_amount'],
                'attribute': card['attribute'],
                'card_text': card['card_text'],
                'image_url': resolvedImageUrl,
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }

          // Va bene qualunque URL assoluto, non solo Backblaze/Cloudinary.
          // Con il solo filtro "hosted" una carta senza immagine già migrata
          // restava senza immagine del tutto, e la migrazione di un catalogo
          // intero richiede giorni: intanto l'URL della sorgente si carica
          // benissimo. La preferenza per lo storage proprio resta, ma si
          // esprime nell'ON CONFLICT qui sotto, che non lascia mai un URL B2
          // sovrascrivere da uno esterno.
          bool isUsableImageUrl(String? url) =>
              url != null && (url.startsWith('https://') || url.startsWith('http://'));
          final cardImageUrl = card['imageUrl'] as String? ?? card['image_url'] as String?;
          final cardArtwork = isUsableImageUrl(cardImageUrl) ? cardImageUrl : null;
          for (final p in prints) {
            final print = Map<String, dynamic>.from(p as Map);
            final rawArtwork = print['artwork'] as String? ?? cardImageUrl;
            final artwork = isUsableImageUrl(rawArtwork) ? rawArtwork : cardArtwork;
            // ON CONFLICT: aggiorna tutti i campi eccetto artwork — se il nuovo
            // valore non è hosted, preserva quello già in SQLite.
            await txn.rawInsert('''
              INSERT INTO onepiece_prints
                (card_id, card_set_id, blueprint_id, set_id, set_name, rarity,
                 inventory_price, market_price, market_price_en, market_price_fr,
                 market_price_ko, market_price_zh, artwork,
                 created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(card_set_id) DO UPDATE SET
                card_id          = excluded.card_id,
                blueprint_id     = COALESCE(excluded.blueprint_id, blueprint_id),
                set_id           = excluded.set_id,
                set_name         = excluded.set_name,
                rarity           = excluded.rarity,
                inventory_price  = excluded.inventory_price,
                market_price     = COALESCE(excluded.market_price, market_price),
                market_price_en  = COALESCE(excluded.market_price_en, market_price_en),
                market_price_fr  = COALESCE(excluded.market_price_fr, market_price_fr),
                market_price_ko  = COALESCE(excluded.market_price_ko, market_price_ko),
                market_price_zh  = COALESCE(excluded.market_price_zh, market_price_zh),
                artwork          = COALESCE(
                  CASE WHEN excluded.artwork LIKE '%backblazeb2.com%'
                            OR excluded.artwork LIKE '%cloudinary.com%'
                       THEN excluded.artwork END,
                  artwork
                ),
                updated_at       = excluded.updated_at
            ''', [
              cardId,
              print['card_set_id'],
              print['blueprint_id']?.toString(),
              print['set_id'],
              print['set_name'],
              print['rarity'],
              print['inventory_price'],
              print['market_price'],
              print['market_price_en'],
              print['market_price_fr'],
              print['market_price_ko'],
              print['market_price_zh'],
              artwork,
              now, now,
            ]);
          }
        }
      });

      await Future.delayed(const Duration(milliseconds: 20)); // yield between batches
      processed += batch.length;
      onProgress?.call(processed / cards.length);
    }
  }

  Future<List<Map<String, dynamic>>> getOnepieceCatalogCards({
    String? query,
    String language = 'EN',
    int limit = 60,
    int offset = 0,
  }) async {
    final db = await database;
    final suffix = _langSuffix(language);
    final hasLang = suffix.isNotEmpty;

    final setNameCol = hasLang ? 'COALESCE(op.set_name$suffix, op.set_name)' : 'op.set_name';
    final rarityCol  = hasLang ? 'COALESCE(op.rarity$suffix, op.rarity)'     : 'op.rarity';

    // Filtro lingua: deriva dalla struttura del card_set_id.
    // JP (predefinito One Piece) → collector-number inizia con cifra (es. OP01-001)
    // EN/FR/IT/… → collector-number inizia con il codice a 2 lettere (es. OP01-EN001)
    final upperLang = language.toUpperCase();
    final String langFilter;
    if (upperLang == 'JP') {
      // ID reali OPTCG JP: hanno cifre SIA prima che dopo il '-' (es. OP01-001).
      // ID surrogate CardTrader (BANDAI-245405, UP-244176) hanno lettere prima del
      // '-' → esclusi controllando che il char immediatamente prima di '-' sia una cifra.
      langFilter = '''
        AND INSTR(op.card_set_id, '-') > 0
        AND SUBSTR(op.card_set_id, INSTR(op.card_set_id, '-') + 1, 1) BETWEEN '0' AND '9'
        AND SUBSTR(op.card_set_id, INSTR(op.card_set_id, '-') - 1, 1) BETWEEN '0' AND '9'
        ''';
    } else {
      langFilter = '''
        AND INSTR(op.card_set_id, '-') > 0
        AND UPPER(SUBSTR(op.card_set_id, INSTR(op.card_set_id, '-') + 1, 2)) = '$upperLang' ''';
    }

    final String searchPattern = '%${query ?? ''}%';
    String whereClause = '';
    if (query != null && query.isNotEmpty) {
      whereClause = '''
        WHERE (
          oc.name LIKE ?
          OR op.card_set_id LIKE ?
          OR op.set_name LIKE ?
          OR oc.color LIKE ?
          OR oc.card_type LIKE ?
        )
        $langFilter''';
    }

    final isLocalizedPrint = hasLang
        ? 'CASE WHEN op.set_name$suffix IS NOT NULL THEN 1 ELSE 0 END'
        : '1';

    final sql = '''
      SELECT
        oc.id, oc.name, oc.card_type, oc.color, oc.cost, oc.power,
        oc.life, oc.sub_types, oc.counter_amount, oc.attribute,
        oc.card_text, oc.image_url,
        op.id AS printId,
        op.card_set_id AS setCode,
        op.set_id AS setId,
        op.set_name AS setName,
        $setNameCol AS localizedSetName,
        op.rarity,
        $rarityCol AS localizedRarity,
        op.inventory_price AS inventoryPrice,
        -- Prezzo per la lingua selezionata: JP=market_price, EN=market_price_en, ecc.
        -- Fallback a JP se la colonna lingua non è ancora popolata.
        COALESCE(
          ctp.ct_price_cents / 100.0,
          CASE '$upperLang'
            WHEN 'EN' THEN COALESCE(op.market_price_en, op.market_price)
            WHEN 'FR' THEN COALESCE(op.market_price_fr, op.market_price)
            WHEN 'KO' THEN COALESCE(op.market_price_ko, op.market_price)
            WHEN 'ZH' THEN COALESCE(op.market_price_zh, op.market_price)
            ELSE op.market_price
          END
        ) AS marketPrice,
        -- Fallback a image_url della card se artwork (Firebase Storage) non è ancora migrato
        COALESCE(op.artwork, oc.image_url) AS artwork,
        'onepiece' AS collection,
        $isLocalizedPrint AS isLocalizedPrint,
        EXISTS(SELECT 1 FROM cards WHERE catalogId = CAST(oc.id AS TEXT) AND collection = 'onepiece') AS isOwned
      FROM onepiece_cards oc
      INNER JOIN onepiece_prints op ON oc.id = op.card_id
      LEFT JOIN (
        SELECT
          expansion_code,
          CAST(collector_number AS INTEGER) AS cn_int,
          MIN(min_price_any_cents) AS ct_price_cents
        FROM cardtrader_prices
        WHERE catalog = 'onepiece' AND min_price_any_cents IS NOT NULL
        GROUP BY expansion_code, cn_int
      ) ctp ON (
        LOWER(SUBSTR(op.card_set_id, 1, INSTR(op.card_set_id, '-') - 1)) = ctp.expansion_code
        AND CAST(SUBSTR(op.card_set_id, INSTR(op.card_set_id, '-') + 1) AS INTEGER) = ctp.cn_int
      )
      ${query != null && query.isNotEmpty ? whereClause : 'WHERE 1=1 $langFilter'}
      GROUP BY oc.id, op.card_set_id, op.rarity
      ORDER BY op.card_set_id
      LIMIT ? OFFSET ?
    ''';

    final args = query != null && query.isNotEmpty
        ? [searchPattern, searchPattern, searchPattern, searchPattern, searchPattern, limit, offset]
        : [limit, offset];

    return await db.rawQuery(sql, args);
  }

  /// Returns all prints for a single One Piece card, with fields mapped for
  /// use in the card dialog (setCode, setRarity, marketPrice).
  Future<List<Map<String, dynamic>>> getOnepieceCardPrints(int cardId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        op.card_set_id AS setCode,
        op.set_name    AS setName,
        op.rarity      AS setRarity,
        op.market_price AS marketPrice,
        COALESCE(op.artwork, oc.image_url) AS artwork
      FROM onepiece_prints op
      LEFT JOIN onepiece_cards oc ON oc.id = op.card_id
      WHERE op.card_id = ?
      ORDER BY op.card_set_id
    ''', [cardId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ─── CardTrader price cache ────────────────────────────────────────────────

  /// Returns distinct lowercase set codes present in the local catalog.
  /// Used to filter which CardTrader expansions to sync.
  Future<Set<String>> getDistinctSetCodesForCardtrader(String catalog) async {
    final db = await database;
    List<Map<String, dynamic>> rows;

    switch (catalog) {
      case 'yugioh':
        // set_id populated in v14 migration (e.g. "LOB" → stored as "LOB")
        rows = await db.rawQuery('''
          SELECT DISTINCT LOWER(set_id) AS code
          FROM yugioh_prints
          WHERE set_id IS NOT NULL AND set_id != ''
        ''');
      case 'pokemon':
        // pokemon_cards.set_id (e.g. "swsh1", "sv1")
        rows = await db.rawQuery('''
          SELECT DISTINCT LOWER(set_id) AS code
          FROM pokemon_cards
          WHERE set_id IS NOT NULL AND set_id != ''
        ''');
      case 'onepiece':
        // set_id (e.g. "OP01") when present; otherwise derive from card_set_id prefix
        // (e.g. "OP01-001" → "op01") so prints with null set_id are still matched.
        rows = await db.rawQuery('''
          SELECT DISTINCT LOWER(COALESCE(
            NULLIF(set_id, ''),
            CASE WHEN card_set_id LIKE '%-%'
                 THEN SUBSTR(card_set_id, 1, INSTR(card_set_id, '-') - 1)
                 ELSE card_set_id END
          )) AS code
          FROM onepiece_prints
          WHERE card_set_id IS NOT NULL AND card_set_id != ''
        ''');
      default:
        return {};
    }

    return rows.map((r) => r['code'] as String).toSet();
  }

  /// Upserts a batch of price records into the local CardTrader cache.
  /// Each item must expose a `toMap()` method returning the column map.
  Future<void> upsertCardtraderPrices(List<Map<String, dynamic>> priceMaps) async {
    final db = await database;
    final batch = db.batch();
    for (final m in priceMaps) {
      batch.insert(
        'cardtrader_prices',
        m,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Inserts one price snapshot per (blueprint, language, edition, rarity) per day.
  /// Uses INSERT OR IGNORE so re-running on the same day is a no-op.
  Future<void> insertPriceHistorySnapshots(List<Map<String, dynamic>> priceMaps) async {
    final db = await database;
    final batch = db.batch();
    for (final m in priceMaps) {
      final priceCents = (m['min_price_nm_cents'] ?? m['min_price_any_cents']) as int?;
      if (priceCents == null) continue;
      final syncedAt = m['synced_at'] as String? ?? '';
      final recordedDate = syncedAt.length >= 10 ? syncedAt.substring(0, 10) : syncedAt;
      if (recordedDate.isEmpty) continue;
      batch.rawInsert('''
        INSERT OR IGNORE INTO price_history
          (blueprint_id, language, first_edition, rarity, price_cents, listing_count, recorded_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        m['blueprint_id'],
        m['language'],
        m['first_edition'] ?? 0,
        m['rarity'] ?? '',
        priceCents,
        m['listing_count'] ?? 0,
        recordedDate,
      ]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getPriceHistory({
    required int blueprintId,
    required String language,
    required int firstEdition,
    required String rarity,
    required String from,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT recorded_date, price_cents, listing_count
      FROM price_history
      WHERE blueprint_id = ?
        AND language = ?
        AND first_edition = ?
        AND rarity = ?
        AND recorded_date >= ?
      ORDER BY recorded_date ASC
    ''', [blueprintId, language, firstEdition, rarity, from]);
  }

  /// Seeds blueprint rows for the target language.
  ///
  /// For NEW blueprints (never seen before): inserts with listing_count=0 and
  /// null prices.
  /// For EXISTING blueprints: only resets listing_count to 0 — preserves the
  /// last known price and synced_at so historical prices remain visible.
  ///
  /// The subsequent [upsertCardtraderPrices] call then fills in current prices
  /// for blueprints that have active marketplace listings. Cards that are no
  /// longer listed keep their old price (visible to users with a "last seen"
  /// date) instead of becoming blank.
  Future<void> insertBlueprintsIfAbsent(
      List<Map<String, dynamic>> blueprintMaps) async {
    final db = await database;
    final batch = db.batch();
    for (final m in blueprintMaps) {
      // INSERT new rows with null prices.
      // ON CONFLICT (existing row): only reset listing_count — do NOT touch
      // min_price_nm_cents, min_price_any_cents, or synced_at so that
      // historical prices survive until the marketplace step overwrites them.
      batch.rawInsert('''
        INSERT INTO cardtrader_prices
          (blueprint_id, catalog, expansion_code, card_name_en,
           language, first_edition, rarity, collector_number,
           listing_count, synced_at,
           min_price_nm_cents, min_price_any_cents)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, NULL, NULL)
        ON CONFLICT(blueprint_id, language, first_edition, rarity)
        DO UPDATE SET listing_count = 0
      ''', [
        m['blueprint_id'], m['catalog'], m['expansion_code'], m['card_name_en'],
        m['language'], m['first_edition'], m['rarity'], m['collector_number'] ?? '',
        m['synced_at'],
      ]);
    }
    await batch.commit(noResult: true);
  }

  /// Looks up a cached [CardtraderPrice] for a card.
  ///
  /// Matches on [catalog], [expansionCode] (lowercase), and a
  /// case-insensitive [cardName]. If [firstEdition] is null the row with
  /// the lowest [min_price_any_cents] is returned regardless of edition.
  /// If [rarity] is provided, filters to that rarity (case-insensitive).
  Future<Map<String, dynamic>?> getCardtraderPrice({
    required String catalog,
    required String expansionCode,
    required String cardName,
    required String language,
    bool? firstEdition,
    String? rarity,
    String? collectorNumber,
    String? catalogId,
  }) async {
    final db = await database;

    // If catalogId is provided resolve the canonical English name from the
    // catalog table so that localized card names (e.g. "Drago Bianco") don't
    // break the match against CT's English-only card_name_en column.
    String nameLower = cardName.toLowerCase();
    if (catalogId != null && catalogId.isNotEmpty) {
      final id = int.tryParse(catalogId);
      if (id != null) {
        final table = switch (catalog) {
          'yugioh'   => 'yugioh_cards',
          'pokemon'  => 'pokemon_cards',
          'onepiece' => 'onepiece_cards',
          _          => null,
        };
        if (table != null) {
          final rows = await db.query(table,
              columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
          if (rows.isNotEmpty) {
            nameLower = (rows.first['name'] as String).toLowerCase();
          }
        }
      }
    }

    String baseWhere =
        'catalog = ? AND expansion_code = ? AND LOWER(card_name_en) = ? AND language = ?'
        ' AND min_price_any_cents IS NOT NULL';
    final baseArgs = <dynamic>[catalog, expansionCode.toLowerCase(), nameLower, language];

    if (firstEdition != null) {
      baseWhere += ' AND first_edition = ?';
      baseArgs.add(firstEdition ? 1 : 0);
    }
    if (rarity != null && rarity.isNotEmpty) {
      baseWhere += ' AND LOWER(rarity) = ?';
      baseArgs.add(rarity.toLowerCase());
    }

    // ── 1. Try with collector_number for exact artwork match ────────────────
    if (collectorNumber != null && collectorNumber.isNotEmpty) {
      final rows = await db.query(
        'cardtrader_prices',
        where: '$baseWhere AND LOWER(collector_number) = ?',
        whereArgs: [...baseArgs, collectorNumber.toLowerCase()],
        orderBy: 'min_price_any_cents ASC',
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }

    // ── 2. Fallback: best price regardless of collector_number ──────────────
    final rows = await db.query(
      'cardtrader_prices',
      where: baseWhere,
      whereArgs: baseArgs,
      orderBy: 'min_price_any_cents ASC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Returns all CardTrader prices for a card across every available language.
  ///
  /// Matches by expansion_code + card_name_en. If [collectorNumber] is provided
  /// it first tries an exact artwork match, then falls back to any artwork.
  /// Returns one row per language (best price for that language).
  Future<List<Map<String, dynamic>>> getPricesForCardAllLanguages({
    required String catalog,
    required String expansionCode,
    required String cardName,
    String? rarity,
    String? collectorNumber,
    String? catalogId,
  }) async {
    final db = await database;
    final exp = expansionCode.toLowerCase();
    // Order: priced rows first (min_price_any_cents DESC NULLS LAST), then lang
    const orderBy = '(min_price_any_cents IS NOT NULL) DESC, language ASC, min_price_any_cents ASC';

    List<Map<String, dynamic>> rows = [];

    // ── Helper to dedup by language ──────────────────────────────────────────
    List<Map<String, dynamic>> dedup(List<Map<String, dynamic>> r) {
      final seen = <String>{};
      return r.where((row) => seen.add(row['language'] as String)).toList();
    }

    // ── Resolve English name via catalog JOIN (bypasses localized card.name) ─
    String? nameEn;
    if (catalogId != null && catalogId.isNotEmpty) {
      final idInt = int.tryParse(catalogId);
      if (idInt != null) {
        final table = switch (catalog) {
          'yugioh'   => 'yugioh_cards',
          'pokemon'  => 'pokemon_cards',
          'onepiece' => 'onepiece_cards',
          _ => null,
        };
        if (table != null) {
          final r = await db.query(table, columns: ['name'], where: 'id = ?', whereArgs: [idInt], limit: 1);
          if (r.isNotEmpty) nameEn = (r.first['name'] as String?)?.toLowerCase();
        }
      }
    }
    // Fall back to the passed name if catalog lookup failed
    final nameLower = nameEn ?? cardName.toLowerCase();

    // ── Normalize collector number ──────────────────────────────────────────
    // Try the raw value lowercased ("it001") AND the stripped version ("001").
    // CT stores the raw CN (e.g. "IT001") — always include the raw form.
    String? cnRaw;  // lowercased as-is: "it001"
    String? cnNorm; // prefix-stripped:  "001"
    if (collectorNumber != null && collectorNumber.isNotEmpty) {
      cnRaw  = collectorNumber.toLowerCase();
      cnNorm = collectorNumber.replaceFirst(RegExp(r'^[A-Za-z]{2}(?=[A-Za-z0-9])'), '').toLowerCase();
      if (cnNorm == cnRaw) cnNorm = null; // no stripping happened — avoid duplicate
    }

    // ── 1. expansion + name + rarity (all languages, priced or not) ────────
    // Rarity is applied first (matching getCardtraderPrice behaviour) so that
    // when multiple blueprints exist for the same card (e.g. "R" vs "RR")
    // the detail page shows the correct variant instead of the cheapest one.
    if (rows.isEmpty) {
      String w = 'catalog = ? AND expansion_code = ? AND LOWER(card_name_en) = ?';
      final a = <dynamic>[catalog, exp, nameLower];
      if (rarity != null && rarity.isNotEmpty) {
        w += ' AND LOWER(rarity) = ?';
        a.add(rarity.toLowerCase());
      }
      // Try raw CN first (e.g. "it001"), then stripped (e.g. "001")
      for (final cn in [cnRaw, cnNorm].whereType<String>()) {
        rows = await db.query('cardtrader_prices',
            where: '$w AND LOWER(collector_number) = ?',
            whereArgs: [...a, cn], orderBy: orderBy);
        if (rows.isNotEmpty) break;
      }
      if (rows.isEmpty) {
        rows = await db.query('cardtrader_prices', where: w, whereArgs: a, orderBy: orderBy);
      }
      // If rarity filter returned nothing, retry without rarity to avoid
      // showing blank prices when CT stores a slightly different rarity string.
      if (rows.isEmpty && rarity != null && rarity.isNotEmpty) {
        final wNr = 'catalog = ? AND expansion_code = ? AND LOWER(card_name_en) = ?';
        final aNr = <dynamic>[catalog, exp, nameLower];
        for (final cn in [cnRaw, cnNorm].whereType<String>()) {
          rows = await db.query('cardtrader_prices',
              where: '$wNr AND LOWER(collector_number) = ?',
              whereArgs: [...aNr, cn], orderBy: orderBy);
          if (rows.isNotEmpty) break;
        }
        if (rows.isEmpty) {
          rows = await db.query('cardtrader_prices', where: wNr, whereArgs: aNr, orderBy: orderBy);
        }
      }
    }

    // ── 2. Fallback: expansion + collector_number only ───────────────────────
    if (rows.isEmpty && (cnRaw != null || cnNorm != null)) {
      final digits = RegExp(r'\d+$').firstMatch(cnNorm ?? cnRaw ?? '')?.group(0) ?? '';
      final candidates = <String>{
        if (cnRaw != null) cnRaw,
        if (cnNorm != null) cnNorm,
        if (digits.isNotEmpty) digits,
      };
      for (final cn in candidates) {
        rows = await db.query(
          'cardtrader_prices',
          where: 'catalog = ? AND expansion_code = ? AND LOWER(collector_number) = ?',
          whereArgs: [catalog, exp, cn.toLowerCase()],
          orderBy: orderBy,
        );
        if (rows.isNotEmpty) break;
      }
    }

    final result = dedup(rows);

    return result;
  }

  /// Reads prices from local catalog prints tables as a fallback when
  /// [getPricesForCardAllLanguages] returns nothing (i.e., no admin CT sync yet).
  /// Returns rows shaped like [cardtrader_prices] rows, with blueprint_id = 0.
  Future<List<Map<String, dynamic>>> getCatalogPricesForCard({
    required String catalog,
    required String cardName,
    String? catalogId,
    String? serialNumber,
  }) async {
    final db = await database;

    Map<String, dynamic> makeRow(String lang, dynamic price, String expCode,
        String nameEn, String rarity, String? ctSyncedAt) {
      final cents = price != null ? ((price as num).toDouble() * 100).round() : 0;
      if (cents <= 0) return {};
      return {
        'blueprint_id': 0,
        'catalog': catalog,
        'expansion_code': expCode,
        'card_name_en': nameEn,
        'language': lang,
        'first_edition': 0,
        'rarity': rarity,
        'collector_number': '',
        'min_price_nm_cents': cents,
        'min_price_any_cents': cents,
        'listing_count': 0,
        // Use real CT sync date when available; empty string hides stale "today" date in UI
        'synced_at': ctSyncedAt ?? '',
      };
    }

    if (catalog == 'pokemon') {
      int? cardDbId = int.tryParse(catalogId ?? '');
      if (cardDbId == null && catalogId != null && catalogId.isNotEmpty) {
        final r = await db.query('pokemon_cards',
            columns: ['id'], where: 'api_id = ?', whereArgs: [catalogId], limit: 1);
        if (r.isNotEmpty) cardDbId = r.first['id'] as int?;
      }
      if (cardDbId == null) return [];
      final rows = await db.rawQuery('''
        SELECT pp.set_price, pp.set_price_it, pp.set_price_fr, pp.set_price_de,
               pp.set_price_es, pp.set_price_pt, pp.rarity, pp.set_code, pp.ct_synced_at, pc.name
        FROM pokemon_prints pp
        JOIN pokemon_cards pc ON pc.id = pp.card_id
        WHERE pp.card_id = ?
        ORDER BY (CASE WHEN pp.set_price > 0 THEN 1 ELSE 0 END) DESC
        LIMIT 1
      ''', [cardDbId]);
      if (rows.isEmpty) return [];
      final row = rows.first;
      final n = row['name'] as String? ?? cardName;
      final r = row['rarity'] as String? ?? '';
      final exp = ((row['set_code'] as String?) ?? '').split('-').first.toLowerCase();
      final ctDate = row['ct_synced_at'] as String?;
      final langMap = <String, dynamic>{
        'en': row['set_price'], 'it': row['set_price_it'],
        'fr': row['set_price_fr'], 'de': row['set_price_de'],
        'es': row['set_price_es'], 'pt': row['set_price_pt'],
      };
      return langMap.entries
          .map((e) => makeRow(e.key, e.value, exp, n, r, ctDate))
          .where((m) => m.isNotEmpty)
          .toList();
    }

    if (catalog == 'yugioh') {
      final cardDbId = int.tryParse(catalogId ?? '');
      if (cardDbId == null) return [];
      final rows = await db.rawQuery('''
        SELECT yp.set_price, yp.set_price_it, yp.set_price_fr, yp.set_price_de,
               yp.set_price_pt, yp.set_price_sp, yp.rarity, yp.set_code, yp.ct_synced_at, yc.name
        FROM yugioh_prints yp
        JOIN yugioh_cards yc ON yc.id = yp.card_id
        WHERE yp.card_id = ?
        ORDER BY (CASE WHEN yp.set_price > 0 THEN 1 ELSE 0 END) DESC
        LIMIT 1
      ''', [cardDbId]);
      if (rows.isEmpty) return [];
      final row = rows.first;
      final n = row['name'] as String? ?? cardName;
      final r = row['rarity'] as String? ?? '';
      final exp = ((row['set_code'] as String?) ?? '').split('-').first.toLowerCase();
      final ctDate = row['ct_synced_at'] as String?;
      final langMap = <String, dynamic>{
        'en': row['set_price'], 'it': row['set_price_it'],
        'fr': row['set_price_fr'], 'de': row['set_price_de'],
        'pt': row['set_price_pt'], 'es': row['set_price_sp'],
      };
      return langMap.entries
          .map((e) => makeRow(e.key, e.value, exp, n, r, ctDate))
          .where((m) => m.isNotEmpty)
          .toList();
    }

    if (catalog == 'onepiece') {
      final cardDbId = int.tryParse(catalogId ?? '');
      if (cardDbId == null) return [];
      final rows = await db.rawQuery('''
        SELECT op.market_price, op.market_price_en, op.market_price_fr,
               op.market_price_ko, op.market_price_zh,
               op.rarity, op.set_id, op.ct_synced_at, oc.name
        FROM onepiece_prints op
        JOIN onepiece_cards oc ON oc.id = op.card_id
        WHERE op.card_id = ?
        ORDER BY (CASE WHEN op.market_price > 0 THEN 1 ELSE 0 END) DESC
        LIMIT 1
      ''', [cardDbId]);
      if (rows.isEmpty) return [];
      final row = rows.first;
      final n = row['name'] as String? ?? cardName;
      final r = row['rarity'] as String? ?? '';
      final exp = ((row['set_id'] as String?) ?? '').toLowerCase();
      final ctDate = row['ct_synced_at'] as String?;
      final langMap = <String, dynamic>{
        'ja': row['market_price'], 'en': row['market_price_en'],
        'fr': row['market_price_fr'], 'ko': row['market_price_ko'],
        'zh': row['market_price_zh'],
      };
      return langMap.entries
          .map((e) => makeRow(e.key, e.value, exp, n, r, ctDate))
          .where((m) => m.isNotEmpty)
          .toList();
    }

    return [];
  }

  /// Aggiorna i prezzi nelle tabelle del catalogo (yugioh_prints, pokemon_prints,
  /// onepiece_prints) leggendo i prezzi CT già in cache locale.
  /// Questo rende i prezzi CT visibili a TUTTE le carte del catalogo,
  /// non solo a quelle possedute.
  ///
  /// Multi-pass per massimizzare il match:
  ///   Pass 1 — nome normalizzato (apostrofi unicode, em-dash, trim).
  ///   Pass 2 — nome CT con suffisso " (...)" rimosso (Speed Duel, Duel Links…).
  ///   Pass 3 — collector_number come chiave alternativa quando il nome fallisce.
  ///
  /// Returns the total number of print rows updated.
  // ── Chiavi di match dei prezzi CardTrader ────────────────────────────────
  //
  // Le passate di [syncCatalogPricesFromCardtrader] confrontavano colonne
  // avvolte in LOWER/SUBSTR/INSTR/REPLACE su entrambi i lati. Con la funzione
  // applicata alla colonna indicizzata nessun indice è utilizzabile, quindi
  // ogni riga di stampa scandiva l'intero bucket di espansione di
  // `cardtrader_prices` (250k righe sul solo Yu-Gi-Oh) applicando cinque
  // REPLACE per candidato — trenta volte di fila. Il risultato era un download
  // fermo al 100% e, siccome sqflite serializza tutte le query su una sola
  // connessione, l'intera app bloccata dietro quella coda.
  //
  // Qui la normalizzazione si calcola una volta sola e si persiste, così i
  // confronti tornano colonna = colonna e gli indici sotto entrano in gioco.

  /// True se [table] esiste nel database aperto.
  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  /// Aggiunge le colonne di match e i relativi indici. Idempotente.
  ///
  /// Ogni tabella viene verificata prima di toccarla: `_addColumnIfMissing` su
  /// una tabella assente lancia "no such table", e in `onUpgrade` un'eccezione
  /// fa fallire `openDatabase` — cioè l'app non parte più. Questa migrazione
  /// gira su ogni installazione già in giro, comprese quelle che vengono da
  /// versioni in cui alcune di queste tabelle non esistevano.
  Future<void> _createPriceMatchKeys(DatabaseExecutor db) async {
    Future<bool> addTo(String table, List<String> columns) async {
      if (!await _tableExists(db, table)) return false;
      for (final c in columns) {
        await _addColumnIfMissing(db, table, c, 'TEXT');
      }
      return true;
    }

    final hasPrices = await addTo(
      'cardtrader_prices',
      ['name_norm', 'name_base_norm', 'cn_lc'],
    );

    await addTo('yugioh_prints', ['set_id_lc', 'cn_primary', 'cn_secondary']);
    await addTo('yugioh_cards', ['name_norm']);
    await addTo('pokemon_prints', ['set_code_lc']);
    await addTo('pokemon_cards', ['set_id_lc', 'name_norm']);
    await addTo('onepiece_prints', ['exp_code_lc']);
    await addTo('onepiece_cards', ['name_norm']);

    if (!hasPrices) return;

    // `language` va in coda: le passate per lingua la filtrano per uguaglianza
    // (quindi resta utilizzabile come quarta colonna dell'indice) e la passata
    // dei metadati, che la lingua non la filtra affatto, usa lo stesso indice
    // fermandosi alle prime tre.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ct_prices_name_norm '
      'ON cardtrader_prices(catalog, expansion_code, name_norm, language)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ct_prices_name_base '
      'ON cardtrader_prices(catalog, expansion_code, name_base_norm, language)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ct_prices_cn_lc '
      'ON cardtrader_prices(catalog, expansion_code, cn_lc, language)',
    );
  }

  /// Riempie le colonne di match rimaste vuote per [catalog].
  ///
  /// Le colonne derivate sono sempre non-NULL una volta calcolate (si usa `''`
  /// come "non applicabile"), quindi `IS NULL` è il flag di "ancora da fare":
  /// costa una scansione per tabella al primo giro e quasi nulla dopo.
  /// `upsertCardtraderPrices` inserisce con `ConflictAlgorithm.replace`, che
  /// riazzera le derivate delle righe riscritte — ed è esattamente quello che
  /// serve, perché il refresh le ricalcoli al sync successivo.
  Future<void> _refreshPriceMatchKeys(Database db, String catalog) async {
    await db.rawUpdate(
      '''
      UPDATE cardtrader_prices
      SET name_norm      = ${_normName('card_name_en')},
          name_base_norm = ${_ctNameBase('card_name_en')},
          cn_lc          = LOWER(collector_number)
      WHERE catalog = ? AND name_norm IS NULL
      ''',
      [catalog],
    );

    switch (catalog) {
      case 'yugioh':
        // cn_primary   = suffisso dopo il trattino di set_code ("LOB-EN001" → "en001")
        // cn_secondary = stesso suffisso senza prefisso lingua ("001"), solo quando
        //                il primo supera i 3 caratteri: è la seconda forma con cui
        //                CardTrader indicizza lo stesso blueprint.
        await db.rawUpdate('''
          UPDATE yugioh_prints
          SET set_id_lc    = COALESCE(LOWER(set_id), ''),
              cn_primary   = CASE WHEN INSTR(set_code, '-') > 0
                                  THEN LOWER(SUBSTR(set_code, INSTR(set_code, '-') + 1))
                                  ELSE '' END,
              cn_secondary = CASE WHEN INSTR(set_code, '-') > 0
                                   AND LENGTH(SUBSTR(set_code, INSTR(set_code, '-') + 1)) > 3
                                  THEN LOWER(SUBSTR(set_code, INSTR(set_code, '-') + 3))
                                  ELSE '' END
          WHERE set_id_lc IS NULL
        ''');
        await db.rawUpdate(
          "UPDATE yugioh_cards SET name_norm = ${_normName('name')} "
          'WHERE name_norm IS NULL',
        );

      case 'pokemon':
        await db.rawUpdate(
          'UPDATE pokemon_prints SET set_code_lc = LOWER(set_code) '
          'WHERE set_code_lc IS NULL',
        );
        await db.rawUpdate(
          'UPDATE pokemon_cards '
          "SET name_norm = ${_normName('name')}, "
          "    set_id_lc = COALESCE(LOWER(set_id), '') "
          'WHERE name_norm IS NULL',
        );

      case 'onepiece':
        await db.rawUpdate('''
          UPDATE onepiece_prints
          SET exp_code_lc = COALESCE(LOWER(COALESCE(
                NULLIF(set_id, ''),
                CASE WHEN card_set_id LIKE '%-%'
                     THEN SUBSTR(card_set_id, 1, INSTR(card_set_id, '-') - 1)
                     ELSE card_set_id END)), '')
          WHERE exp_code_lc IS NULL
        ''');
        await db.rawUpdate(
          "UPDATE onepiece_cards SET name_norm = ${_normName('name')} "
          'WHERE name_norm IS NULL',
        );
    }
  }

  /// Aggancia i prezzi CardTrader in cache alle tabelle di stampa del catalogo.
  /// Ritorna il numero di righe aggiornate.
  ///
  /// [onProgress] riceve 0.0→1.0 sull'avanzamento delle passate: senza, la UI
  /// del download restava ferma al 100% per tutta la durata di questo lavoro,
  /// che è la parte più lunga dell'intera operazione.
  Future<int> syncCatalogPricesFromCardtrader(
    String catalog, {
    void Function(double progress)? onProgress,
  }) async {
    final db = await database;
    int total = 0;

    // Passate per lingua × catalogo, più la passata dei metadati e il refresh
    // delle chiavi: serve solo a dare una frazione onesta a onProgress.
    final int stepsTotal = switch (catalog) {
      'yugioh' => 1 + 6 * 3 + 1,
      'pokemon' => 1 + 6 * 2 + 1,
      'onepiece' => 1 + 5 * 2 + 1,
      _ => 1,
    };
    var stepsDone = 0;
    void tick() {
      stepsDone++;
      onProgress?.call((stepsDone / stepsTotal).clamp(0.0, 1.0));
    }

    await _refreshPriceMatchKeys(db, catalog);
    tick();

    switch (catalog) {
      case 'yugioh':
        const ygoLangCols = <String, String>{
          'en': 'set_price',
          'it': 'set_price_it',
          'fr': 'set_price_fr',
          'de': 'set_price_de',
          'pt': 'set_price_pt',
          'es': 'set_price_sp',
        };
        for (final entry in ygoLangCols.entries) {
          final lang = entry.key;
          final col = entry.value;

          // ── Passata 0: match per collector number (PRIMARIA, distingue le rarità) ──
          // Il suffisso di set_code ("LOB-EN001" → "en001") identifica il
          // blueprint rarità compresa, quindi va prima dei match per nome.
          // `cp.cn_lc <> ''` tiene fuori il bucket dei prezzi senza collector
          // number, che cn_secondary vuoto farebbe altrimenti agganciare.
          total += await db.rawUpdate('''
            UPDATE yugioh_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              WHERE cp.catalog = 'yugioh'
                AND cp.expansion_code = yugioh_prints.set_id_lc
                AND cp.cn_lc IN (yugioh_prints.cn_primary, yugioh_prints.cn_secondary)
                AND cp.cn_lc <> ''
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE yugioh_prints.set_id_lc <> ''
              AND yugioh_prints.cn_primary <> ''
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                WHERE cp.catalog = 'yugioh'
                  AND cp.expansion_code = yugioh_prints.set_id_lc
                  AND cp.cn_lc IN (yugioh_prints.cn_primary, yugioh_prints.cn_secondary)
                  AND cp.cn_lc <> ''
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''', [lang, lang]);
          tick();

          // ── Passata 1: match per nome normalizzato ────────────────────────
          total += await db.rawUpdate('''
            UPDATE yugioh_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
              WHERE cp.catalog = 'yugioh'
                AND cp.expansion_code = yugioh_prints.set_id_lc
                AND cp.name_norm = yc.name_norm
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE yugioh_prints.set_id_lc <> ''
              AND $col IS NULL
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
                WHERE cp.catalog = 'yugioh'
                  AND cp.expansion_code = yugioh_prints.set_id_lc
                  AND cp.name_norm = yc.name_norm
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''', [lang, lang]);
          tick();

          // ── Passata 2: nome CT senza il qualificatore " (...)" ────────────
          // Copre blueprint tipo "Polymerization (Speed Duel)" o
          // "Dark Magician (Duel Links)", che differiscono solo per il suffisso.
          total += await db.rawUpdate('''
            UPDATE yugioh_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
              WHERE cp.catalog = 'yugioh'
                AND cp.expansion_code = yugioh_prints.set_id_lc
                AND cp.name_base_norm = yc.name_norm
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE yugioh_prints.set_id_lc <> ''
              AND $col IS NULL
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
                WHERE cp.catalog = 'yugioh'
                  AND cp.expansion_code = yugioh_prints.set_id_lc
                  AND cp.name_base_norm = yc.name_norm
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''', [lang, lang]);
          tick();

          // NB: qui c'era una quarta passata su collector number identica alla
          // passata 0 tranne che per il guardiano `$col IS NULL`. Era codice
          // morto: le righe che arrivavano fin lì con la colonna ancora vuota
          // sono esattamente quelle su cui la passata 0 non aveva trovato
          // corrispondenza, quindi il suo EXISTS era falso per costruzione.
        }

        // Metadati sync CT per stampa: data e conteggio annunci.
        total += await db.rawUpdate('''
          UPDATE yugioh_prints
          SET ct_synced_at = (
            SELECT MAX(cp.synced_at)
            FROM cardtrader_prices cp
            JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
            WHERE cp.catalog = 'yugioh'
              AND cp.expansion_code = yugioh_prints.set_id_lc
              AND cp.name_norm = yc.name_norm
              AND cp.min_price_any_cents IS NOT NULL
          ),
          ct_listing_count = COALESCE((
            SELECT cp.listing_count
            FROM cardtrader_prices cp
            JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
            WHERE cp.catalog = 'yugioh'
              AND cp.expansion_code = yugioh_prints.set_id_lc
              AND cp.name_norm = yc.name_norm
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.listing_count > 0) DESC, cp.min_price_any_cents ASC
            LIMIT 1
          ), 0)
          WHERE yugioh_prints.set_id_lc <> ''
        ''');
        tick();

      case 'pokemon':
        const pokeLangCols = <String, String>{
          'en': 'set_price',
          'it': 'set_price_it',
          'fr': 'set_price_fr',
          'de': 'set_price_de',
          'es': 'set_price_es',
          'pt': 'set_price_pt',
        };
        for (final entry in pokeLangCols.entries) {
          final lang = entry.key;
          final col = entry.value;

          // ── Passata 1: match per nome normalizzato ────────────────────────
          total += await db.rawUpdate('''
            UPDATE pokemon_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
              WHERE cp.catalog = 'pokemon'
                AND cp.expansion_code = pc.set_id_lc
                AND cp.name_norm = pc.name_norm
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE EXISTS (
              SELECT 1 FROM cardtrader_prices cp
              JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
              WHERE cp.catalog = 'pokemon'
                AND cp.expansion_code = pc.set_id_lc
                AND cp.name_norm = pc.name_norm
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
            )
          ''', [lang, lang]);
          tick();

          // ── Passata 2: fallback su collector number ───────────────────────
          // pokemon_prints.set_code È il collector number ("001", "SWSH001"),
          // lo stesso valore che CT tiene in collector_number.
          total += await db.rawUpdate('''
            UPDATE pokemon_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
              WHERE cp.catalog = 'pokemon'
                AND cp.expansion_code = pc.set_id_lc
                AND cp.cn_lc = pokemon_prints.set_code_lc
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE $col IS NULL
              AND pokemon_prints.set_code_lc <> ''
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
                WHERE cp.catalog = 'pokemon'
                  AND cp.expansion_code = pc.set_id_lc
                  AND cp.cn_lc = pokemon_prints.set_code_lc
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''', [lang, lang]);
          tick();
        }

        // Metadati sync CT per stampa Pokémon.
        total += await db.rawUpdate('''
          UPDATE pokemon_prints
          SET ct_synced_at = (
            SELECT MAX(cp.synced_at)
            FROM cardtrader_prices cp
            JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
            WHERE cp.catalog = 'pokemon'
              AND cp.expansion_code = pc.set_id_lc
              AND cp.name_norm = pc.name_norm
              AND cp.min_price_any_cents IS NOT NULL
          ),
          ct_listing_count = COALESCE((
            SELECT cp.listing_count
            FROM cardtrader_prices cp
            JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
            WHERE cp.catalog = 'pokemon'
              AND cp.expansion_code = pc.set_id_lc
              AND cp.name_norm = pc.name_norm
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.listing_count > 0) DESC, cp.min_price_any_cents ASC
            LIMIT 1
          ), 0)
        ''');
        tick();

      case 'onepiece':
        const opLangCols = <String, String>{
          'ja': 'market_price',
          'en': 'market_price_en',
          'fr': 'market_price_fr',
          'ko': 'market_price_ko',
          'zh': 'market_price_zh',
        };

        for (final entry in opLangCols.entries) {
          final lang = entry.key;
          final col = entry.value;

          // ── Passata 1: match per nome normalizzato ────────────────────────
          total += await db.rawUpdate('''
            UPDATE onepiece_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
              WHERE cp.catalog = 'onepiece'
                AND cp.expansion_code = onepiece_prints.exp_code_lc
                AND cp.name_norm = oc.name_norm
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE onepiece_prints.exp_code_lc <> ''
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
                WHERE cp.catalog = 'onepiece'
                  AND cp.expansion_code = onepiece_prints.exp_code_lc
                  AND cp.name_norm = oc.name_norm
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''', [lang, lang]);
          tick();

          // ── Passata 2: nome CT senza il qualificatore " (...)" ────────────
          total += await db.rawUpdate('''
            UPDATE onepiece_prints
            SET $col = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
              WHERE cp.catalog = 'onepiece'
                AND cp.expansion_code = onepiece_prints.exp_code_lc
                AND cp.name_base_norm = oc.name_norm
                AND cp.language = ?
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE onepiece_prints.exp_code_lc <> ''
              AND $col IS NULL
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
                WHERE cp.catalog = 'onepiece'
                  AND cp.expansion_code = onepiece_prints.exp_code_lc
                  AND cp.name_base_norm = oc.name_norm
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''', [lang, lang]);
          tick();
        }

        // Metadati sync CT per stampa One Piece.
        total += await db.rawUpdate('''
          UPDATE onepiece_prints
          SET ct_synced_at = (
            SELECT MAX(cp.synced_at)
            FROM cardtrader_prices cp
            JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
            WHERE cp.catalog = 'onepiece'
              AND cp.expansion_code = onepiece_prints.exp_code_lc
              AND cp.name_norm = oc.name_norm
              AND cp.min_price_any_cents IS NOT NULL
          ),
          ct_listing_count = COALESCE((
            SELECT cp.listing_count
            FROM cardtrader_prices cp
            JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
            WHERE cp.catalog = 'onepiece'
              AND cp.expansion_code = onepiece_prints.exp_code_lc
              AND cp.name_norm = oc.name_norm
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.listing_count > 0) DESC, cp.min_price_any_cents ASC
            LIMIT 1
          ), 0)
          WHERE onepiece_prints.exp_code_lc <> ''
        ''');
        tick();
    }

    onProgress?.call(1.0);
    return total;
  }

  /// Updates `cards.cardtrader_value` directly from `cardtrader_prices` so the
  /// card list shows the same fresh value as the detail page.
  ///
  /// For users/admins without a local catalog the print tables (yugioh_prints etc.)
  /// are empty, so `syncCatalogPricesFromCardtrader` leaves `cards.cardtrader_value`
  /// stale. This method bypasses the print tables and writes the NM-preferred
  /// CT price straight onto each card row.
  ///
  ///   YuGiOh   → expansion_code + collector_number from serial "LOB-EN001"
  ///   One Piece → full serial as collector_number  ("op01-001")
  ///   Pokemon   → name join on pokemon_cards (requires local catalog)
  Future<int> updateCardsValueFromCardtrader(String catalog) async {
    final db = await database;
    int updated = 0;

    switch (catalog) {
      case 'yugioh':
        // Serial "LOB-EN001" → expansion = "lob", cn = "en001"
        // Also tries digit-only CN ("001") for CTs that strip the lang prefix.
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            WHERE cp.catalog = 'yugioh'
              AND cp.expansion_code = LOWER(SUBSTR(cards.serialNumber, 1,
                    INSTR(cards.serialNumber, '-') - 1))
              AND (
                LOWER(cp.collector_number) = LOWER(SUBSTR(cards.serialNumber,
                      INSTR(cards.serialNumber, '-') + 1))
                OR (LENGTH(SUBSTR(cards.serialNumber, INSTR(cards.serialNumber, '-') + 1)) > 3
                    AND LOWER(cp.collector_number) = LOWER(SUBSTR(cards.serialNumber,
                          INSTR(cards.serialNumber, '-') + 3)))
              )
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = 'yugioh'
            AND INSTR(serialNumber, '-') > 0
            AND EXISTS (
              SELECT 1 FROM cardtrader_prices cp
              WHERE cp.catalog = 'yugioh'
                AND cp.expansion_code = LOWER(SUBSTR(cards.serialNumber, 1,
                      INSTR(cards.serialNumber, '-') - 1))
                AND (
                  LOWER(cp.collector_number) = LOWER(SUBSTR(cards.serialNumber,
                        INSTR(cards.serialNumber, '-') + 1))
                  OR (LENGTH(SUBSTR(cards.serialNumber, INSTR(cards.serialNumber, '-') + 1)) > 3
                      AND LOWER(cp.collector_number) = LOWER(SUBSTR(cards.serialNumber,
                            INSTR(cards.serialNumber, '-') + 3)))
                )
            )
        ''');

      case 'onepiece':
        // Try direct serial match (CT often stores full serial as collector_number).
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            WHERE cp.catalog = 'onepiece'
              AND LOWER(cp.collector_number) = LOWER(cards.serialNumber)
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = 'onepiece'
            AND EXISTS (
              SELECT 1 FROM cardtrader_prices cp
              WHERE cp.catalog = 'onepiece'
                AND LOWER(cp.collector_number) = LOWER(cards.serialNumber)
            )
        ''');

        // Fallback: name join on local catalog (if downloaded).
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            JOIN onepiece_cards oc ON oc.id = CAST(cards.catalogId AS INTEGER)
            WHERE cp.catalog = 'onepiece'
              AND (${_normName('cp.card_name_en')} = ${_normName('oc.name')}
                   OR ${_ctNameBase('cp.card_name_en')} = ${_normName('oc.name')})
              AND cp.expansion_code = LOWER(CASE WHEN INSTR(cards.serialNumber, '-') > 0
                    THEN SUBSTR(cards.serialNumber, 1, INSTR(cards.serialNumber, '-') - 1)
                    ELSE cards.serialNumber END)
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = 'onepiece'
            AND cardtrader_value IS NULL
            AND catalogId IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM onepiece_cards oc WHERE oc.id = CAST(cards.catalogId AS INTEGER)
            )
        ''');

      case 'pokemon':
        // Name join on local catalog.
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            JOIN pokemon_cards pc ON (pc.id = CAST(cards.catalogId AS INTEGER)
                                   OR pc.api_id = cards.catalogId)
            WHERE cp.catalog = 'pokemon'
              AND (${_normName('cp.card_name_en')} = ${_normName('pc.name')}
                   OR ${_ctNameBase('cp.card_name_en')} = ${_normName('pc.name')})
              AND cp.expansion_code = LOWER(CASE WHEN INSTR(cards.serialNumber, '-') > 0
                    THEN SUBSTR(cards.serialNumber, 1, INSTR(cards.serialNumber, '-') - 1)
                    ELSE cards.serialNumber END)
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = 'pokemon'
            AND catalogId IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM pokemon_cards pc
              WHERE pc.id = CAST(cards.catalogId AS INTEGER) OR pc.api_id = cards.catalogId
            )
        ''');

      default:
        // Generic catalogs (digimon, lorcana, flesh-and-blood, vanguard,
        // dragon-ball-super, star-wars, riftbound, gundam, union-arena).
        // No dedicated print tables — update cards.cardtrader_value directly.

        // Pass 1: full serialNumber == collector_number (e.g. "OP01-001").
        // Works for games where CT uses the complete card code as CN.
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            WHERE cp.catalog = ?
              AND LOWER(cp.collector_number) = LOWER(cards.serialNumber)
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = ?
            AND EXISTS (
              SELECT 1 FROM cardtrader_prices cp
              WHERE cp.catalog = ?
                AND LOWER(cp.collector_number) = LOWER(cards.serialNumber)
            )
        ''', [catalog, catalog, catalog]);

        // Pass 2: expansion_code (prefix before '-') + collector_number (suffix after '-').
        // Handles formats like "BT1-001" → expansion='bt1', cn='001'.
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            WHERE cp.catalog = ?
              AND INSTR(cards.serialNumber, '-') > 0
              AND cp.expansion_code = LOWER(SUBSTR(cards.serialNumber, 1,
                    INSTR(cards.serialNumber, '-') - 1))
              AND (
                LOWER(cp.collector_number) = LOWER(SUBSTR(cards.serialNumber,
                      INSTR(cards.serialNumber, '-') + 1))
              )
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = ?
            AND cardtrader_value IS NULL
            AND INSTR(serialNumber, '-') > 0
            AND EXISTS (
              SELECT 1 FROM cardtrader_prices cp
              WHERE cp.catalog = ?
                AND cp.expansion_code = LOWER(SUBSTR(cards.serialNumber, 1,
                      INSTR(cards.serialNumber, '-') - 1))
                AND LOWER(cp.collector_number) = LOWER(SUBSTR(cards.serialNumber,
                      INSTR(cards.serialNumber, '-') + 1))
            )
        ''', [catalog, catalog, catalog]);

        // Pass 3: expansion_code + name match (cards.name may be English for CT-sourced cards).
        updated += await db.rawUpdate('''
          UPDATE cards
          SET cardtrader_value = (
            SELECT COALESCE(cp.min_price_nm_cents, cp.min_price_any_cents) / 100.0
            FROM cardtrader_prices cp
            WHERE cp.catalog = ?
              AND (${_normName('cp.card_name_en')} = ${_normName('cards.name')}
                   OR ${_ctNameBase('cp.card_name_en')} = ${_normName('cards.name')})
              AND cp.expansion_code = LOWER(CASE WHEN INSTR(cards.serialNumber, '-') > 0
                    THEN SUBSTR(cards.serialNumber, 1, INSTR(cards.serialNumber, '-') - 1)
                    ELSE cards.serialNumber END)
              AND cp.min_price_any_cents IS NOT NULL
            ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
            LIMIT 1
          )
          WHERE collection = ?
            AND cardtrader_value IS NULL
            AND EXISTS (
              SELECT 1 FROM cardtrader_prices cp
              WHERE cp.catalog = ?
                AND (${_normName('cp.card_name_en')} = ${_normName('cards.name')}
                     OR ${_ctNameBase('cp.card_name_en')} = ${_normName('cards.name')})
                AND cp.expansion_code = LOWER(CASE WHEN INSTR(cards.serialNumber, '-') > 0
                      THEN SUBSTR(cards.serialNumber, 1, INSTR(cards.serialNumber, '-') - 1)
                      ELSE cards.serialNumber END)
            )
        ''', [catalog, catalog, catalog]);
    }

    return updated;
  }

  /// Applies Magic price rows (from Firestore `cardtrader_prices/magic`) directly
  /// to `magic_cards.price_eur`. Runs inside a single transaction for speed.
  /// Each row must have { api_id, price_eur }.
  Future<int> applyMagicPricesFromFirestore(
      List<Map<String, dynamic>> rows) async {
    final db = await database;
    int updated = 0;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final row in rows) {
        final apiId = row['api_id'] as String?;
        if (apiId == null) continue;
        final priceEur = (row['price_eur'] as num?)?.toDouble();
        updated += await txn.rawUpdate(
          'UPDATE magic_cards SET price_eur = ?, updated_at = ? WHERE api_id = ?',
          [priceEur, now, apiId],
        );
      }
    });
    return updated;
  }

  /// Normalizes a SQL column expression for fuzzy name matching.
  /// Trims whitespace, lowercases, and converts common Unicode variants to ASCII:
  ///   U+2019 ' → U+0027 '   (RIGHT SINGLE QUOTATION MARK)
  ///   U+2018 ' → U+0027 '   (LEFT SINGLE QUOTATION MARK)
  ///   U+00B4 ´ → U+0027 '   (ACUTE ACCENT)
  ///   U+2212 − → U+002D -   (MINUS SIGN)
  ///   U+2014 — → U+002D -   (EM DASH)
  static String _normName(String col) =>
      "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE("
      "TRIM(LOWER($col)),"
      "char(8217),char(39)),"  // ' → '
      "char(8216),char(39)),"  // ' → '
      "char(180),char(39)),"   // ´ → '
      "char(8722),char(45)),"  // − → -
      "char(8212),char(45))";  // — → -

  /// Like [_normName] but also strips a trailing " (...)" qualifier from CT card
  /// names (e.g. "Dark Magician (Duel Links)" → "dark magician").
  /// Only strips when the name ends with ')' and contains ' ('.
  static String _ctNameBase(String col) => _normName(
      "CASE WHEN SUBSTR(TRIM($col),-1)=')' AND INSTR($col,' (')>0"
      " THEN SUBSTR($col,1,INSTR($col,' (')-1)"
      " ELSE $col END");

  // ── AI Deck Builder ───────────────────────────────────────────────────────

  /// Restituisce le carte YGO possedute con info catalogo per l'AI Deck Builder.
  Future<List<Map<String, dynamic>>> getOwnedYugiohCardsForAi() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        yc.name, yc.type, yc.attribute, yc.level, yc.atk, yc.def,
        yc.race, yc.frame_type AS frameType,
        c.id AS owned_id, c.quantity, c.serialNumber,
        c.imageUrl
      FROM cards c
      JOIN yugioh_cards yc ON yc.id = CAST(c.catalogId AS INTEGER)
      WHERE c.collection = 'yugioh'
      ORDER BY yc.name
    ''');
  }

  // ── Wishlist ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getWishlistItemsEnriched() async {
    final db = await database;
    return db.rawQuery('''
      SELECT w.*,
        CASE w.collection
          WHEN 'yugioh' THEN (
            SELECT COALESCE(yp.set_price_it, yp.set_price)
            FROM yugioh_prints yp
            WHERE yp.card_id = CAST(w.catalogId AS INTEGER)
              AND (yp.set_code = w.serialNumber OR yp.set_code_it = w.serialNumber
                OR yp.set_code_fr = w.serialNumber OR yp.set_code_de = w.serialNumber
                OR yp.set_code_pt = w.serialNumber OR yp.set_code_sp = w.serialNumber)
            LIMIT 1
          )
          WHEN 'pokemon' THEN (
            SELECT COALESCE(pp.set_price_it, pp.set_price)
            FROM pokemon_prints pp
            WHERE pp.card_id = CAST(w.catalogId AS INTEGER)
              AND (pp.set_code = w.serialNumber OR pp.set_code_it = w.serialNumber)
            LIMIT 1
          )
          WHEN 'onepiece' THEN (
            SELECT COALESCE(op.market_price_en, op.market_price)
            FROM onepiece_prints op
            WHERE op.card_id = CAST(w.catalogId AS INTEGER)
            LIMIT 1
          )
          ELSE (
            SELECT ct.min_price_nm_cents / 100.0
            FROM cardtrader_prices ct
            WHERE ct.catalog = w.collection
              AND ct.card_name_en = w.name
              AND ct.listing_count > 0
            ORDER BY ct.min_price_nm_cents ASC
            LIMIT 1
          )
        END AS cardtrader_value
      FROM wishlist w
      ORDER BY w.added_at DESC
    ''');
  }

  Future<int> insertWishlistItem(Map<String, dynamic> item) async {
    final db = await database;
    return db.insert('wishlist', item, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> isInWishlist(String catalogId) async {
    final db = await database;
    final rows = await db.query('wishlist', where: 'catalogId = ?', whereArgs: [catalogId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getWishlistItems() async {
    final db = await database;
    return db.query('wishlist', orderBy: 'added_at DESC');
  }

  Future<int> deleteWishlistItem(int id) async {
    final db = await database;
    return db.delete('wishlist', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWishlistItemByCatalogId(String catalogId) async {
    final db = await database;
    return db.delete('wishlist', where: 'catalogId = ?', whereArgs: [catalogId]);
  }

  Future<Map<String, dynamic>?> getWishlistItemById(int id) async {
    final db = await database;
    final rows = await db.query('wishlist', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Set<String>> getAllWishlistCatalogIds() async {
    final db = await database;
    final rows = await db.query('wishlist', columns: ['catalogId']);
    return rows.map((r) => r['catalogId'] as String).toSet();
  }

  Future<int> updateWishlistTargetPrice(int id, double? targetPrice) async {
    final db = await database;
    return db.update(
      'wishlist',
      {'target_price': targetPrice},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
