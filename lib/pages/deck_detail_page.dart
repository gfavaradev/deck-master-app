import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import 'card_detail_page.dart';

class DeckDetailPage extends StatefulWidget {
  final int deckId;
  final String deckName;
  final String collectionKey;

  const DeckDetailPage({
    super.key,
    required this.deckId,
    required this.deckName,
    required this.collectionKey,
  });

  @override
  State<DeckDetailPage> createState() => _DeckDetailPageState();
}

class _DeckDetailPageState extends State<DeckDetailPage> {
  final DataRepository _repo = DataRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _deckCards = [];
  List<CardModel> _ownedCards = [];
  List<CardModel> _filteredOwned = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _repo.getDeckCards(widget.deckId),
      _repo.getCardsByCollection(widget.collectionKey),
    ]);
    if (!mounted) return;
    final owned = results[1] as List<CardModel>;
    setState(() {
      _deckCards = results[0] as List<Map<String, dynamic>>;
      _ownedCards = owned;
      _filteredOwned = owned;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      _repo.getDeckCards(widget.deckId),
      _repo.getCardsByCollection(widget.collectionKey),
    ]);
    if (!mounted) return;
    final owned = results[1] as List<CardModel>;
    setState(() {
      _deckCards = results[0] as List<Map<String, dynamic>>;
      _ownedCards = owned;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredOwned = query.isEmpty
          ? _ownedCards
          : _ownedCards.where((c) {
              return c.name.toLowerCase().contains(query) ||
                  c.serialNumber.toLowerCase().contains(query);
            }).toList();
    });
  }

  Future<void> _addToDeck(CardModel card) async {
    await _repo.addCardToDeck(widget.deckId, card.id!, 1);
    _refresh();
  }

  Future<void> _decrementFromDeck(Map<String, dynamic> deckCard) async {
    await _repo.decrementCardInDeck(widget.deckId, deckCard['id'] as int);
    _refresh();
  }

  void _navigateToDetail(CardModel card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CardDetailPage(
          cards: [card],
          initialIndex: 0,
          onDelete: (_) {},
        ),
      ),
    );
  }

  CardModel? _findOwnedCard(int cardId) {
    try {
      return _ownedCards.firstWhere((c) => c.id == cardId);
    } catch (_) {
      return null;
    }
  }

  int _getQtyInDeck(int cardId) {
    for (final c in _deckCards) {
      if (c['id'] == cardId) return c['deckQuantity'] as int? ?? 1;
    }
    return 0;
  }

  int get _totalDeckCards =>
      _deckCards.fold(0, (sum, c) => sum + (c['deckQuantity'] as int? ?? 1));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMedium,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.deckName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            Text(
              '$_totalDeckCards carte nel deck',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildDeckSection()),
                Container(height: 0.5, color: AppColors.divider),
                Expanded(child: _buildOwnedSection()),
              ],
            ),
    );
  }

  // ─── Top half: carte nel deck ─────────────────────────────────────────────

  Widget _buildDeckSection() {
    return Column(
      children: [
        _SectionHeader(
          icon: Icons.style_outlined,
          label: 'Nel Deck',
          count: _deckCards.length,
          accentColor: AppColors.blue,
          hint: 'Dettaglio • − per rimuovere',
        ),
        Expanded(
          child: _deckCards.isEmpty
              ? const Center(
                  child: Text(
                    'Nessuna carta — aggiungile\ndalle carte possedute qui sotto',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textHint, fontSize: 13),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(6),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemCount: _deckCards.length,
                  itemBuilder: (_, i) {
                    final card = _deckCards[i];
                    final qty = card['deckQuantity'] as int? ?? 1;
                    final owned = _findOwnedCard(card['id'] as int);
                    return _CardCell(
                      name: card['name'] as String? ?? '',
                      imageUrl: card['imageUrl'] as String?,
                      badge: qty > 1 ? 'x$qty' : null,
                      badgeColor: AppColors.blue,
                      onTap: owned != null ? () => _navigateToDetail(owned) : null,
                      onAction: () => _decrementFromDeck(card),
                      actionIcon: Icons.remove,
                      actionColor: AppColors.error,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Bottom half: carte possedute ────────────────────────────────────────

  Widget _buildOwnedSection() {
    return Column(
      children: [
        _SectionHeader(
          icon: Icons.photo_album_outlined,
          label: 'Possedute',
          count: _filteredOwned.length,
          accentColor: AppColors.success,
          hint: 'Tocca per aggiungere',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cerca carta...',
              hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textHint),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppColors.textHint),
                      onPressed: _searchController.clear,
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: AppColors.bgLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
              ),
            ),
          ),
        ),
        Expanded(
          child: _filteredOwned.isEmpty
              ? const Center(
                  child: Text(
                    'Nessuna carta trovata',
                    style: TextStyle(color: AppColors.textHint, fontSize: 13),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemCount: _filteredOwned.length,
                  itemBuilder: (_, i) {
                    final card = _filteredOwned[i];
                    final qtyInDeck = card.id != null ? _getQtyInDeck(card.id!) : 0;
                    return _CardCell(
                      name: card.name,
                      imageUrl: card.imageUrl,
                      badge: qtyInDeck > 0 ? 'x$qtyInDeck' : null,
                      badgeColor: AppColors.blue,
                      onTap: () => _addToDeck(card),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color accentColor;
  final String hint;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.accentColor,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: AppColors.bgMedium,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: accentColor, size: 13),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          Text(
            hint,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card cell ───────────────────────────────────────────────────────────────

class _CardCell extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String? badge;
  final Color badgeColor;
  final VoidCallback? onTap;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Color actionColor;

  const _CardCell({
    required this.name,
    this.imageUrl,
    this.badge,
    this.badgeColor = AppColors.error,
    this.onTap,
    this.onAction,
    this.actionIcon,
    this.actionColor = AppColors.error,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        color: AppColors.bgMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: imageUrl != null && imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const _ImagePlaceholder(),
                          errorWidget: (_, _, _) => const _ImagePlaceholder(),
                        )
                      : const _ImagePlaceholder(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.bgLight,
        child: const Center(
          child: Icon(Icons.style, color: AppColors.textHint, size: 22),
        ),
      );
}
