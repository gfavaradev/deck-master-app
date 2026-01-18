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

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    // String path = join(await getDatabasesPath(), 'cards_database_v9.db');
    String path = inMemoryDatabasePath; // Usiamo database in memoria per i test
    
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Ensure essential indices exist (for development/existing dbs)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_catalog_card_sets_cardId ON catalog_card_sets (cardId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_catalog_cards_collection ON catalog_cards (collection)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_catalog_card_sets_lookup ON catalog_card_sets (cardId, setCode)');

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
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE albums(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        collection TEXT,
        maxCapacity INTEGER
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
        FOREIGN KEY (albumId) REFERENCES albums (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE catalog_cards(
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        frameType TEXT,
        description TEXT,
        atk INTEGER,
        def INTEGER,
        level INTEGER,
        race TEXT,
        attribute TEXT,
        archetype TEXT,
        ygoprodeck_url TEXT,
        collection TEXT,
        imageUrl TEXT,
        imageUrlSmall TEXT,
        prices TEXT,
        isOwned INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE catalog_card_sets(
        cardId TEXT,
        setName TEXT,
        setCode TEXT,
        setRarity TEXT,
        setPrice REAL,
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
        collection TEXT
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
  }

  Future<void> clearAllCardData() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('cards');
      await txn.delete('catalog_cards');
      await txn.delete('catalog_card_sets');
      await txn.delete('deck_cards');
    });
  }

  // --- Album Methods ---
  Future<int> insertAlbum(AlbumModel album) async {
    Database db = await database;
    return await db.insert('albums', album.toMap());
  }

  Future<List<AlbumModel>> getAlbumsByCollection(String collection) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT a.*, (SELECT COALESCE(SUM(c.quantity), 0) FROM cards c WHERE c.albumId = a.id) as currentCount
      FROM albums a
      WHERE a.collection = ?
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
    // Potremmo voler cancellare anche le carte associate o settare albumId a null
    return await db.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  // --- Card Methods ---
  Future<int> insertCard(CardModel card) async {
    Database db = await database;
    return await db.transaction((txn) async {
      int id = await txn.insert('cards', card.toMap());
      
      if (card.catalogId != null) {
        // Update catalog flags
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

  Future<List<CardModel>> getCardsWithCatalog(String collection) async {
    Database db = await database;
    
    // Vista generale: Mostriamo tutte le carte del catalogo con i loro flag posseduti
    // o carte custom non presenti nel catalogo
    
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        NULL as id,
        c.id as catalogId,
        c.name,
        c.type,
        c.description,
        c.collection,
        c.imageUrl,
        c.isOwned,
        (SELECT SUM(quantity) FROM catalog_card_sets WHERE cardId = c.id) as quantity,
        0.0 as value,
        '' as rarity,
        '' as serialNumber,
        -1 as albumId
      FROM catalog_cards c
      WHERE c.collection = ?
    ''', [collection]);

    // Carichiamo anche le carte effettivamente possedute per avere i dettagli degli album
    final List<Map<String, dynamic>> ownedResults = await db.rawQuery('''
      SELECT 
        u.id,
        u.catalogId,
        COALESCE(c.name, u.name) as name,
        COALESCE(c.type, u.type) as type,
        COALESCE(c.description, u.description) as description,
        COALESCE(c.collection, u.collection) as collection,
        COALESCE(c.imageUrl, u.imageUrl) as imageUrl,
        u.serialNumber,
        u.albumId,
        u.rarity,
        u.quantity,
        u.value
      FROM cards u
      LEFT JOIN catalog_cards c ON u.catalogId = c.id
      WHERE u.collection = ?
    ''', [collection]);

    // Uniamo i dati: Il catalogo serve da base per la ricerca, 
    // ma mostriamo le istanze reali se possedute
    Map<String, CardModel> merged = {};

    // 1. Aggiungiamo tutto il catalogo come "non posseduto" (o con quantità totale)
    for (var row in results) {
      final key = row['name'].toString().toLowerCase();
      merged[key] = CardModel.fromMap(row);
    }

    // 2. Sovrascriviamo/Aggiungiamo le istanze reali
    for (var row in ownedResults) {
      final name = row['name'].toString().toLowerCase();
      final serial = row['serialNumber'].toString().toLowerCase();
      final key = "${name}_$serial";

      if (merged.containsKey(key) && merged[key]!.id == null) {
        // Se c'è solo il segnaposto del catalogo, lo sostituiamo con l'istanza reale
        merged[key] = CardModel.fromMap(row);
      } else if (merged.containsKey(key)) {
        // Se c'è già un'istanza reale (magari in un altro album), sommiamo
        final existing = merged[key]!;
        merged[key] = existing.copyWith(
          quantity: existing.quantity + (row['quantity'] as int),
        );
      } else {
        // Carta custom o non trovata nel catalogo base (anche se JOIN garantisce che ci sia)
        merged[key] = CardModel.fromMap(row);
      }
    }

    return merged.values.toList();
  }

  Future<List<CardModel>> getCardsByCollection(String collection) async {
    Database db = await database;
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

  Future<List<CardModel>> findOwnedInstances(String collection, String name, String serialNumber) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT u.*, 
             COALESCE(c.name, u.name) as name, 
             COALESCE(c.type, u.type) as type, 
             COALESCE(c.description, u.description) as description, 
             COALESCE(c.collection, u.collection) as collection, 
             COALESCE(c.imageUrl, u.imageUrl) as imageUrl
      FROM cards u
      LEFT JOIN catalog_cards c ON u.catalogId = c.id
      WHERE u.collection = ? AND (c.name = ? OR u.name = ?) AND u.serialNumber = ?
    ''', [collection, name, name, serialNumber]);
    return List.generate(maps.length, (i) => CardModel.fromMap(maps[i]));
  }

  Future<int> deleteCard(int id) async {
    Database db = await database;
    
    return await db.transaction((txn) async {
      // Recuperiamo i dati prima di eliminare per aggiornare i flag
      final List<Map<String, dynamic>> cards = await txn.query('cards', where: 'id = ?', whereArgs: [id]);
      if (cards.isNotEmpty) {
        final card = cards.first;
        final String? catalogId = card['catalogId'] as String?;
        final String serialNumber = card['serialNumber'] as String;
        final int quantity = card['quantity'] as int;

        if (catalogId != null) {
          // Decrementiamo nel catalogo
          await txn.execute('''
            UPDATE catalog_card_sets 
            SET quantity = quantity - ? 
            WHERE cardId = ? AND setCode = ?
          ''', [quantity, catalogId, serialNumber]);

          // Controlliamo se è ancora posseduta da qualche parte
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
      // Gestione complessa del delta quantità per il catalogo
      final List<Map<String, dynamic>> oldCards = await txn.query('cards', where: 'id = ?', whereArgs: [card.id]);
      if (oldCards.isNotEmpty && card.catalogId != null) {
        final int oldQty = oldCards.first['quantity'] as int;
        final int delta = card.quantity - oldQty;
        
        await txn.execute('''
          UPDATE catalog_card_sets 
          SET quantity = quantity + ? 
          WHERE cardId = ? AND setCode = ?
        ''', [delta, card.catalogId, card.serialNumber]);
        
        // Calcoliamo il totale posseduto dopo l'aggiornamento
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

  // --- Catalog Methods ---
  Future<void> insertCatalogCards(List<Map<String, dynamic>> cards, {Function(double)? onProgress}) async {
    Database db = await database;
    
    // Use a single transaction for the whole operation to prevent database locks
    // and drastically improve performance.
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
          
          // Use INSERT OR IGNORE then UPDATE to avoid resetting the 'isOwned' flag
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
                'setPrice': double.tryParse(set['set_price'].toString()) ?? 0.0,
              };
              
              // Update existing set to preserve 'quantity'
              batch.update('catalog_card_sets', setData, 
                  where: 'cardId = ? AND setCode = ?', 
                  whereArgs: [cardData['id'], setCode]);
              
              // Insert if missing
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
        SELECT c.*, (SELECT setCode FROM catalog_card_sets WHERE cardId = c.id LIMIT 1) as setCode
        FROM catalog_cards c
        WHERE c.collection = ?
      ''', [collection]);
    }
    
    // Search by name in catalog_cards or by setCode in catalog_card_sets
    return await db.rawQuery('''
      SELECT DISTINCT c.*, s.setCode 
      FROM catalog_cards c
      LEFT JOIN catalog_card_sets s ON c.id = s.cardId
      WHERE c.collection = ? AND (c.name LIKE ? OR s.setCode LIKE ?)
      GROUP BY c.id
    ''', [collection, '%$query%', '%$query%']);
  }

  Future<List<Map<String, dynamic>>> getCardSets(String cardId) async {
    Database db = await database;
    return await db.query('catalog_card_sets', where: 'cardId = ?', whereArgs: [cardId]);
  }

  Future<int> getCatalogCount(String collection) async {
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM catalog_cards WHERE collection = ?', [collection]);
    return result.first['count'] as int? ?? 0;
  }

  Future<Map<String, dynamic>> getGlobalStats() async {
    Database db = await database;
    
    final totalCards = await db.rawQuery('SELECT SUM(quantity) as total FROM cards');
    final uniqueCards = await db.rawQuery('SELECT COUNT(DISTINCT catalogId) as total FROM cards');
    final totalValue = await db.rawQuery('SELECT SUM(value * quantity) as total FROM cards');
    final collections = await db.rawQuery('SELECT COUNT(*) as total FROM collections WHERE isUnlocked = 1');
    
    return {
      'totalCards': (totalCards.first['total'] as num?)?.toInt() ?? 0,
      'uniqueCards': uniqueCards.first['total'] as int? ?? 0,
      'totalValue': (totalValue.first['total'] as num?)?.toDouble() ?? 0.0,
      'unlockedCollections': collections.first['total'] as int? ?? 0,
    };
  }

  // --- Collection Methods ---
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

  // --- Deck Methods ---
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
    await db.insert('deck_cards', {
      'deckId': deckId,
      'cardId': cardId,
      'quantity': quantity,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> removeCardFromDeck(int deckId, int cardId) async {
    Database db = await database;
    await db.delete('deck_cards', where: 'deckId = ? AND cardId = ?', whereArgs: [deckId, cardId]);
  }
}
