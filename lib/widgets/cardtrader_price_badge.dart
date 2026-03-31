import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cardtrader_service.dart';
import '../theme/app_colors.dart';

// ─── Multi-language prices section ────────────────────────────────────────────

/// Shows all available CardTrader prices for a card, one row per language.
/// Intended for use in card detail dialogs/sheets.
class CardtraderAllPricesSection extends StatefulWidget {
  final String collection;
  final String serialNumber;
  final String cardName;
  final String? rarity;

  const CardtraderAllPricesSection({
    super.key,
    required this.collection,
    required this.serialNumber,
    required this.cardName,
    this.rarity,
  });

  @override
  State<CardtraderAllPricesSection> createState() =>
      _CardtraderAllPricesSectionState();
}

class _CardtraderAllPricesSectionState
    extends State<CardtraderAllPricesSection> {
  final _service = CardtraderService();
  late final Future<List<CardtraderPrice>> _future;

  static String _expansionCode(String sn) =>
      sn.isEmpty ? '' : sn.split('-').first.toLowerCase();

  static String _collectorNumber(String sn) {
    final idx = sn.indexOf('-');
    return idx < 0 ? '' : sn.substring(idx + 1);
  }

  @override
  void initState() {
    super.initState();
    _future = _service.getAllPricesForCard(
      catalog: widget.collection,
      expansionCode: _expansionCode(widget.serialNumber),
      cardName: widget.cardName,
      rarity: widget.rarity,
      collectorNumber: _collectorNumber(widget.serialNumber),
    );
  }

  static const _langLabels = <String, String>{
    'en': 'EN', 'it': 'IT', 'fr': 'FR', 'de': 'DE',
    'es': 'ES', 'pt': 'PT', 'ja': 'JA', 'ko': 'KO', 'zh': 'ZH',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CardtraderPrice>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final prices = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardtraderBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.cardtraderBorder.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 13, color: AppColors.cardtraderTeal),
                  const SizedBox(width: 5),
                  const Text(
                    'Prezzi CardTrader',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cardtraderTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...prices.map(
                (p) => _PriceRow(
                  price: p,
                  langLabel: _langLabels[p.language] ?? p.language.toUpperCase(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PriceRow extends StatelessWidget {
  final CardtraderPrice price;
  final String langLabel;

  const _PriceRow({required this.price, required this.langLabel});

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final isHistorical = price.listingCount == 0;
    final priceColor =
        isHistorical ? Colors.orange : AppColors.cardtraderTeal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              langLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            price.displayPrice,
            style: TextStyle(
              color: priceColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          if (!isHistorical)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: price.hasNmPrice
                    ? const Color(0xFF1A6B5A).withValues(alpha: 0.5)
                    : Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                price.hasNmPrice ? 'NM' : 'ANY',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: price.hasNmPrice
                      ? AppColors.cardtraderTeal
                      : Colors.orange,
                ),
              ),
            ),
          if (price.firstEdition) ...[
            const SizedBox(width: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '1st',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
            ),
          ],
          if (isHistorical) ...[
            const SizedBox(width: 4),
            Text(
              _formatDate(price.syncedAtDate),
              style: TextStyle(
                fontSize: 9,
                color: Colors.orange.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays a cached CardTrader price badge for a card.
///
/// Automatically extracts language and expansion code from [serialNumber].
/// Shows nothing if no price is cached in the local database.
class CardtraderPriceBadge extends StatefulWidget {
  final String collection;
  final String serialNumber;
  final String cardName;
  final String? rarity;

  const CardtraderPriceBadge({
    super.key,
    required this.collection,
    required this.serialNumber,
    required this.cardName,
    this.rarity,
  });

  @override
  State<CardtraderPriceBadge> createState() => _CardtraderPriceBadgeState();
}

class _CardtraderPriceBadgeState extends State<CardtraderPriceBadge> {
  final _service = CardtraderService();
  late final Future<CardtraderPrice?> _priceFuture;

  @override
  void initState() {
    super.initState();
    _priceFuture = _fetchPrice();
  }

  Future<CardtraderPrice?> _fetchPrice() {
    final sn = widget.serialNumber;
    final expansionCode = _extractExpansionCode(sn);
    final language = _extractLanguage(sn, widget.collection);
    final collectorNumber = _extractCollectorNumber(sn);

    return _service.getPriceForCard(
      catalog: widget.collection,
      expansionCode: expansionCode,
      cardName: widget.cardName,
      language: language,
      rarity: widget.rarity,
      collectorNumber: collectorNumber,
    );
  }

  /// Extracts expansion code from serial number.
  /// Examples: "LOB-EN001" → "lob", "swsh1-1" → "swsh1", "OP01-001" → "op01"
  static String _extractExpansionCode(String sn) {
    if (sn.isEmpty) return '';
    return sn.split('-').first.toLowerCase();
  }

  /// Extracts the collector number from the serial number.
  /// Examples: "MAGO-EN006" → "EN006", "swsh1-1" → "1", "OP01-001" → "001"
  static String _extractCollectorNumber(String sn) {
    final idx = sn.indexOf('-');
    if (idx < 0) return '';
    return sn.substring(idx + 1);
  }

  /// Detects language code from serial number.
  ///
  /// YuGiOh: "LOB-EN001" → "en", "LOB-IT001" → "it", "LOB-SP001" → "es" (CardTrader uses "es")
  /// Pokemon/OnePiece: defaults to "en" (these use set codes without language suffix)
  static String _extractLanguage(String sn, String collection) {
    if (collection == 'yugioh') {
      final match = RegExp(r'-([A-Za-z]{2})\d').firstMatch(sn);
      if (match != null) {
        final code = match.group(1)!.toLowerCase();
        // CardTrader uses "es" for Spanish, YGO uses "sp"
        return code == 'sp' ? 'es' : code;
      }
    }
    return 'en';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CardtraderPrice?>(
      future: _priceFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
        final price = snapshot.data!;
        return _PriceBadge(price: price);
      },
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final CardtraderPrice price;
  const _PriceBadge({required this.price});

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final isNm = price.hasNmPrice;
    final isHistorical = price.listingCount == 0; // no active listings

    // Historical prices use a muted colour so users understand it's stale.
    const activeColor = AppColors.cardtraderTeal;
    const historicalColor = Colors.orange;
    final priceColor = isHistorical ? historicalColor : activeColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardtraderBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHistorical
              ? Colors.orange.withValues(alpha: 0.5)
              : AppColors.cardtraderBorder.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHistorical ? Icons.history : Icons.storefront_outlined,
            size: 14,
            color: priceColor,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      price.displayPrice,
                      style: TextStyle(
                        color: priceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (!isHistorical)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isNm
                              ? const Color(0xFF1A6B5A).withValues(alpha: 0.5)
                              : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          isNm ? 'NM' : 'ANY',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isNm ? const Color(0xFF4ECDC4) : Colors.orange,
                          ),
                        ),
                      ),
                    if (price.firstEdition) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '1st',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (isHistorical)
                  Text(
                    'Ultimo: ${_formatDate(price.syncedAtDate)}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.orange,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(price.cardtraderUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text(
                      'CardTrader ↗',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF4ECDC4),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF4ECDC4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
