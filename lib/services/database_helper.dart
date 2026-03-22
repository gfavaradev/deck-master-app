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

  static const List<String> _validLanguages = ['EN', 'IT', 'FR', 'DE', 'PT'];

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
      version: 13,
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

    await db.insert('collections', {'id': 'yugioh', 'name': 'Yu-Gi-Oh!', 'isUnlocked': 0});
    await db.insert('collections', {'id': 'pokemon', 'name': 'Pokémon', 'isUnlocked': 0});
    await db.insert('collections', {'id': 'magic', 'name': 'Magic: The Gathering', 'isUnlocked': 0});
    await db.insert('collections', {'id': 'onepiece', 'name': 'One Piece', 'isUnlocked': 0});

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
      int id = await txn.insert('cards', card.toMap());

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
                 (SELECT set_price FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber)
                  LIMIT 1),
                 u.value
               ) as value,
               COALESCE(
                 (SELECT artwork FROM yugioh_prints
                  WHERE card_id = CAST(u.catalogId AS INTEGER)
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber)
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
               COALESCE(op.market_price, u.value) as value,
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
                 (SELECT set_price FROM pokemon_prints
                  WHERE card_id = pc.id
                    AND (set_code = u.serialNumber OR set_code_it = u.serialNumber
                      OR set_code_fr = u.serialNumber OR set_code_de = u.serialNumber
                      OR set_code_pt = u.serialNumber)
                  LIMIT 1),
                 u.value
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
                      OR set_code_pt = u.serialNumber)
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
        CASE
          WHEN c.collection = 'yugioh' THEN
            COALESCE(
              (SELECT set_price FROM yugioh_prints
               WHERE card_id = CAST(c.catalogId AS INTEGER)
                 AND (set_code = c.serialNumber OR set_code_it = c.serialNumber
                   OR set_code_fr = c.serialNumber OR set_code_de = c.serialNumber
                   OR set_code_pt = c.serialNumber)
               LIMIT 1),
              c.value
            )
          WHEN c.collection = 'onepiece' THEN
            COALESCE(
              (SELECT market_price FROM onepiece_prints
               WHERE card_id = CAST(c.catalogId AS INTEGER)
                 AND card_set_id = c.serialNumber
               LIMIT 1),
              c.value
            )
          WHEN c.collection = 'pokemon' THEN
            COALESCE(
              (SELECT set_price FROM pokemon_prints
               WHERE card_id = CAST(c.catalogId AS INTEGER)
                 AND (set_code = c.serialNumber OR set_code_it = c.serialNumber
                   OR set_code_fr = c.serialNumber OR set_code_de = c.serialNumber
                   OR set_code_pt = c.serialNumber)
               LIMIT 1),
              c.value
            )
          ELSE c.value
        END * c.quantity
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
             SUM(value * quantity) as totalValue
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
             SUM(value * quantity) as totalValue
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
               OR p.set_code_pt = cards.serialNumber)
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
            for (var p in prints) {
              final cardId = cardData['id'];
              final setCode = p['set_code'] ?? '';
              final rarity = p['rarity'];

              // Insert print
              batch.rawInsert('''
                INSERT OR REPLACE INTO yugioh_prints (
                  card_id, set_code, set_name, rarity, rarity_code, set_price, artwork,
                  set_name_it, set_code_it, rarity_it, rarity_code_it, set_price_it,
                  set_name_fr, set_code_fr, rarity_fr, rarity_code_fr, set_price_fr,
                  set_name_de, set_code_de, rarity_de, rarity_code_de, set_price_de,
                  set_name_pt, set_code_pt, rarity_pt, rarity_code_pt, set_price_pt,
                  set_name_sp, set_code_sp, rarity_sp, rarity_code_sp, set_price_sp,
                  created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      // No search: show all cards (no language filter)
      whereClause = '';
    } else {
      final q = '%$query%';
      // Search by name (localized or EN) + all set codes (all languages)
      if (hasLang) {
        whereClause = '''WHERE (
          $nameCol LIKE ?
          OR yc.name LIKE ?
          OR yp.set_code LIKE ?
          OR yp.set_code_it LIKE ?
          OR yp.set_code_fr LIKE ?
          OR yp.set_code_de LIKE ?
          OR yp.set_code_pt LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q, q];
      } else {
        // EN: search name + all set codes
        whereClause = '''WHERE (
          yc.name LIKE ?
          OR yp.set_code LIKE ?
          OR yp.set_code_it LIKE ?
          OR yp.set_code_fr LIKE ?
          OR yp.set_code_de LIKE ?
          OR yp.set_code_pt LIKE ?
        )''';
        whereArgs = [q, q, q, q, q, q];
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
      whereClause = '';
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
  Future<List<Map<String, dynamic>>> getSetStats(String collection) async {
    Database db = await database;
    if (collection == 'yugioh') {
      // serialNumber memorizza il codice localizzato (EN/IT/FR/DE/PT) → confronta con tutte le colonne
      return db.rawQuery('''
        SELECT COALESCE(p.set_name, '?') as setName,
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
            OR c.serialNumber = p.set_code_pt)
        WHERE p.set_name IS NOT NULL
        GROUP BY p.set_name
        ORDER BY p.set_name
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
      return db.rawQuery('''
        SELECT COALESCE(pc.set_name, pc.set_id, '?') as setName,
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
        ORDER BY pc.set_name
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

  /// Dettaglio carte in un set specifico con stato di possesso.
  /// [setIdentifier]: set_name (YGO), set_id (OP), setName (generico)
  /// Ritorna: [{id, name, imageUrl, serialNumber, rarity, isOwned}]
  Future<List<Map<String, dynamic>>> getSetDetail(String collection, String setIdentifier) async {
    Database db = await database;
    if (collection == 'yugioh') {
      return db.rawQuery('''
        SELECT yc.id, yc.name, COALESCE(p.artwork, yc.image_url) as imageUrl,
               p.set_code as serialNumber, p.rarity,
               CASE WHEN c.id IS NOT NULL THEN 1 ELSE 0 END as isOwned
        FROM yugioh_prints p
        JOIN yugioh_cards yc ON yc.id = p.card_id
        LEFT JOIN cards c ON CAST(c.catalogId AS INTEGER) = p.card_id
          AND c.collection = 'yugioh'
          AND (c.serialNumber = p.set_code
            OR c.serialNumber = p.set_code_it
            OR c.serialNumber = p.set_code_fr
            OR c.serialNumber = p.set_code_de
            OR c.serialNumber = p.set_code_pt)
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
      return db.rawQuery('''
        SELECT pc.id, pc.name, pp.artwork as imageUrl,
               pp.set_code as serialNumber, pp.rarity,
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
            OR c.serialNumber = p.set_code_pt)
        WHERE p.set_name IN (
          SELECT set_name FROM yugioh_prints
          WHERE set_code = ? OR set_code_it = ? OR set_code_fr = ? OR set_code_de = ? OR set_code_pt = ?
        )
        GROUP BY p.set_name
        HAVING ownedCards >= totalCards AND totalCards > 0
      ''', [serialNumber, serialNumber, serialNumber, serialNumber, serialNumber]);
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
    final db = await database;
    await db.rawDelete('''
      DELETE FROM cards WHERE firestoreId IS NULL
        AND id NOT IN (
          SELECT local_id FROM pending_sync WHERE table_name = 'cards'
        )
    ''');
    await db.rawDelete('''
      DELETE FROM albums WHERE firestoreId IS NULL
        AND id NOT IN (
          SELECT local_id FROM pending_sync WHERE table_name = 'albums'
        )
    ''');
  }

  /// Delete albums that have a firestoreId but it's NOT in [keepIds].
  /// Albums without a firestoreId (offline-created, not yet synced) are untouched.
  Future<void> deleteAlbumsNotInFirestoreIds(List<String> keepIds) async {
    if (keepIds.isEmpty) {
      // Delete all albums that have a firestoreId
      final db = await database;
      await db.delete('albums', where: 'firestoreId IS NOT NULL');
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
      final db = await database;
      await db.delete('cards', where: 'firestoreId IS NOT NULL');
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

          for (final p in prints) {
            final print = Map<String, dynamic>.from(p as Map);
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
                'artwork': print['artwork'],
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
}
