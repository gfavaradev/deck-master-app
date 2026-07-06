import '../utils/currency_formatter.dart';
import 'database_helper.dart';

/// CardTrader API integration for real marketplace price data.
///
/// Supported collections and their CardTrader game IDs:
///   'yugioh'   → 4
///   'pokemon'  → 5
///   'onepiece' → 15
class CardtraderService {
  // Available languages per catalog (CardTrader language codes).
  // Note: CardTrader uses 'es' for Spanish (YGO uses 'sp' internally).
  static const _catalogLanguages = <String, Map<String, String>>{
    'yugioh': {
      'en': 'Inglese',
      'it': 'Italiano',
      'fr': 'Francese',
      'de': 'Tedesco',
      'pt': 'Portoghese',
      'es': 'Spagnolo',
    },
    'pokemon': {
      'en': 'Inglese',
      'ja': 'Giapponese',
      'fr': 'Francese',
      'de': 'Tedesco',
      'it': 'Italiano',
      'es': 'Spagnolo',
      'pt': 'Portoghese',
      'ko': 'Coreano',
    },
    'onepiece': {
      'ja': 'Giapponese',
      'en': 'Inglese',
      'fr': 'Francese',
      'zh': 'Cinese',
      'ko': 'Coreano',
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
      case 'jp':
        return 'ja';
      case 'kr':
        return 'ko';
      case 'zh-cn':
        return 'zh';
      default:
        return ctLang.toLowerCase();
    }
  }

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

  final DatabaseHelper _db;

  CardtraderService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

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
    return CardtraderPrice.fromMap(row);
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
    if (rows.isNotEmpty) return rows.map(CardtraderPrice.fromMap).toList();

    // Fallback: read prices embedded in catalog prints tables (no CT sync needed)
    final fallback = await _db.getCatalogPricesForCard(
      catalog: catalog,
      cardName: cardName,
      catalogId: catalogId,
      serialNumber: collectorNumber,
    );
    return fallback.map(CardtraderPrice.fromMap).toList();
  }

  /// Aggiorna i prezzi del catalogo dai prezzi CT in cache locale.
  /// Returns the number of catalog print rows updated.
  Future<int> applyLocalPricesToCollection(String catalog) async {
    return await _db.syncCatalogPricesFromCardtrader(catalog);
  }

  /// Returns daily price snapshots for a card, ordered by date ascending.
  /// Returns an empty list if the card has no history or the blueprint is unknown.
  Future<List<Map<String, dynamic>>> getCardPriceHistory({
    required String catalog,
    required String expansionCode,
    required String cardName,
    required String language,
    String? rarity,
    String? collectorNumber,
    String? catalogId,
    required DateTime from,
  }) async {
    final price = await getPriceForCard(
      catalog: catalog,
      expansionCode: expansionCode,
      cardName: cardName,
      language: language,
      rarity: rarity,
      collectorNumber: collectorNumber,
      catalogId: catalogId,
    );
    if (price == null) return [];
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    return _db.getPriceHistory(
      blueprintId: price.blueprintId,
      language: price.language,
      firstEdition: price.firstEdition ? 1 : 0,
      rarity: price.rarity,
      from: fromStr,
    );
  }
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
  String get displayPrice => CurrencyFormatter.formatCents(bestPriceCents);

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
