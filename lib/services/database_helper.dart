import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/card_model.dart';
import '../models/collection_model.dart';
import '../models/album_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static const List<String> _validLanguages = ['EN', 'IT', 'FR', 'DE', 'PT', 'SP'];

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
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
      version: 21,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

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

    // cards table indices — critical for getCardsByCollection and getAlbumsByCollection
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_collection ON cards(collection)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_albumId ON cards(albumId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cards_catalogId ON cards(catalogId)');

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
  }

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
        set_id TEXT,
        set_name TEXT,
        rarity TEXT,
        inventory_price REAL,
        market_price REAL,
        artwork TEXT,
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
        set_code_pt TEXT,
        set_name_pt TEXT,
        rarity_pt TEXT,
        set_price_pt REAL,
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

  Future _onCreate(Database db, int version) async {
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

    // Dedicated expansion and rarity tables (v18)
    await _createExpansionRarityTables(db);
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
        set_name_pt TEXT,
        set_name_sp TEXT,
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
        rarity_pt   TEXT,
        rarity_sp   TEXT,
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
        SELECT set_name, NULL AS set_name_it, NULL AS set_name_fr,
               NULL AS set_name_de, NULL AS set_name_pt, NULL AS set_name_sp,
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
        'set_name_pt': row['set_name_pt'],
        'set_name_sp': row['set_name_sp'],
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
               MIN(rarity_de) AS rarity_de, MIN(rarity_pt) AS rarity_pt,
               NULL AS rarity_sp
        FROM pokemon_prints
        WHERE rarity IS NOT NULL AND rarity != ''
        GROUP BY rarity
      ''');
    } else if (catalog == 'onepiece') {
      rows = await db.rawQuery('''
        SELECT DISTINCT rarity, NULL AS rarity_code,
               NULL AS rarity_it, NULL AS rarity_fr,
               NULL AS rarity_de, NULL AS rarity_pt, NULL AS rarity_sp
        FROM onepiece_prints
        WHERE rarity IS NOT NULL AND rarity != ''
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
        'rarity_pt':  row['rarity_pt'],
        'rarity_sp':  row['rarity_sp'],
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
      if (id == null) return null;
      final rows = await db.query(
        'pokemon_cards',
        columns: ['hp', 'types', 'supertype', 'subtype'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }

    return null;
  }

  // Returns all owned card instances for a collection.
  // Used only to build _ownedQuantityMap (needs catalogId, serialNumber, quantity).
  // All fields are already stored in the cards table at insert time.
  Future<List<CardModel>> getCardsWithCatalog(String collection) async {
    Database db = await database;
    final maps = await db.query('cards', where: 'collection = ?', whereArgs: [collection]);
    return maps.map((row) => CardModel.fromMap(row)).toList();
  }

  Future<List<CardModel>> getCardsByCollection(String collection) async {
    Database db = await database;
    if (collection == 'yugioh') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, yc.name) as name,
               COALESCE(u.type, yc.type) as type,
               COALESCE(u.description, yc.description) as description,
               u.collection,
               COALESCE(
                 NULLIF(u.value, 0),
                 (SELECT set_price FROM yugioh_prints
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
               ) as imageUrl
        FROM cards u
        LEFT JOIN yugioh_cards yc ON yc.id = CAST(u.catalogId AS INTEGER)
        WHERE u.collection = 'yugioh'
      ''');
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    if (collection == 'onepiece') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, oc.name) as name,
               COALESCE(u.type, oc.card_type) as type,
               COALESCE(u.description, oc.card_text) as description,
               u.collection,
               COALESCE(NULLIF(u.value, 0), op.market_price) as value,
               COALESCE(
                 op.artwork,
                 oc.image_url,
                 u.imageUrl
               ) as imageUrl
        FROM cards u
        LEFT JOIN onepiece_cards oc ON oc.id = CAST(u.catalogId AS INTEGER)
        LEFT JOIN onepiece_prints op ON op.card_id = oc.id AND op.card_set_id = u.serialNumber
        WHERE u.collection = 'onepiece'
      ''');
      return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
    }

    if (collection == 'pokemon') {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT u.*,
               COALESCE(u.name, pc.name) as name,
               COALESCE(u.type, pc.supertype) as type,
               u.collection,
               COALESCE(
                 NULLIF(u.value, 0),
                 (SELECT set_price FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber)
                  LIMIT 1)
               ) as value,
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
        LEFT JOIN pokemon_cards pc ON pc.id = CAST(u.catalogId AS INTEGER)
        WHERE u.collection = 'pokemon'
      ''');
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
      WHERE u.collection = ?
    ''', [collection]);
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
        LEFT JOIN pokemon_cards pc ON pc.id = CAST(u.catalogId AS INTEGER)
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

  Future<Map<String, dynamic>> getGlobalStats() async {
    Database db = await database;

    final totalCards = await db.rawQuery('SELECT SUM(quantity) as total FROM cards');
    final uniqueCards = await db.rawQuery('SELECT COUNT(DISTINCT catalogId) as total FROM cards WHERE catalogId IS NOT NULL');
    final totalValue = await db.rawQuery('''
      SELECT SUM(
        COALESCE(NULLIF(c.cardtrader_value, 0), NULLIF(c.value, 0), 0)
        * c.quantity
      ) as total
      FROM cards c
    ''');
    final collections = await db.rawQuery('SELECT COUNT(*) as total FROM collections WHERE isUnlocked = 1');

    return {
      'totalCards': (totalCards.first['total'] as num?)?.toInt() ?? 0,
      'uniqueCards': uniqueCards.first['total'] as int? ?? 0,
      'totalValue': (totalValue.first['total'] as num?)?.toDouble() ?? 0.0,
      'unlockedCollections': collections.first['total'] as int? ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getStatsPerCollection() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT collection,
             SUM(quantity) as totalCards,
             SUM(COALESCE(NULLIF(cardtrader_value, 0), NULLIF(value, 0), 0) * quantity) as totalValue
      FROM cards
      GROUP BY collection
      ORDER BY totalValue DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getStatsPerRarity() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT rarity,
             SUM(quantity) as count,
             SUM(COALESCE(NULLIF(cardtrader_value, 0), NULLIF(value, 0), 0) * quantity) as totalValue
      FROM cards
      WHERE rarity != ''
      GROUP BY rarity
      ORDER BY count DESC
      LIMIT 10
    ''');
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

    await db.transaction((txn) async {
      int total = cards.length;
      const int batchSize = 200;

      for (int i = 0; i < total; i += batchSize) {
        int end = (i + batchSize < total) ? i + batchSize : total;
        List<Map<String, dynamic>> chunk = cards.sublist(i, end);

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

        onProgress?.call(end / total);
      }
    });
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

    await db.transaction((txn) async {
      int total = cards.length;
      const int batchSize = 200;

      for (int i = 0; i < total; i += batchSize) {
        int end = (i + batchSize < total) ? i + batchSize : total;
        List<Map<String, dynamic>> chunk = cards.sublist(i, end);

        Batch batch = txn.batch();
        for (var card in chunk) {
          final cardData = Map<String, dynamic>.from(card);
          final prints = cardData.remove('prints') as List<dynamic>?;

          batch.rawInsert('''
            INSERT OR REPLACE INTO pokemon_cards (
              api_id, name, supertype, subtype, hp, types, rarity,
              set_id, set_name, set_series, number, image_url,
              name_it, name_fr, name_de, name_pt,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                  set_code_pt, set_name_pt, rarity_pt, set_price_pt,
                  created_at, updated_at
                ) VALUES (
                  (SELECT id FROM pokemon_cards WHERE api_id = ?),
                  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
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
        onProgress?.call(end / total);
      }
    });
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
          OR pp.set_code LIKE ?
          OR pp.set_code_it LIKE ?
          OR pp.set_code_fr LIKE ?
          OR pp.set_code_de LIKE ?
          OR pp.set_code_pt LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q, q];
      } else {
        whereClause = '''WHERE (
          pc.name LIKE ?
          OR pp.set_code LIKE ?
          OR pp.set_code_it LIKE ?
          OR pp.set_code_fr LIKE ?
          OR pp.set_code_de LIKE ?
          OR pp.set_code_pt LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q];
      }
    }

    final isLocalizedPrint = hasLang ? 'CASE WHEN pp.set_name$suffix IS NOT NULL THEN 1 ELSE 0 END' : '1';

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
        pp.set_price AS setPrice,
        $setPriceCol AS localizedSetPrice,
        pp.artwork,
        'pokemon' AS collection,
        $isLocalizedPrint AS isLocalizedPrint,
        EXISTS(SELECT 1 FROM cards WHERE catalogId = CAST(pc.id AS TEXT) AND collection = 'pokemon') AS isOwned
      FROM pokemon_cards pc
      LEFT JOIN pokemon_prints pp ON pc.id = pp.card_id
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

  Future<List<Map<String, dynamic>>> getDecksByCollection(String collection) async {
    Database db = await database;
    return await db.query('decks', where: 'collection = ?', whereArgs: [collection]);
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
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = pp.card_id
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
      case 'yugioh':  return ['it', 'fr', 'de', 'pt', 'sp'];
      case 'pokemon': return ['it', 'fr', 'de', 'pt'];
      default:        return [];
    }
  }

  /// Restituisce tutte le espansioni per una collezione (dalla tabella dedicata).
  /// Campi restituiti compatibili con i vecchi consumatori: set_name, set_code, set_name_XX.
  Future<List<Map<String, dynamic>>> getDistinctSets(String collection) async {
    final rows = await getExpansions(collection);
    // Remap set_id → set_code per compatibilità con AdminSetsRaritiesPage
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
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = pp.card_id
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
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = pp.card_id
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
    // Intentionally a no-op: deleting cards/albums without a firestoreId is
    // too aggressive — those records are valid local data that hasn't been
    // pushed to Firestore yet (e.g. added offline or before sync was implemented).
    // Removing them would silently wipe the user's collection on every startup
    // if the Firestore pull returns 0 results (permission error, offline, etc).
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

          final cardId = await txn.insert(
            'onepiece_cards',
            {
              if (card['id'] != null) 'id': card['id'],
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
              'image_url': card['image_url'],
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Solo URL Firebase Storage sono accettati come immagini valide
          bool isFbStorage(String? url) =>
              url != null && url.contains('firebasestorage');
          final cardImageUrl = card['imageUrl'] as String? ?? card['image_url'] as String?;
          final cardArtwork = isFbStorage(cardImageUrl) ? cardImageUrl : null;
          for (final p in prints) {
            final print = Map<String, dynamic>.from(p as Map);
            final rawArtwork = print['artwork'] as String? ?? cardImageUrl;
            final artwork = isFbStorage(rawArtwork) ? rawArtwork : cardArtwork;
            await txn.insert(
              'onepiece_prints',
              {
                'card_id': cardId,
                'card_set_id': print['card_set_id'],
                'set_id': print['set_id'],
                'set_name': print['set_name'],
                'rarity': print['rarity'],
                'inventory_price': print['inventory_price'],
                'market_price': print['market_price'],
                'artwork': artwork,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });

      processed += batch.length;
      onProgress?.call(processed / cards.length);
    }
  }

  Future<List<Map<String, dynamic>>> getOnepieceCatalogCards({
    String? query,
    int limit = 60,
    int offset = 0,
  }) async {
    final db = await database;
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
        )''';
    }

    final sql = '''
      SELECT
        oc.id, oc.name, oc.card_type, oc.color, oc.cost, oc.power,
        oc.life, oc.sub_types, oc.counter_amount, oc.attribute,
        oc.card_text, oc.image_url,
        op.id AS printId,
        op.card_set_id AS setCode,
        op.set_id AS setId,
        op.set_name AS setName,
        op.rarity,
        op.inventory_price AS inventoryPrice,
        op.market_price AS marketPrice,
        op.artwork,
        'onepiece' AS collection,
        EXISTS(SELECT 1 FROM cards WHERE catalogId = CAST(oc.id AS TEXT) AND collection = 'onepiece') AS isOwned
      FROM onepiece_cards oc
      INNER JOIN onepiece_prints op ON oc.id = op.card_id
      $whereClause
      GROUP BY oc.id, op.card_set_id, op.rarity, COALESCE(op.artwork, 0)
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
        op.artwork
      FROM onepiece_prints op
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
        // onepiece_prints.set_id (e.g. "OP01")
        rows = await db.rawQuery('''
          SELECT DISTINCT LOWER(set_id) AS code
          FROM onepiece_prints
          WHERE set_id IS NOT NULL AND set_id != ''
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
  Future<dynamic> getCardtraderPrice({
    required String catalog,
    required String expansionCode,
    required String cardName,
    required String language,
    bool? firstEdition,
    String? rarity,
    String? collectorNumber,
  }) async {
    final db = await database;
    final nameLower = cardName.toLowerCase();

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

    // ── 1. expansion + name (all languages, priced or not) ──────────────────
    if (rows.isEmpty) {
      String w = 'catalog = ? AND expansion_code = ? AND LOWER(card_name_en) = ?';
      final a = <dynamic>[catalog, exp, nameLower];
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
    }

    // ── 2. Fallback: expansion + collector_number only ───────────────────────
    if (rows.isEmpty && (cnRaw != null || cnNorm != null)) {
      final digits = RegExp(r'\d+$').firstMatch(cnNorm ?? cnRaw ?? '')?.group(0) ?? '';
      final candidates = <String>{
        if (cnRaw  != null) cnRaw,
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

  /// Updates `cards.value` for every card that has a matching CardTrader price.
  ///
  /// Joins `cards` with the catalog table to resolve the English card name,
  /// then queries `cardtrader_prices` using expansion code + language + rarity.
  /// Returns the number of cards whose value was updated.
  Future<int> syncCollectionValuesFromCardtrader(String catalog) async {
    final db = await database;

    // ── Pre-fetch ALL priced CT rows for this catalog in ONE query ─────────
    // Sorted cheapest-first so putIfAbsent below keeps the best price per key.
    final ctRows = await db.rawQuery('''
      SELECT expansion_code,
             LOWER(card_name_en)     AS name_en,
             language,
             LOWER(rarity)           AS rarity,
             LOWER(collector_number) AS collector_number,
             min_price_nm_cents,
             min_price_any_cents
      FROM cardtrader_prices
      WHERE catalog = ? AND min_price_any_cents IS NOT NULL
      ORDER BY (min_price_nm_cents IS NULL), min_price_any_cents ASC
    ''', [catalog]);

    if (ctRows.isEmpty) return 0;

    // Build five in-memory lookup maps (cheapest row wins per key).
    final mapFull   = <String, Map<String, dynamic>>{};  // exp|name|lang|cn|rar
    final mapCn     = <String, Map<String, dynamic>>{};  // exp|name|lang|cn
    final mapRar    = <String, Map<String, dynamic>>{};  // exp|name|lang|rar
    final mapName   = <String, Map<String, dynamic>>{};  // exp|name|lang
    final mapCnOnly = <String, Map<String, dynamic>>{};  // exp|lang|cn (no name)

    for (final r in ctRows) {
      final exp  = r['expansion_code']   as String;
      final name = r['name_en']          as String;
      final lang = r['language']         as String;
      final cn   = r['collector_number'] as String;
      final rar  = r['rarity']           as String;
      mapFull  .putIfAbsent('$exp|$name|$lang|$cn|$rar', () => Map<String, dynamic>.from(r));
      mapCn    .putIfAbsent('$exp|$name|$lang|$cn',      () => Map<String, dynamic>.from(r));
      mapRar   .putIfAbsent('$exp|$name|$lang|$rar',     () => Map<String, dynamic>.from(r));
      mapName  .putIfAbsent('$exp|$name|$lang',          () => Map<String, dynamic>.from(r));
      mapCnOnly.putIfAbsent('$exp|$lang|$cn',            () => Map<String, dynamic>.from(r));
    }

    // In-memory price lookup with 5-level fallback chain (zero DB queries).
    Map<String, dynamic>? findPrice(
        String exp, String name, String lang, String cn, String rar) {
      if (cn.isNotEmpty && rar.isNotEmpty) {
        final r = mapFull['$exp|$name|$lang|$cn|$rar'];
        if (r != null) return r;
      }
      if (cn.isNotEmpty) {
        final r = mapCn['$exp|$name|$lang|$cn'];
        if (r != null) return r;
      }
      if (rar.isNotEmpty) {
        final r = mapRar['$exp|$name|$lang|$rar'];
        if (r != null) return r;
      }
      final r = mapName['$exp|$name|$lang'];
      if (r != null) return r;
      // Ultimate fallback: no name required (handles catalog name ≠ CT name_en)
      if (cn.isNotEmpty) return mapCnOnly['$exp|$lang|$cn'];
      return null;
    }

    // ── Pass 1: cards with catalogId → JOIN with catalog for English name ──
    String joinSql;
    switch (catalog) {
      case 'yugioh':
        joinSql = '''
          SELECT c.id AS card_id, yc.name AS name_en, c.serialNumber, c.rarity
          FROM cards c
          JOIN yugioh_cards yc ON yc.id = CAST(c.catalogId AS INTEGER)
          WHERE c.collection = 'yugioh'
            AND c.serialNumber IS NOT NULL AND c.serialNumber != ''
            AND c.catalogId IS NOT NULL
        ''';
      case 'pokemon':
        joinSql = '''
          SELECT c.id AS card_id, pk.name AS name_en, c.serialNumber, c.rarity
          FROM cards c
          JOIN pokemon_cards pk ON pk.id = CAST(c.catalogId AS INTEGER)
          WHERE c.collection = 'pokemon'
            AND c.serialNumber IS NOT NULL AND c.serialNumber != ''
            AND c.catalogId IS NOT NULL
        ''';
      case 'onepiece':
        joinSql = '''
          SELECT c.id AS card_id, oc.name AS name_en, c.serialNumber, c.rarity
          FROM cards c
          JOIN onepiece_cards oc ON oc.id = CAST(c.catalogId AS INTEGER)
          WHERE c.collection = 'onepiece'
            AND c.serialNumber IS NOT NULL AND c.serialNumber != ''
            AND c.catalogId IS NOT NULL
        ''';
      default:
        return 0;
    }

    final cards = await db.rawQuery(joinSql);

    int updated = 0;
    final batch = db.batch();
    final updatedCardIds = <int>{};

    for (final card in cards) {
      final cardId = card['card_id'] as int;
      final nameEn = (card['name_en'] as String? ?? '').trim();
      final sn     = (card['serialNumber'] as String? ?? '').trim();
      if (nameEn.isEmpty || sn.isEmpty) continue;

      final (exp, lang, cn) = _parseSerialForCt(catalog, sn);
      final rar = (card['rarity'] as String? ?? '').trim().toLowerCase();

      final priceRow = findPrice(exp, nameEn.toLowerCase(), lang, cn, rar);
      if (priceRow == null) continue;

      final priceCents = (priceRow['min_price_nm_cents'] as int?) ??
          (priceRow['min_price_any_cents'] as int?);
      if (priceCents == null || priceCents <= 0) continue;

      batch.rawUpdate(
        'UPDATE cards SET cardtrader_value = ? WHERE id = ?',
        [double.parse((priceCents / 100.0).toStringAsFixed(2)), cardId],
      );
      updatedCardIds.add(cardId);
      updated++;
    }

    // ── Pass 2: orphans (no catalogId) → match by collector_number only ───
    final orphans = await db.rawQuery('''
      SELECT id AS card_id, serialNumber
      FROM cards
      WHERE collection = ?
        AND serialNumber IS NOT NULL AND serialNumber != ''
        AND (catalogId IS NULL OR catalogId = '')
    ''', [catalog]);

    for (final card in orphans) {
      final cardId = card['card_id'] as int;
      if (updatedCardIds.contains(cardId)) continue;
      final sn = (card['serialNumber'] as String? ?? '').trim();
      if (sn.isEmpty || !sn.contains('-')) continue;

      final (exp, lang, cn) = _parseSerialForCt(catalog, sn);
      if (cn.isEmpty) continue;

      final priceRow = mapCnOnly['$exp|$lang|$cn'];
      if (priceRow == null) continue;

      final priceCents = (priceRow['min_price_nm_cents'] as int?) ??
          (priceRow['min_price_any_cents'] as int?);
      if (priceCents == null || priceCents <= 0) continue;

      batch.rawUpdate(
        'UPDATE cards SET cardtrader_value = ? WHERE id = ?',
        [double.parse((priceCents / 100.0).toStringAsFixed(2)), cardId],
      );
      updatedCardIds.add(cardId);
      updated++;
    }

    if (updated > 0) await batch.commit(noResult: true);
    return updated;
  }

  /// Extracts (expansionCode, language, collectorNumber) from a serial number.
  /// Used by both syncCollectionValuesFromCardtrader and applyCtPriceToCard.
  static (String, String, String) _parseSerialForCt(String catalog, String sn) {
    final exp = sn.split('-').first.toLowerCase();
    String lang = 'en';
    String cn   = '';

    if (catalog == 'yugioh') {
      final m = RegExp(r'-([A-Za-z]{2})[A-Za-z0-9]').firstMatch(sn);
      if (m != null) {
        final code = m.group(1)!.toLowerCase();
        lang = code == 'sp' ? 'es' : code;
      }
      final rawCn = sn.contains('-') ? sn.substring(sn.indexOf('-') + 1) : '';
      cn = rawCn.toLowerCase(); // e.g. "IT001" → "it001", matches CT stored value
    } else if (catalog == 'onepiece') {
      cn = sn.contains('-') ? sn.substring(sn.indexOf('-') + 1).toLowerCase() : '';
      // "001" or "SEC" → Japanese (no lang prefix); "EN001" → English
      final langMatch = RegExp(r'^([a-z]{2})\d').firstMatch(cn);
      lang = langMatch != null ? langMatch.group(1)! : 'ja';
    } else {
      // Pokemon and others: lowercase CN to match CT stored values
      cn = sn.contains('-') ? sn.substring(sn.indexOf('-') + 1).toLowerCase() : '';
    }

    return (exp, lang, cn);
  }

  /// Looks up the CT price for a single card from local cache and writes it
  /// to [cardId]'s cardtrader_value column. Called at insert time so new
  /// cards immediately show a price without waiting for a full sync.
  ///
  /// [catalogId] is used to resolve the English card name via a catalog JOIN,
  /// bypassing localized card names (e.g. Italian "Drago Bianco Occhi Blu"
  /// would never match CT's "Blue-Eyes White Dragon").
  Future<void> applyCtPriceToCard(
    int cardId,
    String catalog,
    String sn,
    String cardName,
    String rarity, {
    String? catalogId,
  }) async {
    if (sn.isEmpty) return;

    final (exp, lang, cn) = _parseSerialForCt(catalog, sn);
    final rarLower = rarity.trim().toLowerCase();
    final db = await database;

    // ── Resolve English name via catalogId (skips localization issues) ──
    String? nameEn;
    final idInt = int.tryParse(catalogId ?? '');
    if (idInt != null) {
      final table = switch (catalog) {
        'yugioh'   => 'yugioh_cards',
        'pokemon'  => 'pokemon_cards',
        'onepiece' => 'onepiece_cards',
        _ => null,
      };
      if (table != null) {
        final rows = await db.query(table,
            columns: ['name'], where: 'id = ?', whereArgs: [idInt]);
        if (rows.isNotEmpty) nameEn = rows.first['name'] as String?;
      }
    }
    // Fall back to the card's display name if catalog lookup failed
    final nameLower = (nameEn ?? cardName).trim().toLowerCase();

    // ── 1. Name-based lookup (most precise) ─────────────────────────────
    Map<String, dynamic>? row;
    final nameResult = await getCardtraderPrice(
      catalog: catalog,
      expansionCode: exp,
      cardName: nameLower,
      language: lang,
      rarity: rarLower.isNotEmpty ? rarLower : null,
      collectorNumber: cn.isNotEmpty ? cn : null,
    );
    if (nameResult != null) row = nameResult as Map<String, dynamic>;

    // ── 2. Collector-number fallback (handles name mismatches) ──────────
    if (row == null && cn.isNotEmpty) {
      final rows = await db.query(
        'cardtrader_prices',
        where: 'catalog = ? AND expansion_code = ? AND language = ?'
            ' AND LOWER(collector_number) = ? AND min_price_any_cents IS NOT NULL',
        whereArgs: [catalog, exp, lang, cn.toLowerCase()],
        orderBy: '(min_price_nm_cents IS NULL), min_price_any_cents ASC',
        limit: 1,
      );
      if (rows.isNotEmpty) row = rows.first;
    }

    if (row == null) return;

    final priceCents = (row['min_price_nm_cents'] as int?) ??
        (row['min_price_any_cents'] as int?);
    if (priceCents == null || priceCents <= 0) return;

    await db.rawUpdate(
      'UPDATE cards SET cardtrader_value = ? WHERE id = ?',
      [double.parse((priceCents / 100.0).toStringAsFixed(2)), cardId],
    );
  }

  /// Aggiorna i prezzi nelle tabelle del catalogo (yugioh_prints, pokemon_prints,
  /// onepiece_prints) leggendo i prezzi CT già in cache locale.
  /// Questo rende i prezzi CT visibili a TUTTE le carte del catalogo,
  /// non solo a quelle possedute.
  ///
  /// Returns the total number of print rows updated.
  Future<int> syncCatalogPricesFromCardtrader(String catalog) async {
    final db = await database;

    // Wrap all UPDATE statements in a single transaction so the write lock
    // is acquired once and released once — no interleaving with other reads.
    return db.transaction((txn) async {
      int total = 0;

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
            final col  = entry.value;
            final n = await txn.rawUpdate('''
              UPDATE yugioh_prints
              SET $col = (
                SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
                FROM cardtrader_prices cp
                JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
                WHERE cp.catalog = 'yugioh'
                  AND cp.expansion_code = LOWER(yugioh_prints.set_id)
                  AND LOWER(cp.card_name_en) = LOWER(yc.name)
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
                ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
                LIMIT 1
              )
              WHERE yugioh_prints.set_id IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM cardtrader_prices cp
                  JOIN yugioh_cards yc ON yc.id = yugioh_prints.card_id
                  WHERE cp.catalog = 'yugioh'
                    AND cp.expansion_code = LOWER(yugioh_prints.set_id)
                    AND LOWER(cp.card_name_en) = LOWER(yc.name)
                    AND cp.language = ?
                    AND cp.min_price_any_cents IS NOT NULL
                )
            ''', [lang, lang]);
            total += n;
          }

        case 'pokemon':
          const pokeLangCols = <String, String>{
            'en': 'set_price',
            'it': 'set_price_it',
            'fr': 'set_price_fr',
            'de': 'set_price_de',
            'pt': 'set_price_pt',
          };
          for (final entry in pokeLangCols.entries) {
            final lang = entry.key;
            final col  = entry.value;
            final n = await txn.rawUpdate('''
              UPDATE pokemon_prints
              SET $col = (
                SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
                FROM cardtrader_prices cp
                JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
                WHERE cp.catalog = 'pokemon'
                  AND cp.expansion_code = LOWER(pc.set_id)
                  AND LOWER(cp.card_name_en) = LOWER(pc.name)
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
                ORDER BY (cp.min_price_nm_cents IS NULL), cp.min_price_any_cents ASC
                LIMIT 1
              )
              WHERE EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN pokemon_cards pc ON pc.id = pokemon_prints.card_id
                WHERE cp.catalog = 'pokemon'
                  AND cp.expansion_code = LOWER(pc.set_id)
                  AND LOWER(cp.card_name_en) = LOWER(pc.name)
                  AND cp.language = ?
                  AND cp.min_price_any_cents IS NOT NULL
              )
            ''', [lang, lang]);
            total += n;
          }

        case 'onepiece':
          final n = await txn.rawUpdate('''
            UPDATE onepiece_prints
            SET market_price = (
              SELECT CAST(cp.min_price_any_cents AS REAL) / 100.0
              FROM cardtrader_prices cp
              JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
              WHERE cp.catalog = 'onepiece'
                AND cp.expansion_code = LOWER(onepiece_prints.set_id)
                AND LOWER(cp.card_name_en) = LOWER(oc.name)
                AND cp.min_price_any_cents IS NOT NULL
              ORDER BY (cp.language != 'en'), (cp.min_price_nm_cents IS NULL),
                       cp.min_price_any_cents ASC
              LIMIT 1
            )
            WHERE onepiece_prints.set_id IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM cardtrader_prices cp
                JOIN onepiece_cards oc ON oc.id = onepiece_prints.card_id
                WHERE cp.catalog = 'onepiece'
                  AND cp.expansion_code = LOWER(onepiece_prints.set_id)
                  AND LOWER(cp.card_name_en) = LOWER(oc.name)
                  AND cp.min_price_any_cents IS NOT NULL
              )
          ''');
          total += n;
      }

      return total;
    });
  }
}
