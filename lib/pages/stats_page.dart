import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/collection_model.dart';
import '../widgets/banner_ad_widget.dart';
import '../services/app_preferences.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../widgets/collection_value_chart.dart';
import 'set_completion_page.dart';
import 'roi_page.dart';

class StatsPage extends StatefulWidget {
  final String? collectionKey;
  final String? collectionName;

  const StatsPage({super.key, this.collectionKey, this.collectionName});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final DataRepository _dbHelper = DataRepository();
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _rarityStats = [];
  List<CollectionModel> _unlockedCollections = [];
  // '_global' = tutte le collezioni sbloccate; altrimenti la chiave della collezione
  String _filterValue = '_global';
  bool _isLoading = true;
  // false = questa collezione, true = globale (solo quando collectionKey != null)
  bool _chartGlobal = false;
  StreamSubscription<String>? _syncSub;

  String? get _selectedCollectionKey =>
      _filterValue == '_global' ? null : _filterValue;

  String? get _effectiveCollectionKey =>
      widget.collectionKey ?? _selectedCollectionKey;

  String? get _effectiveCollectionName {
    if (widget.collectionName != null) return widget.collectionName;
    if (_selectedCollectionKey == null) return null;
    try {
      return _unlockedCollections
          .firstWhere((c) => c.key == _selectedCollectionKey)
          .name;
    } catch (_) {
      return _selectedCollectionKey;
    }
  }

