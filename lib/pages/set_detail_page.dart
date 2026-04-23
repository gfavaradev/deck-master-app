import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cardtrader_price_badge.dart';

class SetDetailPage extends StatefulWidget {
  final String collectionKey;
  final String collectionName;
  final String setIdentifier; // set_name (YGO), set_id (OP), setName (generico)
  final String setName;       // nome display
  final int totalCards;
  final int ownedCards;

  const SetDetailPage({
    super.key,
    required this.collectionKey,
    required this.collectionName,
    required this.setIdentifier,
    required this.setName,
    required this.totalCards,
    required this.ownedCards,
  });

  @override
  State<SetDetailPage> createState() => _SetDetailPageState();
}

class _SetDetailPageState extends State<SetDetailPage> with SingleTickerProviderStateMixin {
  final DataRepository _repo = DataRepository();
  late final TabController _tabController;

  List<Map<String, dynamic>> _allCards = [];
  List<Map<String, dynamic>> _ownedCards = [];
  List<Map<String, dynamic>> _missingCards = [];
  bool _isLoading = true;
  String _lang = 'en';
  StreamSubscription<String>? _syncSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCards();
    LanguageService.getPreferredLanguageForCollection(widget.collectionKey).then((l) {
      if (mounted && l.toLowerCase() != _lang) {
        _lang = l.toLowerCase();
        _loadCards();
      }
    });
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _loadCards();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final data = await _repo.getSetDetail(widget.collectionKey, widget.setIdentifier, lang: _lang);
    if (!mounted) return;
    setState(() {
      _allCards = data;
      _ownedCards = data.where((c) => (c['isOwned'] as int?) == 1).toList();
      _missingCards = data.where((c) => (c['isOwned'] as int?) == 0).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final owned = widget.ownedCards;
    final total = widget.totalCards;
    final pct = total > 0 ? owned / total : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.setName, style: const TextStyle(fontSize: 16)),
            Text(
              '$owned / $total carte  •  ${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.gold,
          tabs: [
            Tab(text: 'Tutte (${_allCards.length})'),
            Tab(text: 'Possedute (${_ownedCards.length})'),
            Tab(text: 'Mancanti (${_missingCards.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_allCards),
                    _buildList(_ownedCards),
                    _buildList(_missingCards),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> cards) {
    if (cards.isEmpty) {
      return const Center(
        child: Text('Nessuna carta.', style: TextStyle(color: AppColors.textHint)),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 600;
      final thumbW = isWide ? 66.0 : 44.0;
      final thumbH = isWide ? 90.0 : 60.0;
      return ListView.builder(
      itemCount: cards.length,
      itemBuilder: (_, index) {
        final card = cards[index];
        final isOwned = (card['isOwned'] as int?) == 1;
        final imageUrl = card['imageUrl'] as String?;
        final name = card['name'] as String? ?? '';
        final serial = card['serialNumber'] as String? ?? '';
        final rarity = card['rarity'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isOwned
                ? Colors.green.withValues(alpha: 0.08)
                : Colors.red.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOwned
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.2),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: SizedBox(
              width: thumbW,
              height: thumbH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 132,
                        memCacheHeight: 180,
                        placeholder: (ctx, url) => Container(color: AppColors.bgLight),
                        errorWidget: (ctx, url, err) => const Icon(Icons.image_not_supported, color: AppColors.textHint, size: 20),
                      )
                    : Container(
                        color: AppColors.bgLight,
                        child: const Icon(Icons.style, color: AppColors.textHint, size: 20),
                      ),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  serial.isNotEmpty && rarity.isNotEmpty
                      ? '$serial  •  $rarity'
                      : serial.isNotEmpty ? serial : rarity,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                if (isOwned && serial.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  CardtraderPriceBadge(
                    collection: widget.collectionKey,
                    serialNumber: serial,
                    cardName: name,
                    rarity: rarity.isNotEmpty ? rarity : null,
                    catalogId: card['id']?.toString(),
                  ),
                ],
              ],
            ),
            trailing: Icon(
              isOwned ? Icons.check_circle : Icons.cancel,
              color: isOwned ? Colors.green : Colors.red.withValues(alpha: 0.7),
              size: 22,
            ),
          ),
        );
      },
    );
    });
  }
}
