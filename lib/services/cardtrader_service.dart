import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';
import 'admin_catalog_service.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'sync_service.dart';

/// CardTrader API integration for real marketplace price data.
///
/// Supported collections and their CardTrader game IDs:
///   'yugioh'   → 4
///   'pokemon'  → 5
///   'onepiece' → 15
class CardtraderService {
  static const _baseUrl = 'https://api.cardtrader.com/api/v2';

  static const gameIds = <String, int>{
    'yugioh': 4,
    'pokemon': 5,
    'onepiece': 15,
  };

  // Language property key per collection (in properties_hash)
  static const _langKeys = <String, String>{
    'yugioh': 'yugioh_language',
    'pokemon': 'pokemon_language',
    'onepiece': 'onepiece_language',
  };

  // Rarity property key per collection (in properties_hash)
  static const _rarityKeys = <String, String>{
    'yugioh': 'yugioh_rarity',
    'pokemon': 'pokemon_rarity',
    'onepiece': 'onepiece_rarity',
  };

  // Available languages per catalog (CardTrader language codes).
  // Note: CardTrader uses 'es' for Spanish (YGO uses 'sp' internally).
  static const _catalogLanguages = <String, Map<String, String>>{
    'yugioh': {
      'en': 'Inglese', 'it': 'Italiano', 'fr': 'Francese',
      'de': 'Tedesco', 'pt': 'Portoghese', 'es': 'Spagnolo',
    },
    'pokemon': {
      'en': 'Inglese', 'ja': 'Giapponese', 'fr': 'Francese',
      'de': 'Tedesco', 'it': 'Italiano', 'es': 'Spagnolo',
      'pt': 'Portoghese', 'ko': 'Coreano',
    },
    'onepiece': {
      'ja': 'Giapponese', 'en': 'Inglese', 'fr': 'Francese',
      'zh': 'Cinese',     'ko': 'Coreano',
    },
  };

  /// Returns the language code→label map for [catalog].
  static Map<String, String> languagesForCatalog(String catalog) =>
      _catalogLanguages[catalog] ?? {};

  /// Detects the CardTrader language code from a card serial number.
  ///
  /// YuGiOh:   "LOB-EN001" → "en", "LOB-IT001" → "it", "LOB-SP001" → "es"
  /// One Piece: "OP01-001" → "ja" (default), "OP01-EN001" → "en"
  /// Pokemon:   any serial → "en" (serials don't encode language)
  static String languageFromSerial(String sn, String collection) {
    if (collection == 'yugioh') {
      final m = RegExp(r'-([A-Za-z]{2})[A-Za-z0-9]').firstMatch(sn);
      if (m != null) {
        final code = m.group(1)!.toLowerCase();
        return code == 'sp' ? 'es' : code;
      }
    } else if (collection == 'onepiece') {
      final cn = sn.contains('-') ? sn.substring(sn.indexOf('-') + 1) : '';
      final m = RegExp(r'^([A-Za-z]{2})\d').firstMatch(cn);
      if (m != null) return m.group(1)!.toLowerCase();
      return 'ja'; // Default: One Piece cards are Japanese unless serial says otherwise
    }
    return 'en';
  }

  /// Normalizes CardTrader API language codes to internal codes.
  /// CT uses 'jp' for Japanese, 'kr' for Korean, 'zh-CN' for Chinese.
  static String normalizeLang(String ctLang) {
    switch (ctLang.toLowerCase()) {
      case 'jp': return 'ja';
      case 'kr': return 'ko';
      case 'zh-cn': return 'zh';
      default: return ctLang.toLowerCase();
    }
  }

  static String _normalizeLang(String ctLang) => normalizeLang(ctLang);

  /// Extracts the image URL from a CT blueprint map.
  /// CT may return image as a String URL or as a nested map {original, show}.
  static String? extractBlueprintImageUrl(Map<String, dynamic> blueprint) {
    final image = blueprint['image'];
    if (image is String && image.isNotEmpty) return image;
    if (image is Map) {
      final show = image['show'];
      if (show is String && show.isNotEmpty) return show;
      final original = image['original'];
      if (original is String && original.isNotEmpty) return original;
    }
    final imageUrl = blueprint['image_url'];
    if (imageUrl is String && imageUrl.isNotEmpty) return imageUrl;
    return null;
  }

