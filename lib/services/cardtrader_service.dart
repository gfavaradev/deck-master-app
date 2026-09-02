import '../utils/currency_formatter.dart';
import 'database_helper.dart';
import 'price_repository.dart';
import 'print_id.dart';

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
  final PriceRepository _prices;

  CardtraderService({DatabaseHelper? db, PriceRepository? prices})
      : _db = db ?? DatabaseHelper(),
        _prices = prices ?? PriceRepository();

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
    String? serialNumber,
  }) async {
    // Percorso nuovo: il prezzo e' gia' agganciato alla stampa dal worker,
    // quindi basta risolvere il printId e leggere una riga per chiave primaria
    // — nessun matching per nome, nessuna scansione. Se la stampa non e'
    // risolvibile o il prezzo non c'e' ancora, si ricade sul percorso storico.
    // Vedi REQUIREMENTS_prices_unified.md.
    final unified = await _unifiedPrice(
      catalog: catalog,
      catalogId: catalogId,
      serialNumber: serialNumber ?? collectorNumber,
      rarity: rarity,
      language: language,
    );
    if (unified != null) return unified;

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
    if (row != null) return CardtraderPrice.fromMap(row);

    // Terzo percorso: i prezzi incorporati nelle tabelle di stampa del
    // catalogo. Lo aveva solo [getAllPricesForCard], ed e' il motivo per cui la
    // stessa carta mostrava "N/D" in lista e un valore di mercato in scheda:
    // due funzioni con un numero diverso di ripieghi, quindi due insiemi
    // disgiunti di cataloghi con il prezzo. Un solo percorso, un solo esito.
    final embedded = await _db.getCatalogPricesForCard(
      catalog: catalog,
      cardName: cardName,
      catalogId: catalogId,
      serialNumber: collectorNumber ?? serialNumber,
    );
    if (embedded.isEmpty) return null;
    return CardtraderPrice.fromMap(_preferLanguage(embedded, language));
  }

  /// La riga nella lingua richiesta; in mancanza l'inglese, poi la prima.
  ///
  /// Le righe di `card_prices` chiamano la colonna `lang`, quelle del percorso
  /// storico `language`: si accettano entrambe perche' questa scelta serve a
  /// tutti e tre i percorsi prezzo.
  static Map<String, dynamic> _preferLanguage(
    List<Map<String, dynamic>> rows,
    String language,
  ) {
    String langOf(Map<String, dynamic> r) =>
        ((r['lang'] ?? r['language']) as String? ?? '').toLowerCase();
    final wanted = language.toLowerCase();
    for (final r in rows) {
      if (langOf(r) == wanted) return r;
    }
    for (final r in rows) {
      if (langOf(r) == 'en') return r;
    }
    return rows.first;
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
    String? serialNumber,
  }) async {
    // Percorso nuovo: una riga per lingua, tutte sotto lo stesso printId.
    final printId = await _db.resolvePrintId(
      catalog: catalog,
      catalogId: catalogId,
      serialNumber: serialNumber ?? collectorNumber,
      rarity: rarity,
    );
    if (printId.isNotEmpty) {
      final unified = await _db.getUnifiedPricesForPrint(
        catalog: catalog,
        printId: printId,
      );
      if (unified.isNotEmpty) {
        return unified
            .map((r) => _fromUnifiedRow(r, catalog: catalog, cardName: cardName))
            .toList();
      }
    }

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

  /// Cerca il prezzo nella tabella unificata `card_prices`, risolvendo prima il
  /// printId. Restituisce null se la stampa non e' risolvibile o se il prezzo
  /// non e' ancora stato scaricato: in quel caso il chiamante usa il percorso
  /// storico, cosi' il passaggio non fa sparire prezzi gia' visibili.
  Future<CardtraderPrice?> _unifiedPrice({
    required String catalog,
    required String? catalogId,
    required String? serialNumber,
    required String? rarity,
    required String language,
  }) async {
    final printId = await _db.resolvePrintId(
      catalog: catalog,
      catalogId: catalogId,
      serialNumber: serialNumber,
      rarity: rarity,
    );
    if (printId.isEmpty) return null;
    final row = await _db.getUnifiedPrice(
      catalog: catalog,
      printId: printId,
      lang: language,
    );
    if (row != null) return _fromUnifiedRow(row, catalog: catalog, cardName: '');

    // Nessun prezzo in QUELLA lingua: si ripiega su un'altra stampa dello
    // stesso printId invece di dire "N/D". Serve da quando il worker etichetta
    // i prezzi con la lingua vera dell'inserzione: prima finivano tutti in
    // "en", e una carta italiana trovava per caso il prezzo giusto. La lingua
    // effettiva resta nel modello, che la scheda carta mostra.
    final all = await _db.getUnifiedPricesForPrint(
      catalog: catalog,
      printId: printId,
    );
    if (all.isEmpty) return null;
    return _fromUnifiedRow(
      _preferLanguage(all, language),
      catalog: catalog,
      cardName: '',
    );
  }

  /// Adatta una riga di `card_prices` al modello che la UI gia' conosce.
  ///
  /// `blueprintId` resta valorizzato solo per gli 11 cataloghi in cui il printId
  /// E' il blueprint CardTrader: e' cio' che alimenta il link a cardtrader.com.
  /// Per yugioh e magic il printId e' composito e il link non e' derivabile,
  /// quindi vale 0 e il bottone si comporta come per una carta senza blueprint.
  static CardtraderPrice _fromUnifiedRow(
    Map<String, dynamic> row, {
    required String catalog,
    required String cardName,
  }) {
    final printId = row['print_id'] as String? ?? '';
    return CardtraderPrice(
      blueprintId: int.tryParse(printIdFromBlueprint(catalog, printId)) ?? 0,
      catalog: catalog,
      expansionCode: row['set_code'] as String? ?? '',
      cardNameEn: cardName,
      language: row['lang'] as String? ?? 'en',
      firstEdition: false,
      rarity: '',
      collectorNumber: '',
      minPriceNmCents: row['nm_cents'] as int?,
      minPriceAnyCents: row['any_cents'] as int?,
      listingCount: row['listings'] as int? ?? 0,
      syncedAt: row['updated_at'] as String? ?? '',
      printId: printId,
    );
  }

  /// Aggiorna i prezzi del catalogo dai prezzi CT in cache locale.
  /// Returns the number of catalog print rows updated.
  ///
  /// [onProgress] riceve 0.0→1.0 sull'avanzamento delle passate di match: è il
  /// passo più lungo di un download di catalogo e senza di esso la UI resta
  /// ferma al 100% finché non finisce.
  Future<int> applyLocalPricesToCollection(
    String catalog, {
    void Function(double progress)? onProgress,
  }) async {
    return await _db.syncCatalogPricesFromCardtrader(
      catalog,
      onProgress: onProgress,
    );
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
    String? serialNumber,
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
      serialNumber: serialNumber,
    );
    if (price == null) return [];

    // Storico condiviso su RTDB: vale per tutti gli utenti e copre anche il
    // periodo precedente all'installazione, mentre `price_history` in SQLite
    // parte dal primo sync su QUESTO dispositivo e riparte da zero a ogni
    // reinstallazione.
    if (price.printId.isNotEmpty) {
      final points = await _prices.fetchHistory(catalog, price.printId);
      final filtered = points.where((p) => !p.date.isBefore(from));
      if (filtered.isNotEmpty) {
        return [
          for (final p in filtered)
            {
              'recorded_date': _isoDate(p.date),
              'price_cents': p.cents,
              'listing_count': 0,
            },
        ];
      }
    }

    final fromStr = _isoDate(from);
    return _db.getPriceHistory(
      blueprintId: price.blueprintId,
      language: price.language,
      firstEdition: price.firstEdition ? 1 : 0,
      rarity: price.rarity,
      from: fromStr,
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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

  /// Chiave di stampa del percorso unificato (vedi `print_id.dart`). Vuota per
  /// le righe che arrivano ancora dal percorso storico.
  final String printId;

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
    this.printId = '',
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
