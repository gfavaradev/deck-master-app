import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/banner_ad_widget.dart';
import '../services/app_preferences.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_dialog.dart';
import '../widgets/collection_value_chart.dart';

class RoiPage extends StatefulWidget {
  const RoiPage({super.key});

  @override
  State<RoiPage> createState() => _RoiPageState();
}

class _RoiPageState extends State<RoiPage> {
  final _repo = DataRepository();

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;
  String? _filterCollection;

  void _onCurrencyChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _load();
    AppPreferences.currencyNotifier.addListener(_onCurrencyChanged);
  }

  @override
  void dispose() {
    AppPreferences.currencyNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _repo.getRoiSummary(),
      _repo.getRoiCardList(collection: _filterCollection),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as Map<String, dynamic>;
      _cards = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _editPurchasePrice(Map<String, dynamic> card) async {
    final currentPriceEur = (card['purchase_price'] as num?)?.toDouble();
    // Pre-fill in the user's selected currency
    final displayPrice = currentPriceEur != null
        ? CurrencyFormatter.fromEuros(currentPriceEur).toStringAsFixed(2)
        : '';
    final ctrl = TextEditingController(text: displayPrice);

    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.roiPurchasePriceTitle,
        icon: Icons.euro,
        iconColor: AppColors.gold,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card['name']?.toString() ?? '',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            if ((card['serialNumber']?.toString() ?? '').isNotEmpty)
              Text(
                card['serialNumber'].toString(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.roiPurchasePriceLabel,
                border: const OutlineInputBorder(),
                prefixText: CurrencyFormatter.prefixText,
                helperText: l10n.roiPurchasePriceHelper,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.btnCancel),
          ),
          if (currentPriceEur != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Text(l10n.btnDelete, style: const TextStyle(color: AppColors.error)),
            ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (val == null) return;
              Navigator.pop(ctx, val);
            },
            child: Text(l10n.btnSave),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (result == null) return;
    // Convert from selected currency back to EUR for storage
    final priceEur = result < 0 ? null : CurrencyFormatter.toEuros(result);
    await _repo.updateCardPurchasePrice(card['id'] as int, priceEur);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.roiTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.gold,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildPortfolioSection()),
                        SliverToBoxAdapter(child: _buildRoiSummarySection()),
                        SliverToBoxAdapter(child: _buildCardListHeader()),
                        if (_cards.isEmpty)
                          SliverToBoxAdapter(child: _buildEmptyRoi())
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _buildCardTile(_cards[i]),
                              childCount: _cards.length,
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ),
                  ),
          ),
          if (!kIsWeb) const BannerAdWidget(),
        ],
      ),
    );
  }

  Widget _buildPortfolioSection() {
    final currentValue = (_summary['currentValue'] as num?)?.toDouble() ?? 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.roiPortfolio,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: AppLocalizations.of(context)!.roiTotalValue,
                  value: CurrencyFormatter.format(currentValue),
                  color: AppColors.gold,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const CollectionValueChart(accentColor: AppColors.gold),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRoiSummarySection() {
    final invested = (_summary['totalInvested'] as num?)?.toDouble() ?? 0.0;
    final ownedValue = (_summary['ownedValue'] as num?)?.toDouble() ?? 0.0;
    final gain = (_summary['gain'] as num?)?.toDouble() ?? 0.0;
    final roiPct = (_summary['roiPct'] as num?)?.toDouble() ?? 0.0;

    if (invested == 0) return const SizedBox.shrink();

    final gainColor = gain >= 0 ? AppColors.success : AppColors.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.roiSection,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(label: AppLocalizations.of(context)!.roiInvested, value: CurrencyFormatter.format(invested), color: AppColors.blue, icon: Icons.payments_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(label: AppLocalizations.of(context)!.roiValueCt, value: CurrencyFormatter.format(ownedValue), color: AppColors.cardtraderTeal, icon: Icons.trending_up)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                label: AppLocalizations.of(context)!.roiGain,
                value: CurrencyFormatter.formatSigned(gain),
                color: gainColor,
                icon: gain >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                label: AppLocalizations.of(context)!.roiPercent,
                value: '${roiPct >= 0 ? '+' : ''}${roiPct.toStringAsFixed(1)}%',
                color: gainColor,
                icon: Icons.percent,
              )),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCardListHeader() {
    final cardCount = (_summary['cardCount'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Text(AppLocalizations.of(context)!.roiTrackedCards,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12, letterSpacing: 1.2)),
          const Spacer(),
          if (cardCount > 0)
            Text(
              AppLocalizations.of(context)!.statsCardsCount(cardCount),
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyRoi() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.euro_outlined, size: 60, color: AppColors.textHint),
          const SizedBox(height: 16),
          const Text(
            'Nessun prezzo d\'acquisto impostato',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Tocca il pulsante "+" su una carta per inserire\nil prezzo che hai pagato e calcolare il tuo ROI.',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _buildSetPricePrompt(),
        ],
      ),
    );
  }

  Widget _buildSetPricePrompt() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _repo.getRoiCardList(limit: 3),
      builder: (ctx, snap) {
        // Already shown with purchase prices — nothing to suggest
        if (snap.hasData && snap.data!.isNotEmpty) return const SizedBox.shrink();

        return FutureBuilder<List<dynamic>>(
          future: _repo.getStatsPerCollection(),
          builder: (ctx2, snap2) {
            if (!snap2.hasData || snap2.data!.isEmpty) return const SizedBox.shrink();
            final collections = snap2.data!.cast<Map<String, dynamic>>();
            return Column(
              children: collections.take(3).map((c) {
                final key = c['collection']?.toString() ?? '';
                final label = _collectionLabel(key);
                final color = AppColors.forCollection(key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _loadCardsForCollection(key),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(AppLocalizations.of(ctx2)!.roiAddPricesBtn(label)),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Future<void> _loadCardsForCollection(String collection) async {
    setState(() { _filterCollection = collection; });
    await _load();
  }

  Widget _buildCardTile(Map<String, dynamic> card) {
    final name = card['name']?.toString() ?? '';
    final serial = card['serialNumber']?.toString() ?? '';
    final collection = card['collection']?.toString() ?? '';
    final quantity = (card['quantity'] as num?)?.toInt() ?? 1;
    final purchasePrice = (card['purchase_price'] as num?)?.toDouble() ?? 0.0;
    final currentPrice = (card['current_price'] as num?)?.toDouble() ?? 0.0;
    final gainEuros = (card['gain_euros'] as num?)?.toDouble() ?? 0.0;
    final roiPct = (card['roi_pct'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = card['imageUrl']?.toString();
    final color = AppColors.forCollection(collection);
    final gainColor = gainEuros >= 0 ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _editPurchasePrice(card),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(imageUrl, width: 38, height: 54, fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => _imgPlaceholder(color))
                    : _imgPlaceholder(color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (serial.isNotEmpty)
                      Text(serial, style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Pagato: ${CurrencyFormatter.format(purchasePrice)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(width: 8),
                        Text('CT: ${CurrencyFormatter.format(currentPrice)}',
                            style: const TextStyle(color: AppColors.cardtraderTeal, fontSize: 11)),
                        if (quantity > 1) ...[
                          const SizedBox(width: 6),
                          Text('×$quantity', style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatSigned(gainEuros),
                    style: TextStyle(color: gainColor, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${roiPct >= 0 ? '+' : ''}${roiPct.toStringAsFixed(1)}%',
                    style: TextStyle(color: gainColor, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imgPlaceholder(Color color) => Container(
        width: 38,
        height: 54,
        color: color.withValues(alpha: 0.15),
        child: Icon(Icons.style, color: color.withValues(alpha: 0.4), size: 18),
      );

  String _collectionLabel(String key) => switch (key) {
    'yugioh'   => 'Yu-Gi-Oh!',
    'pokemon'  => 'Pokémon',
    'onepiece' => 'One Piece',
    _          => key,
  };
}

// ─── KPI Card ──────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _KpiCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
                Text(value,
                    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