  String get _jwt => AppSecrets.cardtraderJwt;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_jwt',
        'Accept': 'application/json',
        'Accept-Encoding': 'identity', // prevent gzip so json.decode works
      };

  final DatabaseHelper _db;

  CardtraderService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  // ─── Public sync API ───────────────────────────────────────────────────────

  /// Syncs prices for the given [catalog] across ALL available languages.
  ///
  /// Steps:
  ///   1. Fetch all CT expansions for this game.
  ///   2. Match against locally-known set codes (set_id column).
  ///   3. For each matched expansion:
  ///      a. Fetch all /blueprints → seed DB rows for every language present.
  ///      b. Fetch /marketplace/products → upsert prices for all languages.
  ///   4. Update card collection values from the new prices.
  ///
  /// Returns a summary map: {expansions, blueprints, pricedBlueprints, skipped, errors}.
  Future<Map<String, dynamic>> syncPrices({
    required String catalog,
    required String adminUid,
    required void Function(String msg, double? progress) onProgress,
  }) async {
    if (kIsWeb) return _syncPricesWeb(catalog: catalog, adminUid: adminUid, onProgress: onProgress);

    final gameId = gameIds[catalog];
    if (gameId == null) throw Exception('Catalogo non supportato: $catalog');
    if (_jwt.isEmpty) {
      throw Exception('CARDTRADER_JWT non configurato nel file .env');
    }

    onProgress('Caricamento espansioni CardTrader…', null);
    final ctExpansions = await _fetchExpansions(gameId);

    onProgress('Caricamento set locali…', null);
    final localCodes = await _db.getDistinctSetCodesForCardtrader(catalog);

    // Build a map from CT code → local code with multi-level normalization:
    //   1. Exact match:            "op01"     → "op01"
    //   2. Remove dashes:          "op-01"    → "op01"
    //   3. Strip all punctuation:  "sv3.5"    → "sv35"  (handles dotted Pokémon set codes)
    //   4. Pokémon "pt" suffix:    "sv35"     ↔ "sv3pt5" (e.g. Pokémon 151 = sv3pt5 on TCGDex)
    final ctToLocal = <String, String>{};
    // Pre-build reverse lookup: stripped-local → original-local for fuzzy match
    final strippedLocalToLocal = <String, String>{};
    for (final lc in localCodes) {
      final stripped = lc.replaceAll(RegExp(r'[^a-z0-9]'), '');
      strippedLocalToLocal.putIfAbsent(stripped, () => lc);
      // Also index with "pt" replaced by "" for Pokémon sets like "sv3pt5" ↔ "sv35"
      final noPt = stripped.replaceAll('pt', '');
      strippedLocalToLocal.putIfAbsent(noPt, () => lc);
    }
    for (final e in ctExpansions) {
      final ctCode = (e['code'] as String? ?? '').toLowerCase();
      if (localCodes.contains(ctCode)) {
        ctToLocal[ctCode] = ctCode;
      } else {
        final noDash = ctCode.replaceAll('-', '');
        if (localCodes.contains(noDash)) {
          ctToLocal[ctCode] = noDash;
        } else {
          // Strip all non-alphanumeric and try fuzzy match
          final stripped = ctCode.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final fuzzy = strippedLocalToLocal[stripped] ??
              strippedLocalToLocal[stripped.replaceAll('pt', '')];
          if (fuzzy != null) ctToLocal[ctCode] = fuzzy;
        }
      }
    }
    final matched = ctExpansions.where((e) {
      final ctCode = (e['code'] as String? ?? '').toLowerCase();
      return ctToLocal.containsKey(ctCode);
    }).toList();

    onProgress(
      'Trovati ${localCodes.length} set locali · ${ctExpansions.length} espansioni CT · ${matched.length} corrispondenze',
      null,
    );

    int totalBlueprints = 0;  // blueprints seeded (from /blueprints endpoint)
    int pricedBlueprints = 0; // blueprints with active marketplace listings
    int skipped = 0;
    int errors = 0;

    for (int i = 0; i < matched.length; i++) {
      final exp = matched[i];
      final expId = exp['id'] as int;
      // Use the LOCAL code so cardtrader_prices.expansion_code matches the catalog DB.
      final expCode = ctToLocal[(exp['code'] as String).toLowerCase()]!;
      final expName = exp['name'] as String? ?? expCode;

      onProgress(
        '$expName ($expCode) — ${i + 1}/${matched.length}',
        (i + 1) / matched.length,
      );

      try {
        // ── Fetch blueprints + marketplace in parallel ────────────────────
        late List<Map<String, dynamic>> blueprints;
        late Map<String, List<Map<String, dynamic>>> products;
        await Future.wait([
          _fetchBlueprints(expId).then((r) => blueprints = r),
          _fetchMarketplaceProducts(expId).then((r) => products = r),
        ]);

        // ── Step a: seed blueprint placeholders ───────────────────────────
        final byLang = _groupBlueprintsByLanguage(blueprints, catalog);
        for (final entry in byLang.entries) {
          final rows = _buildBlueprintMaps(catalog, expCode, entry.value, entry.key);
          if (rows.isNotEmpty) {
            await _db.insertBlueprintsIfAbsent(rows);
            totalBlueprints += rows.length;
          }
        }

        // ── Step b: upsert marketplace prices ─────────────────────────────
        if (products.isEmpty) {
          skipped++;
        } else {
          final priced = await _storePrices(catalog, expCode, products);
          pricedBlueprints += priced;
        }
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) { // ignore: empty_catches

        errors++;
      }
    }

    // Always push prices to Firestore so other users can download them.
    await _pushCardValuesToFirestore(catalog);

    onProgress('Aggiornamento prezzi catalogo locale…', null);
    final catalogUpdated = await _db.syncCatalogPricesFromCardtrader(catalog);

    // Scrivi i prezzi CT nei chunk Firestore così tutti gli utenti
    // li vedono al prossimo download del catalogo.
    onProgress('Pubblicazione prezzi su Firestore…', null);
    Map<String, dynamic> firestoreResult = {'modifiedChunks': 0, 'totalChunks': 0, 'updatedPrices': 0};
    try {
      firestoreResult = await AdminCatalogService().syncCatalogPricesToFirestore(
        catalog: catalog,
        adminUid: adminUid,
        onProgress: onProgress,
      );
    } catch (_) {}

    if (catalogUpdated > 0) {
      SyncService().notifyLocalChange('cards');
    }

    return {
      'success': true,
      'expansions': matched.length,
      'ctExpansionsTotal': ctExpansions.length,
      'localSets': localCodes.length,
      'blueprints': totalBlueprints,
      'pricedBlueprints': pricedBlueprints,
      'skipped': skipped,
      'errors': errors,
      'catalog': catalog,
      'catalogUpdated': catalogUpdated,
      'firestoreChunksUpdated': firestoreResult['modifiedChunks'],
      'firestorePricesUpdated': firestoreResult['updatedPrices'],
    };
  }

  // ─── Public price lookup ───────────────────────────────────────────────────

  /// Returns the best available [CardtraderPrice] for a card from local cache.
  ///
  /// [expansionCode] is the set_id (e.g. 'lob', 'swsh1') — lowercase.
  /// [language] is the card's language code ('en', 'it', 'fr', 'de', 'es', 'pt').
  /// If [firstEdition] is null, returns the cheapest regardless of edition.
  Future<CardtraderPrice?> getPriceForCard({
    required String catalog,
    required String expansionCode,
    required String cardName,
    required String language,
    bool? firstEdition,
    String? rarity,
    String? collectorNumber,
    String? catalogId,
  }) async {
    final row = await _db.getCardtraderPrice(
      catalog: catalog,
      expansionCode: expansionCode.toLowerCase(),
      cardName: cardName,
      language: language.toLowerCase(),
      firstEdition: firstEdition,
      rarity: rarity,
      collectorNumber: collectorNumber,
      catalogId: catalogId,
    );
    if (row == null) return null;
    return CardtraderPrice.fromMap(row as Map<String, dynamic>);
  }

  /// Returns all cached CardTrader prices for a card across every language.
  ///
  /// One [CardtraderPrice] per language — best (cheapest) price for each.
  /// [catalogId] is used as a fallback to resolve the English card name via
  /// catalog JOIN, bypassing localized card names.
  Future<List<CardtraderPrice>> getAllPricesForCard({
    required String catalog,
    required String expansionCode,
    required String cardName,
    String? rarity,
    String? collectorNumber,
    String? catalogId,
  }) async {
    final rows = await _db.getPricesForCardAllLanguages(
      catalog: catalog,
      expansionCode: expansionCode.toLowerCase(),
      cardName: cardName,
      rarity: rarity,
      collectorNumber: collectorNumber,
      catalogId: catalogId,
    );
    return rows.map(CardtraderPrice.fromMap).toList();
  }

  /// Aggiorna i prezzi del catalogo dai prezzi CT in cache locale.
  /// Returns the number of catalog print rows updated.
  Future<int> applyLocalPricesToCollection(String catalog) async {
    return await _db.syncCatalogPricesFromCardtrader(catalog);
  }

  // ─── Web-specific sync (Firestore-only, no SQLite) ───────────────────────

  Future<Map<String, dynamic>> _syncPricesWeb({
    required String catalog,
    required String adminUid,
    required void Function(String msg, double? progress) onProgress,
  }) async {
    final gameId = gameIds[catalog];
    if (gameId == null) throw Exception('Catalogo non supportato: $catalog');
    if (_jwt.isEmpty) throw Exception('CARDTRADER_JWT non configurato');

    onProgress('Caricamento espansioni CardTrader…', null);
    final ctExpansions = await _fetchExpansions(gameId);

    onProgress('Lettura set da Firestore…', null);
    final localCodes = await _getSetCodesFromFirestore(catalog);

    final ctToLocalWeb = <String, String>{};
    final strippedLocalToLocalWeb = <String, String>{};
    for (final lc in localCodes) {
      final stripped = lc.replaceAll(RegExp(r'[^a-z0-9]'), '');
      strippedLocalToLocalWeb.putIfAbsent(stripped, () => lc);
      strippedLocalToLocalWeb.putIfAbsent(stripped.replaceAll('pt', ''), () => lc);
    }
    for (final e in ctExpansions) {
      final ctCode = (e['code'] as String? ?? '').toLowerCase();
      if (localCodes.contains(ctCode)) {
        ctToLocalWeb[ctCode] = ctCode;
      } else {
        final noDash = ctCode.replaceAll('-', '');
        if (localCodes.contains(noDash)) {
          ctToLocalWeb[ctCode] = noDash;
        } else {
          final stripped = ctCode.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final fuzzy = strippedLocalToLocalWeb[stripped] ??
              strippedLocalToLocalWeb[stripped.replaceAll('pt', '')];
          if (fuzzy != null) ctToLocalWeb[ctCode] = fuzzy;
        }
      }
    }
    final matched = ctExpansions.where((e) {
      final ctCode = (e['code'] as String? ?? '').toLowerCase();
      return ctToLocalWeb.containsKey(ctCode);
    }).toList();

    int totalBlueprints = 0;
    int pricedBlueprints = 0;
    int errors = 0;
    final allPrices = <CardtraderPrice>[];

    for (int i = 0; i < matched.length; i++) {
      final exp = matched[i];
      final expId = exp['id'] as int;
      final expCode = ctToLocalWeb[(exp['code'] as String).toLowerCase()]!;
      final expName = exp['name'] as String? ?? expCode;

      onProgress('$expName — ${i + 1}/${matched.length}', (i + 1) / matched.length);

      try {
        late List<Map<String, dynamic>> blueprints;
        late Map<String, List<Map<String, dynamic>>> products;
        await Future.wait([
          _fetchBlueprints(expId).then((r) => blueprints = r),
          _fetchMarketplaceProducts(expId).then((r) => products = r),
        ]);

        final byLang = _groupBlueprintsByLanguage(blueprints, catalog);
        for (final entry in byLang.entries) {
          totalBlueprints += _buildBlueprintMaps(catalog, expCode, entry.value, entry.key).length;
        }

        if (products.isNotEmpty) {
          final prices = _collectPricesInMemory(catalog, expCode, products);
          allPrices.addAll(prices);
          if (prices.isNotEmpty) pricedBlueprints += prices.length;
        }

        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {
        errors++;
      }
    }

    // Save all prices to Firestore (replaces local SQLite on web)
    onProgress('Salvataggio prezzi su Firestore…', null);
    if (allPrices.isNotEmpty) {
      await FirestoreService().saveCardtraderPrices(
        catalog,
        allPrices.map((p) => p.toMap()).toList(),
      );
    }

    return {
      'success': true,
      'expansions': matched.length,
      'blueprints': totalBlueprints,
      'pricedBlueprints': pricedBlueprints,
      'skipped': 0,
      'errors': errors,
      'catalog': catalog,
      'valuesUpdated': 0,
      'catalogUpdated': allPrices.length,
    };
  }

  /// Reads distinct set codes from Firestore catalog chunks (web fallback).
  Future<Set<String>> _getSetCodesFromFirestore(String catalog) async {
    try {
      final cards = await FirestoreService().fetchCatalog(catalog);
      final codes = <String>{};
      for (final card in cards) {
        // sets is a map keyed by language; each entry has set_id
        final sets = card['sets'];
        if (sets is Map) {
          for (final langEntry in sets.values) {
            if (langEntry is Map) {
              final setId = langEntry['set_id'] as String?;
              if (setId != null && setId.isNotEmpty) {
                codes.add(setId.toLowerCase());
              }
            }
          }
        }
        // also check top-level set_id (Pokemon / One Piece)
        final topSetId = card['set_id'] as String?;
        if (topSetId != null && topSetId.isNotEmpty) {
          codes.add(topSetId.toLowerCase());
        }
      }
      return codes;
    } catch (_) {
      return {};
    }
  }

  /// Collects prices from marketplace products into memory (no SQLite write).
  List<CardtraderPrice> _collectPricesInMemory(
    String catalog,
    String expansionCode,
    Map<String, List<Map<String, dynamic>>> products,
  ) {
    final langKey = _langKeys[catalog] ?? 'yugioh_language';
    final rarityKey = _rarityKeys[catalog] ?? 'yugioh_rarity';
    final prices = <CardtraderPrice>[];
    final now = DateTime.now().toIso8601String();

    for (final entry in products.entries) {
      final blueprintId = int.tryParse(entry.key);
      if (blueprintId == null) continue;
      final listings = entry.value;
      if (listings.isEmpty) continue;

      final cardNameEn = listings.first['name_en'] as String? ?? '';
      if (cardNameEn.isEmpty) continue;

      final firstPh = listings.first['properties_hash'] as Map<String, dynamic>? ?? {};
      final collectorNumber =
          (listings.first['collector_number'] as String?)?.trim() ??
          (firstPh['collector_number'] as String?)?.trim() ??
          (firstPh['number'] as String?)?.trim() ??
          '';

      final nmPrices = <String, List<int>>{};
      final anyPrices = <String, List<int>>{};
      final rarityByKey = <String, String>{};

      for (final listing in listings) {
        final ph = listing['properties_hash'] as Map<String, dynamic>? ?? {};
        final lang = _normalizeLang(ph[langKey] as String? ?? 'en');
        final isFirst = (ph['first_edition'] as bool?) == true ? 1 : 0;
        final rarity = (ph[rarityKey] as String? ?? '').toLowerCase();
        final condition = ph['condition'] as String? ?? '';
        final priceCents = listing['price_cents'] as int?;
        if (priceCents == null || priceCents <= 0) continue;

        final key = '$lang|$isFirst|$rarity';
        rarityByKey[key] = rarity;
        final isNm = condition.contains('Near Mint') ||
            (condition.contains('Mint') && !condition.contains('Moderately'));

        anyPrices.putIfAbsent(key, () => []).add(priceCents);
        if (isNm) nmPrices.putIfAbsent(key, () => []).add(priceCents);
      }

      for (final key in anyPrices.keys) {
        final parts = key.split('|');
        final lang = parts[0];
        final firstEd = parts[1] == '1';
        final rarity = rarityByKey[key] ?? '';
        final nm = nmPrices[key];
        final any = anyPrices[key]!;

        prices.add(CardtraderPrice(
          blueprintId: blueprintId,
          catalog: catalog,
          expansionCode: expansionCode,
          cardNameEn: cardNameEn,
          language: lang,
          firstEdition: firstEd,
          rarity: rarity,
          collectorNumber: collectorNumber,
          minPriceNmCents: nm != null && nm.isNotEmpty ? nm.reduce(_min) : null,
          minPriceAnyCents: any.reduce(_min),
          listingCount: any.length,
          syncedAt: now,
        ));
      }
    }
    return prices;
  }

  Future<void> _pushCardValuesToFirestore(String catalog) async {
    try {
      final prices = await _db.getAllCardtraderPrices(catalog);
      if (prices.isEmpty) return;
      await FirestoreService().saveCardtraderPrices(catalog, prices);

    } catch (e) { // ignore: empty_catches

    }
  }

  // ─── Public catalog-fetch API (used by AdminCatalogService) ───────────────

  /// Fetches all CT expansions for [catalog] (e.g. 'pokemon', 'onepiece').
  Future<List<Map<String, dynamic>>> fetchExpansionsForCatalog(String catalog) async {
    final gameId = gameIds[catalog];
    if (gameId == null) return [];
    return _fetchExpansions(gameId);
  }

  /// Fetches all blueprints for the given CT expansion ID.
  Future<List<Map<String, dynamic>>> fetchBlueprintsForExpansion(int expansionId) =>
      _fetchBlueprints(expansionId);

  // ─── HTTP helpers ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchExpansions(int gameId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/expansions'), headers: _headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Errore fetch espansioni: HTTP ${response.statusCode}\n${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    if (response.body.trimLeft().startsWith('<')) {
      throw Exception('CardTrader non disponibile (manutenzione in corso). Riprova più tardi.');
    }

    dynamic all;
    try {
      all = json.decode(response.body);
    } catch (e) { // ignore: empty_catches
      throw Exception('Errore parsing espansioni: $e\nBody: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }
    if (all is! List) throw Exception('Risposta espansioni non valida: ${all.runtimeType}');

    return all
        .cast<Map<String, dynamic>>()
        .where((e) => e['game_id'] == gameId)
        .toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchMarketplaceProducts(
      int expansionId) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/marketplace/products?expansion_id=$expansionId'),
          headers: _headers,
        )
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw Exception('Errore fetch products: HTTP ${response.statusCode}\n${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    dynamic raw;
    try {
      raw = json.decode(response.body);
    } catch (e) { // ignore: empty_catches
      throw Exception('Errore parsing products: $e\nBody: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }
    if (raw is! Map) return {};

    return raw.map((k, v) =>
        MapEntry(k.toString(), (v as List).cast<Map<String, dynamic>>()));
  }

  // ─── Blueprint helpers ─────────────────────────────────────────────────────

  /// Fetches all blueprints for [expansionId] (cards that exist, with or
  /// without active listings). Returns an empty list on error.
  Future<List<Map<String, dynamic>>> _fetchBlueprints(int expansionId) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/blueprints?expansion_id=$expansionId'),
          headers: _headers,
        )
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw Exception(
          'Errore fetch blueprints: HTTP ${response.statusCode}\n'
          '${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    dynamic raw;
    try {
      raw = json.decode(response.body);
    } catch (e) { // ignore: empty_catches
      throw Exception('Errore parsing blueprints: $e\nBody: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
    }

    // CT may return a plain array OR a wrapped object like {"blueprints":[...]}
    if (raw is Map) {
      raw = raw['blueprints'] ?? raw['cards'] ?? raw['data'] ?? raw['items'];
    }
    if (raw is! List) {
      throw Exception(
        'Risposta blueprints non è una lista. '
        'Body: ${response.body.substring(0, response.body.length.clamp(0, 300))}',
      );
    }
    return raw.cast<Map<String, dynamic>>();
  }

  /// Groups [blueprints] by their language code.
  /// CardTrader stores language in `fixed_properties` (blueprints endpoint)
  /// or `properties_hash` (products endpoint).
  /// Returns a map of language_code → list of blueprints for that language.
  Map<String, List<Map<String, dynamic>>> _groupBlueprintsByLanguage(
    List<Map<String, dynamic>> blueprints,
    String catalog,
  ) {
    final langKey = _langKeys[catalog] ?? 'yugioh_language';
    final result = <String, List<Map<String, dynamic>>>{};
    for (final bp in blueprints) {
      final props = (bp['fixed_properties'] as Map<String, dynamic>?) ??
          (bp['properties_hash'] as Map<String, dynamic>?) ??
          {};
      final lang = _normalizeLang(props[langKey] as String? ?? 'en');
      result.putIfAbsent(lang, () => []).add(bp);
    }
    return result;
  }

  /// Converts a list of blueprint objects to `cardtrader_prices` row maps
  /// with null prices (listing_count = 0). These act as placeholders so every
  /// known card has a row even before marketplace listings are available.
  List<Map<String, dynamic>> _buildBlueprintMaps(
    String catalog,
    String expansionCode,
    List<Map<String, dynamic>> blueprints,
    String language,
  ) {
    final rarityKey = _rarityKeys[catalog] ?? 'yugioh_rarity';
    final now = DateTime.now().toIso8601String();
    final result = <Map<String, dynamic>>[];

    for (final bp in blueprints) {
      final blueprintId = bp['id'] as int?;
      if (blueprintId == null) continue;

      // name_en preferred; fall back to generic name field
      final cardNameEn = (bp['name_en'] as String?)?.trim() ??
          (bp['name'] as String?)?.trim() ??
          '';
      if (cardNameEn.isEmpty) continue;

      final props = (bp['fixed_properties'] as Map<String, dynamic>?) ??
          (bp['properties_hash'] as Map<String, dynamic>?) ??
          {};
      final rarity = (props[rarityKey] as String? ?? '').toLowerCase();
      final firstEd = (props['first_edition'] as bool?) == true ? 1 : 0;
      // CT stores collector number as 'collector_number' or 'number'
      final collectorNumber =
          (props['collector_number'] as String?)?.trim() ??
          (props['number'] as String?)?.trim() ??
          '';

      result.add({
        'blueprint_id': blueprintId,
        'catalog': catalog,
        'expansion_code': expansionCode,
        'card_name_en': cardNameEn,
        'language': language,
        'first_edition': firstEd,
        'rarity': rarity,
        'collector_number': collectorNumber,
        'min_price_nm_cents': null,
        'min_price_any_cents': null,
        'listing_count': 0,
        'synced_at': now,
      });
    }
    return result;
  }

  // ─── Price processing ──────────────────────────────────────────────────────

  /// Processes [products] (blueprint_id → listings map) from the marketplace
  /// endpoint across ALL languages. Upserts price rows and returns the
  /// number of distinct blueprint+language combinations with at least one listing.
  Future<int> _storePrices(
    String catalog,
    String expansionCode,
    Map<String, List<Map<String, dynamic>>> products,
  ) async {
    final langKey = _langKeys[catalog] ?? 'yugioh_language';
    final rarityKey = _rarityKeys[catalog] ?? 'yugioh_rarity';
    final prices = <CardtraderPrice>[];
    final now = DateTime.now().toIso8601String();

    for (final entry in products.entries) {
      final blueprintId = int.tryParse(entry.key);
      if (blueprintId == null) continue;
      final listings = entry.value;
      if (listings.isEmpty) continue;

      final cardNameEn = listings.first['name_en'] as String? ?? '';
      if (cardNameEn.isEmpty) continue;

      // collector_number is a blueprint-level attribute — read once from the
      // first listing's properties_hash (or top-level field if CT exposes it).
      final firstPh =
          listings.first['properties_hash'] as Map<String, dynamic>? ?? {};
      final collectorNumber =
          (listings.first['collector_number'] as String?)?.trim() ??
          (firstPh['collector_number'] as String?)?.trim() ??
          (firstPh['number'] as String?)?.trim() ??
          '';

      // Group listings by: lang|first_edition(0|1)|rarity — no language filter
      final nmPrices = <String, List<int>>{};
      final anyPrices = <String, List<int>>{};
      final rarityByKey = <String, String>{};

      for (final listing in listings) {
        final ph = listing['properties_hash'] as Map<String, dynamic>? ?? {};
        final lang = _normalizeLang(ph[langKey] as String? ?? 'en');
        final isFirst = (ph['first_edition'] as bool?) == true ? 1 : 0;
        final rarity = (ph[rarityKey] as String? ?? '').toLowerCase();
        final condition = ph['condition'] as String? ?? '';
        final priceCents = listing['price_cents'] as int?;
        if (priceCents == null || priceCents <= 0) continue;

        final key = '$lang|$isFirst|$rarity';
        rarityByKey[key] = rarity;
        final isNm = condition.contains('Near Mint') ||
            (condition.contains('Mint') && !condition.contains('Moderately'));

        anyPrices.putIfAbsent(key, () => []).add(priceCents);
        if (isNm) nmPrices.putIfAbsent(key, () => []).add(priceCents);
      }

      for (final key in anyPrices.keys) {
        final parts = key.split('|');
        final lang = parts[0];
        final firstEd = parts[1] == '1';
        final rarity = rarityByKey[key] ?? '';
        final nm = nmPrices[key];
        final any = anyPrices[key]!;

        prices.add(CardtraderPrice(
          blueprintId: blueprintId,
          catalog: catalog,
          expansionCode: expansionCode,
          cardNameEn: cardNameEn,
          language: lang,
          firstEdition: firstEd,
          rarity: rarity,
          collectorNumber: collectorNumber,
          minPriceNmCents: nm != null && nm.isNotEmpty ? nm.reduce(_min) : null,
          minPriceAnyCents: any.reduce(_min),
          listingCount: any.length,
          syncedAt: now,
        ));
      }
    }

    if (prices.isNotEmpty) {
      await _db.upsertCardtraderPrices(prices.map((p) => p.toMap()).toList());
    }
    return prices.length;
  }

  static int _min(int a, int b) => a < b ? a : b;
}

// ─── Model ─────────────────────────────────────────────────────────────────

/// Cached price record from CardTrader marketplace.
class CardtraderPrice {
  final int blueprintId;
  final String catalog;
  final String expansionCode;
  final String cardNameEn;
  final String language;
  final bool firstEdition;
  final String rarity;

  /// CardTrader collector number (e.g. "EN006", "001").
  /// Used to disambiguate alternate-art cards that share the same
  /// name, set, rarity, and language.
  final String collectorNumber;

  /// Minimum Near Mint price in euro cents. Null = no NM listings found.
  final int? minPriceNmCents;

  /// Minimum price of any condition in euro cents.
  final int? minPriceAnyCents;

  final int listingCount;
  final String syncedAt;

  const CardtraderPrice({
    required this.blueprintId,
    required this.catalog,
    required this.expansionCode,
    required this.cardNameEn,
    required this.language,
    required this.firstEdition,
    this.rarity = '',
    this.collectorNumber = '',
    this.minPriceNmCents,
    this.minPriceAnyCents,
    required this.listingCount,
    required this.syncedAt,
  });

  /// Best price in cents: NM if available, otherwise any condition.
  int? get bestPriceCents => minPriceNmCents ?? minPriceAnyCents;

  /// Formatted price string for display (e.g. "€3.50").
  String get displayPrice {
    final c = bestPriceCents;
    if (c == null) return '—';
    return '€${(c / 100).toStringAsFixed(2)}';
  }

  /// Whether NM price is available.
  bool get hasNmPrice => minPriceNmCents != null;

  /// URL to CardTrader page for this blueprint.
  String get cardtraderUrl => 'https://www.cardtrader.com/cards/$blueprintId';

  DateTime get syncedAtDate => DateTime.tryParse(syncedAt) ?? DateTime(2000);

  Map<String, dynamic> toMap() => {
        'blueprint_id': blueprintId,
        'catalog': catalog,
        'expansion_code': expansionCode,
        'card_name_en': cardNameEn,
        'language': language,
        'first_edition': firstEdition ? 1 : 0,
        'rarity': rarity,
        'collector_number': collectorNumber,
        'min_price_nm_cents': minPriceNmCents,
        'min_price_any_cents': minPriceAnyCents,
        'listing_count': listingCount,
        'synced_at': syncedAt,
      };

  factory CardtraderPrice.fromMap(Map<String, dynamic> m) => CardtraderPrice(
        blueprintId: m['blueprint_id'] as int,
        catalog: m['catalog'] as String,
        expansionCode: m['expansion_code'] as String,
        cardNameEn: m['card_name_en'] as String,
        language: m['language'] as String,
        firstEdition: (m['first_edition'] as int? ?? 0) == 1,
        rarity: m['rarity'] as String? ?? '',
        collectorNumber: m['collector_number'] as String? ?? '',
        minPriceNmCents: m['min_price_nm_cents'] as int?,
        minPriceAnyCents: m['min_price_any_cents'] as int?,
        listingCount: m['listing_count'] as int? ?? 0,
        syncedAt: m['synced_at'] as String? ?? '',
      );
}
