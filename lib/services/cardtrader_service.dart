import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'database_helper.dart';
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
      'zh': 'Cinese', 'ko': 'Coreano',
    },
  };

  /// Returns the language code→label map for [catalog].
  static Map<String, String> languagesForCatalog(String catalog) =>
      _catalogLanguages[catalog] ?? {};

  String get _jwt => dotenv.env['CARDTRADER_JWT'] ?? '';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_jwt',
        'Accept': 'application/json',
        'Accept-Encoding': 'identity', // prevent gzip so json.decode works
      };

  final DatabaseHelper _db;

  CardtraderService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  // ─── Public sync API ───────────────────────────────────────────────────────

  /// Syncs prices for the given [catalog] and [language].
  ///
  /// Steps:
  ///   1. Fetch all CT expansions for this game.
  ///   2. Match against locally-known set codes (set_id column).
  ///   3. For each matched expansion:
  ///      a. Fetch all /blueprints → seed DB rows for [language] (no price yet).
  ///      b. Fetch /marketplace/products → upsert prices for active listings.
  ///   4. Update card collection values from the new prices.
  ///
  /// Returns a summary map: {expansions, blueprints, pricedBlueprints, skipped, errors}.
  Future<Map<String, dynamic>> syncPrices({
    required String catalog,
    required String adminUid,
    required void Function(String msg, double? progress) onProgress,
    required String language,
  }) async {
    final gameId = gameIds[catalog];
    if (gameId == null) throw Exception('Catalogo non supportato: $catalog');
    if (_jwt.isEmpty) {
      throw Exception('CARDTRADER_JWT non configurato nel file .env');
    }

    final langLower = language.toLowerCase();

    onProgress('Caricamento espansioni CardTrader…', null);
    final ctExpansions = await _fetchExpansions(gameId);

    onProgress('Caricamento set locali…', null);
    final localCodes = await _db.getDistinctSetCodesForCardtrader(catalog);

    // Match CT codes (lowercase) against local set_id codes (lowercase)
    final matched = ctExpansions.where((e) {
      final code = (e['code'] as String? ?? '').toLowerCase();
      return localCodes.contains(code);
    }).toList();

    debugPrint('[CardTrader] ${ctExpansions.length} CT expansions, '
        '${localCodes.length} local codes, ${matched.length} matched, '
        'language=$langLower');

    int totalBlueprints = 0;  // blueprints seeded (from /blueprints endpoint)
    int pricedBlueprints = 0; // blueprints with active marketplace listings
    int skipped = 0;
    int errors = 0;

    for (int i = 0; i < matched.length; i++) {
      final exp = matched[i];
      final expId = exp['id'] as int;
      final expCode = (exp['code'] as String).toLowerCase();
      final expName = exp['name'] as String? ?? expCode;

      onProgress(
        '$expName ($expCode) — ${i + 1}/${matched.length}',
        (i + 1) / matched.length,
      );

      try {
        // ── Step a: seed all blueprints for this language ─────────────────
        final blueprints = await _fetchBlueprints(expId);
        final langBlueprints = _filterBlueprintsByLanguage(
            blueprints, catalog, langLower);
        if (langBlueprints.isNotEmpty) {
          await _db.insertBlueprintsIfAbsent(
              _buildBlueprintMaps(catalog, expCode, langBlueprints, langLower));
          totalBlueprints += langBlueprints.length;
        }
        await Future.delayed(const Duration(milliseconds: 150));

        // ── Step b: fetch marketplace listings and update prices ───────────
        final products = await _fetchMarketplaceProducts(expId);
        if (products.isEmpty) {
          skipped++;
        } else {
          final priced = await _storePrices(
              catalog, expCode, products, language: langLower);
          pricedBlueprints += priced;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('[CardTrader] Error syncing $expCode: $e');
        errors++;
      }
    }

    onProgress('Aggiornamento valori collezione…', null);
    final valuesUpdated = await _db.syncCollectionValuesFromCardtrader(catalog);
    if (valuesUpdated > 0) {
      SyncService().notifyLocalChange('cards');
    }

    return {
      'success': true,
      'expansions': matched.length,
      'blueprints': totalBlueprints,
      'pricedBlueprints': pricedBlueprints,
      'skipped': skipped,
      'errors': errors,
      'catalog': catalog,
      'language': langLower,
      'valuesUpdated': valuesUpdated,
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
  }) async {
    final row = await _db.getCardtraderPrice(
      catalog: catalog,
      expansionCode: expansionCode.toLowerCase(),
      cardName: cardName,
      language: language.toLowerCase(),
      firstEdition: firstEdition,
      rarity: rarity,
      collectorNumber: collectorNumber,
    );
    if (row == null) return null;
    return CardtraderPrice.fromMap(row as Map<String, dynamic>);
  }

  /// Ricalcola `cards.value` dai prezzi CT già in cache locale senza chiamate API.
  /// Utile dopo un riavvio o un sync Firestore che ha azzerato i valori.
  Future<int> applyLocalPricesToCollection(String catalog) async {
    final updated = await _db.syncCollectionValuesFromCardtrader(catalog);
    if (updated > 0) SyncService().notifyLocalChange('cards');
    return updated;
  }

  // ─── HTTP helpers ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchExpansions(int gameId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/expansions'), headers: _headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Errore fetch espansioni: HTTP ${response.statusCode}\n${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    dynamic all;
    try {
      all = json.decode(response.body);
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      throw Exception('Errore parsing blueprints: $e');
    }
    if (raw is! List) return [];
    return raw.cast<Map<String, dynamic>>();
  }

  /// Filters [blueprints] to only those matching [language] for [catalog].
  /// CardTrader stores language in `fixed_properties` (blueprints endpoint)
  /// or `properties_hash` (products endpoint).
  List<Map<String, dynamic>> _filterBlueprintsByLanguage(
    List<Map<String, dynamic>> blueprints,
    String catalog,
    String language,
  ) {
    final langKey = _langKeys[catalog] ?? 'yugioh_language';
    return blueprints.where((b) {
      final props = (b['fixed_properties'] as Map<String, dynamic>?) ??
          (b['properties_hash'] as Map<String, dynamic>?) ??
          {};
      final bpLang = (props[langKey] as String? ?? 'en').toLowerCase();
      return bpLang == language;
    }).toList();
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
  /// endpoint, filtered to [language]. Upserts price rows and returns the
  /// number of blueprints that had at least one listing.
  Future<int> _storePrices(
    String catalog,
    String expansionCode,
    Map<String, List<Map<String, dynamic>>> products, {
    required String language,
  }) async {
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

      // Group listings: key = 'lang|first_edition(0|1)|rarity'
      final nmPrices = <String, List<int>>{};
      final anyPrices = <String, List<int>>{};
      final rarityByKey = <String, String>{};

      for (final listing in listings) {
        final ph = listing['properties_hash'] as Map<String, dynamic>? ?? {};
        final lang = (ph[langKey] as String? ?? 'en').toLowerCase();
        if (lang != language) continue; // only process target language
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
