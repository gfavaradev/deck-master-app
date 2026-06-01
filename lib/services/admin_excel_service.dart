import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'database_helper.dart';

class ImportPreview {
  final String collection;
  final List<Map<String, dynamic>> changedCards;
  final int totalScanned;

  const ImportPreview({
    required this.collection,
    required this.changedCards,
    required this.totalScanned,
  });

  int get totalChanged => changedCards.length;
  int get unchanged => totalScanned - totalChanged;
}

class ImportResult {
  final int updatedCards;
  final int affectedChunks;

  const ImportResult({required this.updatedCards, required this.affectedChunks});
}

/// Manages Excel export and import for admin catalog operations.
///
/// Export reads from the local SQLite cache (offline, no network).
/// Import preview diffs Excel vs SQLite.
/// Apply import writes changed cards back to Firestore (chunk-level surgical update).
class AdminExcelService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _db = DatabaseHelper();

  static const _sheetName = 'Carte';
  static const _chunkFetchBatchSize = 10;

  // ── Column definitions ──────────────────────────────────────────────────────

  // YuGiOh ─────────────────────────────────────────────────────────────────────
  // Cols 0-20 kept identical to old format → import stays compatible.
  static const _yugiohHeaders = [
    'id', 'name', 'name_it', 'name_fr', 'name_de', 'name_pt', 'name_sp',
    'description', 'description_it', 'description_fr', 'description_de',
    'description_pt', 'description_sp',
    'type', 'race', 'archetype', 'atk', 'def', 'level', 'attribute', 'image_url',
    'human_readable_type', 'frame_type', 'scale', 'linkval', 'linkmarkers', 'ygoprodeck_url',
  ];

  static const _yugiohEditableFields = [
    'name', 'name_it', 'name_fr', 'name_de', 'name_pt', 'name_sp',
    'description', 'description_it', 'description_fr', 'description_de',
    'description_pt', 'description_sp',
    'type', 'race', 'archetype', 'atk', 'def', 'level', 'attribute',
  ];

  static const _yugiohStampeHeaders = [
    'print_id', 'card_id', 'card_name',
    'set_code', 'set_name', 'rarity', 'rarity_code', 'set_price', 'artwork', 'set_id',
    'set_code_it', 'set_name_it', 'rarity_it', 'rarity_code_it', 'set_price_it',
    'set_code_fr', 'set_name_fr', 'rarity_fr', 'rarity_code_fr', 'set_price_fr',
    'set_code_de', 'set_name_de', 'rarity_de', 'rarity_code_de', 'set_price_de',
    'set_code_pt', 'set_name_pt', 'rarity_pt', 'rarity_code_pt', 'set_price_pt',
    'set_code_sp', 'set_name_sp', 'rarity_sp', 'rarity_code_sp', 'set_price_sp',
    'ct_listing_count', 'ct_synced_at',
  ];

  // Pokemon ─────────────────────────────────────────────────────────────────────
  // Cols 0-10 kept identical → import stays compatible.
  static const _pokemonHeaders = [
    'id', 'api_id', 'name', 'name_it', 'name_fr', 'name_de', 'name_pt',
    'supertype', 'hp', 'types', 'rarity', 'set_id', 'set_name',
    'set_series', 'number', 'image_url',
  ];

  static const _pokemonEditableFields = [
    'name', 'name_it', 'name_fr', 'name_de', 'name_pt',
    'supertype', 'hp', 'types', 'rarity',
  ];

  static const _pokemonStampeHeaders = [
    'print_id', 'card_id', 'card_name', 'api_id',
    'set_code', 'set_name', 'rarity', 'set_price',
    'set_code_it', 'set_name_it', 'rarity_it', 'set_price_it',
    'set_code_fr', 'set_name_fr', 'rarity_fr', 'set_price_fr',
    'set_code_de', 'set_name_de', 'rarity_de', 'set_price_de',
    'set_code_pt', 'set_name_pt', 'rarity_pt', 'set_price_pt',
    'set_code_es', 'set_name_es', 'rarity_es', 'set_price_es',
    'ct_listing_count', 'ct_synced_at',
  ];

  // One Piece ───────────────────────────────────────────────────────────────────
  // Cols 0-9 kept identical → import stays compatible.
  static const _onepieceHeaders = [
    'id', 'name', 'card_type', 'color', 'cost', 'power',
    'life', 'counter_amount', 'sub_types', 'card_text', 'image_url', 'attribute',
  ];

  static const _onepieceEditableFields = [
    'name', 'card_type', 'color', 'cost', 'power',
    'life', 'counter_amount', 'sub_types', 'card_text',
  ];

  static const _onepieceStampeHeaders = [
    'print_id', 'card_id', 'card_name', 'card_set_id', 'set_id', 'set_name', 'rarity',
    'market_price', 'market_price_en', 'market_price_fr', 'market_price_ko', 'market_price_zh',
    'inventory_price',
    'set_name_jp', 'set_name_fr', 'set_name_ko', 'set_name_zh',
    'rarity_jp', 'rarity_fr', 'rarity_ko', 'rarity_zh',
    'ct_listing_count', 'ct_synced_at',
  ];

  // Magic ───────────────────────────────────────────────────────────────────────
  static const _magicHeaders = [
    'api_id', 'name', 'mana_cost', 'cmc', 'type_line', 'oracle_text',
    'power', 'toughness', 'colors', 'rarity',
    'set_code', 'set_name', 'collector_number', 'image_url', 'price_eur',
  ];

  static const _magicEditableFields = [
    'name', 'mana_cost', 'type_line', 'oracle_text',
    'power', 'toughness', 'colors', 'rarity', 'price_eur',
  ];

  // Generic v36 collections ─────────────────────────────────────────────────────
  static const _genericHeaders = [
    'api_id', 'name', 'card_type', 'subtype', 'rarity', 'cost', 'power', 'defense',
    'effect', 'set_code', 'set_name',
    'name_it', 'effect_it', 'name_fr', 'effect_fr', 'name_de', 'effect_de', 'name_pt', 'effect_pt',
  ];

  static const _genericEditableFields = [
    'name', 'card_type', 'subtype', 'rarity', 'effect',
    'name_it', 'effect_it', 'name_fr', 'effect_fr', 'name_de', 'effect_de', 'name_pt', 'effect_pt',
  ];

  // ── Export ──────────────────────────────────────────────────────────────────

  /// Reads the local SQLite DB and returns a multi-sheet Excel workbook as bytes.
  /// Sheet "Carte": complete card data, column-order compatible with import.
  /// Sheet "Stampe": all prints/sets with per-language prices (YGO / Pokémon / One Piece).
  Future<Uint8List> exportToExcel(
    String collection, {
    void Function(String status, double? progress)? onProgress,
  }) async {
    onProgress?.call('Lettura database locale...', null);
    final db = await _db.database;
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    switch (collection) {
      case 'yugioh':
        await _exportYugioh(db, excel, onProgress);
      case 'pokemon':
        await _exportPokemon(db, excel, onProgress);
      case 'onepiece':
        await _exportOnePiece(db, excel, onProgress);
      case 'magic':
        await _exportMagic(db, excel, onProgress);
      default:
        final prefix = DatabaseHelper.genericTablePrefix(collection);
        if (prefix == null) throw Exception('Collezione non supportata: $collection');
        await _exportGeneric(db, excel, prefix, collection, onProgress);
    }

    onProgress?.call('Generazione file Excel...', null);
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Errore durante la generazione del file Excel');
    return Uint8List.fromList(bytes);
  }

  // ── Yu-Gi-Oh! ───────────────────────────────────────────────────────────────

  Future<void> _exportYugioh(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final carteSheet = excel[_sheetName];
    _writeHeader(carteSheet, _yugiohHeaders);
    final rows = await db.rawQuery('''
      SELECT id, name, name_it, name_fr, name_de, name_pt, name_sp,
             description, description_it, description_fr, description_de,
             description_pt, description_sp,
             type, race, archetype, atk, def, level, attribute, image_url,
             human_readable_type, frame_type, scale, linkval, linkmarkers, ygoprodeck_url
      FROM yugioh_cards ORDER BY id
    ''') as List<Map<String, dynamic>>;

    if (rows.isEmpty) throw Exception('Nessuna carta Yu-Gi-Oh! nel database locale. Scarica prima il catalogo.');

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      carteSheet.appendRow([
        _int(r['id']),
        _txt(r['name']),     _txt(r['name_it']),   _txt(r['name_fr']),
        _txt(r['name_de']),  _txt(r['name_pt']),   _txt(r['name_sp']),
        _txt(r['description']),      _txt(r['description_it']),
        _txt(r['description_fr']),   _txt(r['description_de']),
        _txt(r['description_pt']),   _txt(r['description_sp']),
        _txt(r['type']),     _txt(r['race']),    _txt(r['archetype']),
        _int(r['atk']),      _int(r['def']),     _int(r['level']),
        _txt(r['attribute']), _txt(r['image_url']),
        _txt(r['human_readable_type']), _txt(r['frame_type']),
        _int(r['scale']),    _int(r['linkval']),  _txt(r['linkmarkers']),
        _txt(r['ygoprodeck_url']),
      ]);
      if (i % 1000 == 0) onProgress?.call('Carte: ${i + 1} / ${rows.length}', (i + 1) / rows.length * 0.5);
    }

    onProgress?.call('Lettura stampe e prezzi...', 0.5);
    try {
      await _exportYugiohStampe(db, excel, onProgress);
    } catch (_) {
      // yugioh_prints not available (older DB) — skip silently
    }
  }

  Future<void> _exportYugiohStampe(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final sheet = excel['Stampe'];
    _writeHeader(sheet, _yugiohStampeHeaders);
    final rows = await db.rawQuery('''
      SELECT p.id as print_id, p.card_id, c.name as card_name,
             p.set_code, p.set_name, p.rarity, p.rarity_code, p.set_price, p.artwork, p.set_id,
             p.set_code_it, p.set_name_it, p.rarity_it, p.rarity_code_it, p.set_price_it,
             p.set_code_fr, p.set_name_fr, p.rarity_fr, p.rarity_code_fr, p.set_price_fr,
             p.set_code_de, p.set_name_de, p.rarity_de, p.rarity_code_de, p.set_price_de,
             p.set_code_pt, p.set_name_pt, p.rarity_pt, p.rarity_code_pt, p.set_price_pt,
             p.set_code_sp, p.set_name_sp, p.rarity_sp, p.rarity_code_sp, p.set_price_sp,
             p.ct_listing_count, p.ct_synced_at
      FROM yugioh_prints p
      LEFT JOIN yugioh_cards c ON p.card_id = c.id
      ORDER BY c.name, p.set_code
    ''') as List<Map<String, dynamic>>;

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      sheet.appendRow([
        _int(r['print_id']),    _int(r['card_id']),     _txt(r['card_name']),
        _txt(r['set_code']),    _txt(r['set_name']),    _txt(r['rarity']),
        _txt(r['rarity_code']), _dbl(r['set_price']),   _txt(r['artwork']),   _txt(r['set_id']),
        _txt(r['set_code_it']), _txt(r['set_name_it']), _txt(r['rarity_it']), _txt(r['rarity_code_it']), _dbl(r['set_price_it']),
        _txt(r['set_code_fr']), _txt(r['set_name_fr']), _txt(r['rarity_fr']), _txt(r['rarity_code_fr']), _dbl(r['set_price_fr']),
        _txt(r['set_code_de']), _txt(r['set_name_de']), _txt(r['rarity_de']), _txt(r['rarity_code_de']), _dbl(r['set_price_de']),
        _txt(r['set_code_pt']), _txt(r['set_name_pt']), _txt(r['rarity_pt']), _txt(r['rarity_code_pt']), _dbl(r['set_price_pt']),
        _txt(r['set_code_sp']), _txt(r['set_name_sp']), _txt(r['rarity_sp']), _txt(r['rarity_code_sp']), _dbl(r['set_price_sp']),
        _int(r['ct_listing_count']), _txt(r['ct_synced_at']),
      ]);
      if (i % 1000 == 0) onProgress?.call('Stampe: ${i + 1} / ${rows.length}', 0.5 + (i + 1) / rows.length * 0.5);
    }
  }

  // ── Pokémon ──────────────────────────────────────────────────────────────────

  Future<void> _exportPokemon(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final carteSheet = excel[_sheetName];
    _writeHeader(carteSheet, _pokemonHeaders);
    final rows = await db.rawQuery('''
      SELECT id, api_id, name, name_it, name_fr, name_de, name_pt,
             supertype, hp, types, rarity, set_id, set_name,
             set_series, number, image_url
      FROM pokemon_cards ORDER BY id
    ''') as List<Map<String, dynamic>>;

    if (rows.isEmpty) throw Exception('Nessuna carta Pokémon nel database locale. Scarica prima il catalogo.');

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      carteSheet.appendRow([
        _int(r['id']),         _txt(r['api_id']),   _txt(r['name']),
        _txt(r['name_it']),    _txt(r['name_fr']),  _txt(r['name_de']),
        _txt(r['name_pt']),    _txt(r['supertype']),
        _int(r['hp']),         _txt(r['types']),    _txt(r['rarity']),
        _txt(r['set_id']),     _txt(r['set_name']),
        _txt(r['set_series']), _txt(r['number']),   _txt(r['image_url']),
      ]);
      if (i % 1000 == 0) onProgress?.call('Carte: ${i + 1} / ${rows.length}', (i + 1) / rows.length * 0.5);
    }

    onProgress?.call('Lettura stampe e prezzi...', 0.5);
    try {
      await _exportPokemonStampe(db, excel, onProgress);
    } catch (_) {
      // pokemon_prints not available — skip silently
    }
  }

  Future<void> _exportPokemonStampe(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final sheet = excel['Stampe'];
    _writeHeader(sheet, _pokemonStampeHeaders);
    final rows = await db.rawQuery('''
      SELECT p.id as print_id, p.card_id, c.name as card_name, c.api_id,
             p.set_code, p.set_name, p.rarity, p.set_price,
             p.set_code_it, p.set_name_it, p.rarity_it, p.set_price_it,
             p.set_code_fr, p.set_name_fr, p.rarity_fr, p.set_price_fr,
             p.set_code_de, p.set_name_de, p.rarity_de, p.set_price_de,
             p.set_code_pt, p.set_name_pt, p.rarity_pt, p.set_price_pt,
             p.set_code_es, p.set_name_es, p.rarity_es, p.set_price_es,
             p.ct_listing_count, p.ct_synced_at
      FROM pokemon_prints p
      LEFT JOIN pokemon_cards c ON p.card_id = c.id
      ORDER BY c.name, p.set_code
    ''') as List<Map<String, dynamic>>;

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      sheet.appendRow([
        _int(r['print_id']),   _int(r['card_id']),    _txt(r['card_name']),  _txt(r['api_id']),
        _txt(r['set_code']),   _txt(r['set_name']),   _txt(r['rarity']),     _dbl(r['set_price']),
        _txt(r['set_code_it']), _txt(r['set_name_it']), _txt(r['rarity_it']), _dbl(r['set_price_it']),
        _txt(r['set_code_fr']), _txt(r['set_name_fr']), _txt(r['rarity_fr']), _dbl(r['set_price_fr']),
        _txt(r['set_code_de']), _txt(r['set_name_de']), _txt(r['rarity_de']), _dbl(r['set_price_de']),
        _txt(r['set_code_pt']), _txt(r['set_name_pt']), _txt(r['rarity_pt']), _dbl(r['set_price_pt']),
        _txt(r['set_code_es']), _txt(r['set_name_es']), _txt(r['rarity_es']), _dbl(r['set_price_es']),
        _int(r['ct_listing_count']), _txt(r['ct_synced_at']),
      ]);
      if (i % 1000 == 0) onProgress?.call('Stampe: ${i + 1} / ${rows.length}', 0.5 + (i + 1) / rows.length * 0.5);
    }
  }

  // ── One Piece ─────────────────────────────────────────────────────────────────

  Future<void> _exportOnePiece(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final carteSheet = excel[_sheetName];
    _writeHeader(carteSheet, _onepieceHeaders);
    final rows = await db.rawQuery('''
      SELECT id, name, card_type, color, cost, power,
             life, counter_amount, sub_types, card_text, image_url, attribute
      FROM onepiece_cards ORDER BY id
    ''') as List<Map<String, dynamic>>;

    if (rows.isEmpty) throw Exception('Nessuna carta One Piece nel database locale. Scarica prima il catalogo.');

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      carteSheet.appendRow([
        _int(r['id']),            _txt(r['name']),       _txt(r['card_type']),
        _txt(r['color']),         _int(r['cost']),       _int(r['power']),
        _int(r['life']),          _int(r['counter_amount']),
        _txt(r['sub_types']),     _txt(r['card_text']),  _txt(r['image_url']),
        _txt(r['attribute']),
      ]);
      if (i % 500 == 0) onProgress?.call('Carte: ${i + 1} / ${rows.length}', (i + 1) / rows.length * 0.5);
    }

    onProgress?.call('Lettura stampe e prezzi...', 0.5);
    try {
      await _exportOnePieceStampe(db, excel, onProgress);
    } catch (_) {
      // onepiece_prints not available — skip silently
    }
  }

  Future<void> _exportOnePieceStampe(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final sheet = excel['Stampe'];
    _writeHeader(sheet, _onepieceStampeHeaders);
    final rows = await db.rawQuery('''
      SELECT p.id as print_id, p.card_id, c.name as card_name,
             p.card_set_id, p.set_id, p.set_name, p.rarity,
             p.market_price, p.market_price_en, p.market_price_fr,
             p.market_price_ko, p.market_price_zh, p.inventory_price,
             p.set_name_jp, p.set_name_fr, p.set_name_ko, p.set_name_zh,
             p.rarity_jp, p.rarity_fr, p.rarity_ko, p.rarity_zh,
             p.ct_listing_count, p.ct_synced_at
      FROM onepiece_prints p
      LEFT JOIN onepiece_cards c ON p.card_id = c.id
      ORDER BY c.name, p.card_set_id
    ''') as List<Map<String, dynamic>>;

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      sheet.appendRow([
        _int(r['print_id']),    _int(r['card_id']),     _txt(r['card_name']),
        _txt(r['card_set_id']), _txt(r['set_id']),      _txt(r['set_name']),    _txt(r['rarity']),
        _dbl(r['market_price']),    _dbl(r['market_price_en']),
        _dbl(r['market_price_fr']), _dbl(r['market_price_ko']), _dbl(r['market_price_zh']),
        _dbl(r['inventory_price']),
        _txt(r['set_name_jp']), _txt(r['set_name_fr']), _txt(r['set_name_ko']), _txt(r['set_name_zh']),
        _txt(r['rarity_jp']),   _txt(r['rarity_fr']),   _txt(r['rarity_ko']),   _txt(r['rarity_zh']),
        _int(r['ct_listing_count']), _txt(r['ct_synced_at']),
      ]);
      if (i % 500 == 0) onProgress?.call('Stampe: ${i + 1} / ${rows.length}', 0.5 + (i + 1) / rows.length * 0.5);
    }
  }

  // ── Magic: The Gathering ──────────────────────────────────────────────────────

  Future<void> _exportMagic(dynamic db, Excel excel, void Function(String, double?)? onProgress) async {
    final sheet = excel[_sheetName];
    _writeHeader(sheet, _magicHeaders);
    final rows = await db.rawQuery('''
      SELECT api_id, name, mana_cost, cmc, type_line, oracle_text,
             power, toughness, colors, rarity,
             set_code, set_name, collector_number, image_url, price_eur
      FROM magic_cards ORDER BY name
    ''') as List<Map<String, dynamic>>;

    if (rows.isEmpty) throw Exception('Nessuna carta Magic nel database locale. Scarica prima il catalogo.');

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      sheet.appendRow([
        _txt(r['api_id']),        _txt(r['name']),       _txt(r['mana_cost']),
        _dbl(r['cmc']),           _txt(r['type_line']),  _txt(r['oracle_text']),
        _txt(r['power']),         _txt(r['toughness']),  _txt(r['colors']),
        _txt(r['rarity']),        _txt(r['set_code']),   _txt(r['set_name']),
        _txt(r['collector_number']), _txt(r['image_url']),  _dbl(r['price_eur']),
      ]);
      if (i % 1000 == 0) onProgress?.call('Carte: ${i + 1} / ${rows.length}', (i + 1) / rows.length);
    }
  }

  // ── Generic v36 collections ───────────────────────────────────────────────────

  Future<void> _exportGeneric(
    dynamic db,
    Excel excel,
    String tablePrefix,
    String collection,
    void Function(String, double?)? onProgress,
  ) async {
    final sheet = excel[_sheetName];
    _writeHeader(sheet, _genericHeaders);
    final rows = await db.rawQuery('''
      SELECT api_id, name, card_type, subtype, rarity, cost, power, defense,
             effect, set_code, set_name,
             name_it, effect_it, name_fr, effect_fr, name_de, effect_de, name_pt, effect_pt
      FROM ${tablePrefix}_cards ORDER BY name
    ''') as List<Map<String, dynamic>>;

    if (rows.isEmpty) {
      throw Exception('Nessuna carta $collection nel database locale. Scarica prima il catalogo.');
    }

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      sheet.appendRow([
        _txt(r['api_id']),    _txt(r['name']),      _txt(r['card_type']),
        _txt(r['subtype']),   _txt(r['rarity']),    _txt(r['cost']),
        _txt(r['power']),     _txt(r['defense']),   _txt(r['effect']),
        _txt(r['set_code']),  _txt(r['set_name']),
        _txt(r['name_it']),   _txt(r['effect_it']),
        _txt(r['name_fr']),   _txt(r['effect_fr']),
        _txt(r['name_de']),   _txt(r['effect_de']),
        _txt(r['name_pt']),   _txt(r['effect_pt']),
      ]);
      if (i % 500 == 0) onProgress?.call('Carte: ${i + 1} / ${rows.length}', (i + 1) / rows.length);
    }
  }

  void _writeHeader(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  }

  // ── Preview Import ──────────────────────────────────────────────────────────

  /// Parses [fileBytes] (Excel .xlsx) and diffs against the local SQLite cache.
  /// Returns a preview with the list of cards that differ from the current values.
  Future<ImportPreview> previewImport(String collection, Uint8List fileBytes) async {
    final excel = Excel.decodeBytes(fileBytes.toList());
    final sheet = excel.tables[_sheetName];
    if (sheet == null) throw Exception('Foglio "$_sheetName" non trovato. Usa solo file esportati da questa app.');

    final rows = sheet.rows;
    if (rows.length < 2) throw Exception('Il file non contiene dati (solo intestazione o vuoto).');

    switch (collection) {
      case 'yugioh':   return _previewYugioh(rows);
      case 'pokemon':  return _previewPokemon(rows);
      case 'onepiece': return _previewOnePiece(rows);
      case 'magic':    return _previewMagic(rows);
      default:
        final prefix = DatabaseHelper.genericTablePrefix(collection);
        if (prefix == null) throw Exception('Collezione non supportata: $collection');
        return _previewGeneric(collection, prefix, rows);
    }
  }

  Future<ImportPreview> _previewYugioh(List<List<Data?>> rows) async {
    final excelCards = <int, Map<String, dynamic>>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      final id = _cellInt(row, 0);
      if (id == null || id == 0) continue;
      excelCards[id] = {
        'id': id,
        'name':           _cellStr(row, 1),
        'name_it':        _cellStr(row, 2),  'name_fr':        _cellStr(row, 3),
        'name_de':        _cellStr(row, 4),  'name_pt':        _cellStr(row, 5),
        'name_sp':        _cellStr(row, 6),
        'description':    _cellStr(row, 7),
        'description_it': _cellStr(row, 8),  'description_fr': _cellStr(row, 9),
        'description_de': _cellStr(row, 10), 'description_pt': _cellStr(row, 11),
        'description_sp': _cellStr(row, 12),
        'type':           _cellStr(row, 13), 'race':           _cellStr(row, 14),
        'archetype':      _cellStr(row, 15),
        'atk':            _cellInt(row, 16), 'def':            _cellInt(row, 17),
        'level':          _cellInt(row, 18), 'attribute':      _cellStr(row, 19),
      };
    }
    return _diffAgainstSqlite(
      collection: 'yugioh',
      excelById: excelCards,
      table: 'yugioh_cards',
      idColumn: 'id',
      editableFields: _yugiohEditableFields,
      totalScanned: rows.length - 1,
    );
  }

  Future<ImportPreview> _previewPokemon(List<List<Data?>> rows) async {
    final excelCards = <String, Map<String, dynamic>>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      final apiId = _cellStr(row, 1);
      if (apiId == null || apiId.isEmpty) continue;
      excelCards[apiId] = {
        'api_id':    apiId,
        'name':      _cellStr(row, 2), 'name_it':   _cellStr(row, 3),
        'name_fr':   _cellStr(row, 4), 'name_de':   _cellStr(row, 5),
        'name_pt':   _cellStr(row, 6), 'supertype': _cellStr(row, 7),
        'hp':        _cellInt(row, 8), 'types':     _cellStr(row, 9),
        'rarity':    _cellStr(row, 10),
      };
    }
    return _diffAgainstSqlite(
      collection: 'pokemon',
      excelById: excelCards,
      table: 'pokemon_cards',
      idColumn: 'api_id',
      editableFields: _pokemonEditableFields,
      totalScanned: rows.length - 1,
    );
  }

  Future<ImportPreview> _previewOnePiece(List<List<Data?>> rows) async {
    final excelCards = <int, Map<String, dynamic>>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      final id = _cellInt(row, 0);
      if (id == null || id == 0) continue;
      excelCards[id] = {
        'id':             id,
        'name':           _cellStr(row, 1),  'card_type':     _cellStr(row, 2),
        'color':          _cellStr(row, 3),  'cost':          _cellInt(row, 4),
        'power':          _cellInt(row, 5),  'life':          _cellInt(row, 6),
        'counter_amount': _cellInt(row, 7),  'sub_types':     _cellStr(row, 8),
        'card_text':      _cellStr(row, 9),
      };
    }
    return _diffAgainstSqlite(
      collection: 'onepiece',
      excelById: excelCards,
      table: 'onepiece_cards',
      idColumn: 'id',
      editableFields: _onepieceEditableFields,
      totalScanned: rows.length - 1,
    );
  }

  Future<ImportPreview> _previewMagic(List<List<Data?>> rows) async {
    final excelCards = <String, Map<String, dynamic>>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      final apiId = _cellStr(row, 0);
      if (apiId == null || apiId.isEmpty) continue;
      excelCards[apiId] = {
        'api_id':     apiId,
        'name':       _cellStr(row, 1),  'mana_cost':  _cellStr(row, 2),
        'type_line':  _cellStr(row, 4),  'oracle_text': _cellStr(row, 5),
        'power':      _cellStr(row, 6),  'toughness':  _cellStr(row, 7),
        'colors':     _cellStr(row, 8),  'rarity':     _cellStr(row, 9),
        'price_eur':  _cellDbl(row, 14),
      };
    }
    return _diffAgainstSqlite(
      collection: 'magic',
      excelById: excelCards,
      table: 'magic_cards',
      idColumn: 'api_id',
      editableFields: _magicEditableFields,
      totalScanned: rows.length - 1,
    );
  }

  Future<ImportPreview> _previewGeneric(
    String collection,
    String tablePrefix,
    List<List<Data?>> rows,
  ) async {
    final excelCards = <String, Map<String, dynamic>>{};
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      final apiId = _cellStr(row, 0);
      if (apiId == null || apiId.isEmpty) continue;
      excelCards[apiId] = {
        'api_id':    apiId,
        'name':      _cellStr(row, 1),   'card_type': _cellStr(row, 2),
        'subtype':   _cellStr(row, 3),   'rarity':    _cellStr(row, 4),
        'effect':    _cellStr(row, 8),
        'name_it':   _cellStr(row, 11),  'effect_it': _cellStr(row, 12),
        'name_fr':   _cellStr(row, 13),  'effect_fr': _cellStr(row, 14),
        'name_de':   _cellStr(row, 15),  'effect_de': _cellStr(row, 16),
        'name_pt':   _cellStr(row, 17),  'effect_pt': _cellStr(row, 18),
      };
    }
    return _diffAgainstSqlite(
      collection: collection,
      excelById: excelCards,
      table: '${tablePrefix}_cards',
      idColumn: 'api_id',
      editableFields: _genericEditableFields,
      totalScanned: rows.length - 1,
    );
  }

  /// Generic diff: compares Excel data map with SQLite rows for the given table.
  Future<ImportPreview> _diffAgainstSqlite<T>({
    required String collection,
    required Map<T, Map<String, dynamic>> excelById,
    required String table,
    required String idColumn,
    required List<String> editableFields,
    required int totalScanned,
  }) async {
    if (excelById.isEmpty) {
      return ImportPreview(collection: collection, changedCards: [], totalScanned: totalScanned);
    }

    final db = await _db.database;
    final ids = excelById.keys.toList();
    final placeholders = ids.map((_) => '?').join(',');
    final sqliteRows = await db.rawQuery(
      'SELECT ${editableFields.join(', ')}, $idColumn FROM $table WHERE $idColumn IN ($placeholders)',
      ids.map((id) => id is int ? id : id.toString()).toList(),
    );

    final sqliteMap = <T, Map<String, dynamic>>{};
    for (final r in sqliteRows) {
      final key = r[idColumn];
      if (key is T) sqliteMap[key] = r;
    }

    final changed = <Map<String, dynamic>>[];
    for (final entry in excelById.entries) {
      final sqliteCard = sqliteMap[entry.key];
      if (sqliteCard == null) continue;
      if (_hasChanges(entry.value, sqliteCard, editableFields)) {
        changed.add(entry.value);
      }
    }

    return ImportPreview(
      collection: collection,
      changedCards: changed,
      totalScanned: totalScanned,
    );
  }

  // ── Apply Import ────────────────────────────────────────────────────────────

  /// Applies the previewed changes to Firestore by scanning all catalog chunks,
  /// merging field-level updates, and writing back only affected chunks.
  Future<ImportResult> applyImport(
    ImportPreview preview,
    String adminUid, {
    void Function(String status, double? progress)? onProgress,
  }) async {
    if (preview.changedCards.isEmpty) {
      return const ImportResult(updatedCards: 0, affectedChunks: 0);
    }

    final catalogCollection = '${preview.collection}_catalog';
    final editableFields = _editableFieldsFor(preview.collection);

    // Build lookup: identifier → changed card data
    final changeMap = <String, Map<String, dynamic>>{};
    for (final card in preview.changedCards) {
      final id = _cardIdentifier(preview.collection, card);
      if (id != null) changeMap[id] = card;
    }

    // Load metadata
    onProgress?.call('Caricamento metadati Firestore...', null);
    final metaDoc = await _firestore
        .collection(catalogCollection)
        .doc('metadata')
        .get();
    if (!metaDoc.exists) {
      throw Exception('Catalogo Firestore non trovato per "${preview.collection}". Scarica prima il catalogo.');
    }
    final totalChunks = metaDoc.data()?['totalChunks'] as int? ?? 0;
    final currentVersion = metaDoc.data()?['version'] as int? ?? 0;
    if (totalChunks == 0) throw Exception('Il catalogo Firestore è vuoto.');

    // Scan all chunks in parallel batches, apply changes in-memory
    final affectedChunks = <String, List<Map<String, dynamic>>>{};
    int updatedCount = 0;

    onProgress?.call('Scansione $totalChunks chunk Firestore...', 0);
    for (int batchStart = 0; batchStart < totalChunks; batchStart += _chunkFetchBatchSize) {
      final batchEnd = (batchStart + _chunkFetchBatchSize).clamp(0, totalChunks);

      // Fetch batch in parallel
      final futures = List.generate(batchEnd - batchStart, (j) {
        final chunkId = 'chunk_${(batchStart + j + 1).toString().padLeft(3, '0')}';
        return _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .get()
            .then((doc) => (chunkId: chunkId, doc: doc));
      });
      final results = await Future.wait(futures);

      // Process each fetched chunk
      for (final r in results) {
        if (!r.doc.exists) continue;
        final cards = (r.doc.data()?['cards'] as List<dynamic>? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();

        bool chunkDirty = false;
        for (final card in cards) {
          final identifier = _cardIdentifier(preview.collection, card);
          if (identifier == null) continue;
          final changes = changeMap[identifier];
          if (changes == null) continue;

          // Merge only non-empty editable fields
          for (final field in editableFields) {
            final newVal = changes[field];
            if (newVal != null && newVal.toString().isNotEmpty) {
              card[field] = newVal;
            }
          }
          // For Magic, keep 'type' in sync with 'type_line'
          if (preview.collection == 'magic') {
            final typeLine = changes['type_line'];
            if (typeLine != null && typeLine.toString().isNotEmpty) {
              card['type'] = typeLine;
            }
          }
          card['_adminModified'] = true;

          chunkDirty = true;
          updatedCount++;
        }

        if (chunkDirty) affectedChunks[r.chunkId] = cards;
      }

      onProgress?.call(
        'Scansione chunk ${batchEnd.clamp(0, totalChunks)}/$totalChunks...',
        batchEnd / totalChunks,
      );
    }

    if (affectedChunks.isEmpty) {
      return const ImportResult(updatedCards: 0, affectedChunks: 0);
    }

    // Write back affected chunks in Firestore batches (max 400 ops each)
    onProgress?.call('Scrittura ${affectedChunks.length} chunk su Firestore...', null);
    final chunkList = affectedChunks.entries.toList();
    for (int i = 0; i < chunkList.length; i += 400) {
      final writeBatch = _firestore.batch();
      final end = (i + 400).clamp(0, chunkList.length);
      for (int j = i; j < end; j++) {
        final entry = chunkList[j];
        final ref = _firestore
            .collection(catalogCollection)
            .doc('chunks')
            .collection('items')
            .doc(entry.key);
        writeBatch.set(ref, {'cards': entry.value});
      }
      await writeBatch.commit();
    }

    // Bump catalog version
    await _firestore.collection(catalogCollection).doc('metadata').update({
      'version': currentVersion + 1,
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    });

    onProgress?.call('Importazione completata!', 1.0);
    return ImportResult(
      updatedCards: updatedCount,
      affectedChunks: affectedChunks.length,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String? _cardIdentifier(String collection, Map<String, dynamic> card) {
    switch (collection) {
      case 'yugioh':
      case 'onepiece':
        return card['id']?.toString();
      case 'pokemon':
      case 'magic':
        return (card['api_id'] as String?)?.isNotEmpty == true
            ? card['api_id'] as String
            : card['id']?.toString();
      default:
        // Generic v36: api_id is the primary key
        return (card['api_id'] as String?)?.isNotEmpty == true
            ? card['api_id'] as String
            : null;
    }
  }

  List<String> _editableFieldsFor(String collection) => switch (collection) {
    'yugioh'   => _yugiohEditableFields,
    'pokemon'  => _pokemonEditableFields,
    'onepiece' => _onepieceEditableFields,
    'magic'    => _magicEditableFields,
    _          => DatabaseHelper.genericTablePrefix(collection) != null
                  ? _genericEditableFields
                  : <String>[],
  };

  /// Returns true if any non-empty Excel field differs from the SQLite value.
  bool _hasChanges(
    Map<String, dynamic> newData,
    Map<String, dynamic> existing,
    List<String> fields,
  ) {
    for (final field in fields) {
      final newVal = newData[field]?.toString() ?? '';
      if (newVal.isEmpty) continue; // empty in Excel = "no change"
      final oldVal = existing[field]?.toString() ?? '';
      if (newVal != oldVal) return true;
    }
    return false;
  }

  // ── Cell value builders ─────────────────────────────────────────────────────

  CellValue _txt(dynamic v) => TextCellValue(v?.toString() ?? '');
  CellValue _int(dynamic v) => v != null ? IntCellValue(v as int) : TextCellValue('');
  CellValue _dbl(dynamic v) => v != null ? DoubleCellValue((v as num).toDouble()) : TextCellValue('');

  // ── Cell value readers ──────────────────────────────────────────────────────

  /// Extracts a plain string from a TextCellValue.
  /// In some versions of the excel package, TextCellValue.value is a TextSpan
  /// (Flutter InlineSpan) rather than a raw String, so we handle both cases
  /// via dynamic access to avoid compile-time type errors.
  String _textCellStr(TextCellValue v) {
    // Declare as dynamic so Dart allows access regardless of whether
    // TextCellValue.value is String (older excel versions) or TextSpan (newer).
    final dynamic inner = v.value;
    if (inner is String) return inner;
    // TextSpan path: try .text property, then .toPlainText()
    try { final t = inner.text; if (t is String && t.isNotEmpty) return t; } catch (_) {}
    try { final t = inner.toPlainText(); if (t is String) return t; } catch (_) {}
    return inner.toString();
  }

  String? _cellStr(List<Data?> row, int col) {
    if (col >= row.length) return null;
    final v = row[col]?.value;
    if (v == null) return null;
    String s;
    if (v is TextCellValue) {
      s = _textCellStr(v);
    } else if (v is IntCellValue) {
      s = v.value.toString();
    } else if (v is DoubleCellValue) {
      s = v.value.toString();
    } else {
      s = v.toString();
    }
    return s.trim().isEmpty ? null : s.trim();
  }

  int? _cellInt(List<Data?> row, int col) {
    if (col >= row.length) return null;
    final v = row[col]?.value;
    if (v == null) return null;
    if (v is IntCellValue) return v.value;
    if (v is DoubleCellValue) return v.value.toInt();
    if (v is TextCellValue) return int.tryParse(_textCellStr(v).trim());
    return null;
  }

  double? _cellDbl(List<Data?> row, int col) {
    if (col >= row.length) return null;
    final v = row[col]?.value;
    if (v == null) return null;
    if (v is DoubleCellValue) return v.value;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is TextCellValue) return double.tryParse(_textCellStr(v).trim());
    return null;
  }
}