  void _onCurrencyChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _loadStats();
    AppPreferences.currencyNotifier.addListener(_onCurrencyChanged);
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _loadStats();
    });
  }

  @override
  void dispose() {
    AppPreferences.currencyNotifier.removeListener(_onCurrencyChanged);
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final filterKey   = _effectiveCollectionKey;
    final inHomeMode  = widget.collectionKey == null;

    final futures = <Future>[
      _dbHelper.getGlobalStats(collection: filterKey),
      _dbHelper.getStatsPerRarity(collection: filterKey),
      // Local-only read per evitare allocazioni Firestore in parallelo con SQLite
      if (inHomeMode) _dbHelper.getLocalUnlockedCollections(),
    ];

    final results = await Future.wait(futures);
    _dbHelper.saveCollectionValueSnapshot();

    if (mounted) {
      setState(() {
        _stats       = results[0] as Map<String, dynamic>;
        _rarityStats = results[1] as List<Map<String, dynamic>>;
        if (inHomeMode) {
          _unlockedCollections = results[2] as List<CollectionModel>;
        }
        _isLoading = false;
      });
    }
  }

  static final _collectionColors = {
    'yugioh':   AppColors.yugiohAccent,
    'pokemon':  AppColors.pokemonAccent,
    'onepiece': AppColors.onepieceAccent,
    'magic':    AppColors.magicAccent,
  };

  static const _collectionLogoAssets = {
    'yugioh':            'assets/images/collections/yugioh-logo.png',
    'pokemon':           'assets/images/collections/pokemon-logo.png',
    'magic':             'assets/images/collections/magic-logo.png',
    'onepiece':          'assets/images/collections/one-piece-logo.webp',
    'digimon':           'assets/images/collections/digimon-logo.png',
    'dragon-ball-super': 'assets/images/collections/dragon-ball-super-logo.png',
    'lorcana':           'assets/images/collections/lorcana-logo.png',
    'flesh-and-blood':   'assets/images/collections/flesh-and-blood-logo.png',
    'vanguard':          'assets/images/collections/vanguard-logo.png',
    'star-wars':         'assets/images/collections/star-wars-logo.png',
    'riftbound':         'assets/images/collections/riftbound-logo.png',
    'gundam':            'assets/images/collections/gundam-logo.png',
    'union-arena':       'assets/images/collections/union-arena-logo.png',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.trending_up),
            tooltip: l10n.tooltipRoi,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoiPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadStats,
                      child: ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          // Filtro per collezione — solo in home mode
                          if (widget.collectionKey == null &&
                              _unlockedCollections.isNotEmpty)
                            _buildCollectionFilter(),
                          _buildStatCard(l10n.statsTotalCards, _stats?['totalCards'].toString() ?? '0', Icons.copy_all, Colors.indigo),
                          _buildStatCard(l10n.statsDuplicateCards, _stats?['duplicateCards'].toString() ?? '0', Icons.content_copy, Colors.orange),
                          _buildStatCard(l10n.statsEstimatedValue, CurrencyFormatter.format(_stats?['totalValue'] as double? ?? 0.0), Icons.euro, Colors.green),
                          _buildValueChart(),
                          if (_rarityStats.isNotEmpty) _buildRarityBreakdown(),
                          // Espansioni: quando si è dentro una collezione specifica
                          if (_effectiveCollectionKey != null)
                            _buildExpansioniCard(),
                        ],
                      ),
                    ),
            ),
            if (!kIsWeb) const BannerAdWidget(),
          ],
        ),
      ),
    );
  }

  // ─── Filter bar ──────────────────────────────────────────────────────────────

  Widget _buildCollectionFilter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 2),
          children: [
            _CollectionFilterChip(
              isSelected: _filterValue == '_global',
              accentColor: AppColors.gold,
              onTap: () {
                if (_filterValue != '_global') {
                  setState(() => _filterValue = '_global');
                  _loadStats();
                }
              },
              child: const Icon(Icons.public_rounded, size: 32, color: AppColors.gold),
            ),
            ..._unlockedCollections.map((col) {
              final accent = AppColors.forCollection(col.key);
              final logo   = _collectionLogoAssets[col.key];
              return _CollectionFilterChip(
                isSelected: _filterValue == col.key,
                accentColor: accent,
                onTap: () {
                  if (_filterValue != col.key) {
                    setState(() => _filterValue = col.key);
                    _loadStats();
                  }
                },
                child: logo != null
                    ? Image.asset(logo,
                        fit: BoxFit.contain,
                        cacheWidth: 256)
                    : Icon(Icons.style, size: 28, color: accent),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Chart ───────────────────────────────────────────────────────────────────

  Widget _buildValueChart() {
    final hasCollection = widget.collectionKey != null;
    // In collection mode: rispetta il toggle. In home mode: usa il filtro.
    final String? chartCollection;
    if (hasCollection) {
      chartCollection = _chartGlobal ? null : widget.collectionKey;
    } else {
      chartCollection = _selectedCollectionKey;
    }
    final accentColor = chartCollection != null
        ? (_collectionColors[chartCollection] ?? AppColors.gold)
        : AppColors.gold;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.show_chart_rounded,
                      color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.statsValueTrend,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                // Toggle scope — solo in collection mode (non in home mode con filtro)
                if (hasCollection)
                  _ScopeRow(
                    isGlobal: _chartGlobal,
                    onChanged: (v) => setState(() => _chartGlobal = v),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            CollectionValueChart(
              key: ValueKey('${chartCollection}_$_chartGlobal'),
              collection: chartCollection,
              accentColor: accentColor,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Cards ───────────────────────────────────────────────────────────────────

  Widget _buildRarityBreakdown() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.statsPerRarity, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ..._rarityStats.map((row) {
              final rarity   = row['rarity'] as String? ?? '';
              final count    = (row['count'] as num?)?.toInt() ?? 0;
              final value    = (row['totalValue'] as num?)?.toDouble() ?? 0.0;
              final maxCount = (_rarityStats.first['count'] as num?)?.toInt() ?? 1;
              final ratio    = maxCount > 0 ? count / maxCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(rarity, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                        Text('$count  •  ${CurrencyFormatter.format(value)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.amber,
                      backgroundColor: Colors.amber.withValues(alpha: 0.15),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansioniCard() {
    final collKey  = _effectiveCollectionKey!;
    final collName = _effectiveCollectionName ?? collKey;
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.layers, color: Colors.orange, size: 30),
        ),
        title: Text(AppLocalizations.of(context)!.statsSetsSection, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        subtitle: Text(
          'Completamento set per $collName',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SetCompletionPage(
              collectionKey: collKey,
              collectionName: collName,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Collection filter chip ───────────────────────────────────────────────────

class _CollectionFilterChip extends StatelessWidget {
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  const _CollectionFilterChip({
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  // Stesso beige delle card collezione nella home
  static const _cardBg = Color(0xFFE8DFCC);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 132,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: isSelected ? _cardBg : AppColors.bgLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accentColor
                : AppColors.border.withValues(alpha: 0.5),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: child,
      ),
    );
  }
}

// ─── Scope toggle (Collezione / Globale) ──────────────────────────────────────

class _ScopeRow extends StatelessWidget {
  final bool isGlobal;
  final ValueChanged<bool> onChanged;
  const _ScopeRow({required this.isGlobal, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleChip(
          label: l10n.statsTabCollection,
          active: !isGlobal,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 4),
        _ToggleChip(
          label: l10n.statsTabGlobal,
          active: isGlobal,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gold.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? AppColors.gold
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? AppColors.gold : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
