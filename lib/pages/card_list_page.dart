import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
import '../widgets/card_item.dart';
import '../widgets/collection_summary.dart';
import '../widgets/full_screen_gallery.dart';
import '../widgets/card_dialogs.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/top_undo_bar.dart';
import 'support_page.dart';
import 'card_detail_page.dart';
import '../services/language_service.dart';

class CardListPage extends StatefulWidget {
  final String collectionName;
  final String collectionKey;
  final int? albumId;

  const CardListPage({
    super.key,
    required this.collectionName,
    required this.collectionKey,
    this.albumId,
  });

  @override
  State<CardListPage> createState() => _CardListPageState();
}

class _CardListPageState extends State<CardListPage> {
  final DataRepository _repo = DataRepository();
  List<CardModel> _allCards = [];
  List<CardModel> _filteredCards = [];
  List<CardModel> _doppioniCards = [];
  List<CardModel> _filteredDoppioniCards = [];
  /// Precomputed map: "serialNumber|rarity|catalogId" → total doppioni quantity
  Map<String, int> _doppioniQtyMap = {};
  List<AlbumModel> _availableAlbums = [];
  bool _isGridView = false;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<String>? _syncSub;
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _catalogSuggestions = [];
  bool _catalogSearching = false;
  int? _lastUsedAlbumId;
  String _preferredLanguage = 'EN';
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;
  @override
  void initState() {
    super.initState();
    _refreshCards();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _refreshCards();
    });
    LanguageService.getPreferredLanguageForCollection(widget.collectionKey).then((lang) {
      if (!mounted) return;
      // _preferredLanguage drives catalog search; if it changed re-fetch so
      // prices are computed with the correct localized columns.
      if (lang != _preferredLanguage) {
        _preferredLanguage = lang;
        _refreshCards();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await _repo.fullSync();
    await _refreshCards();
  }

  Future<void> _refreshCards() async {
    // Run both queries in parallel — SQLite serializes internally but avoids
    // the Dart await overhead of sequential calls
    final results = await Future.wait([
      _repo.getCardsByCollection(widget.collectionKey),
      _repo.getAlbumsByCollection(widget.collectionKey),
    ]);
    if (!mounted) return;
    final data = results[0] as List<CardModel>;
    final albums = results[1] as List<AlbumModel>;

    List<CardModel> processedCards = data;

    final doppioniIds = albums.where((a) => a.name == 'Doppioni' && a.id != null).map((a) => a.id!).toSet();

    if (widget.albumId != null) {
      // Se siamo in un album specifico, mostriamo solo le carte di quell'album
      processedCards = data.where((c) => c.albumId == widget.albumId).toList();

    } else {
      // Vista generale: escludi le carte dall'album "Doppioni"
      processedCards = data.where((c) => !doppioniIds.contains(c.albumId)).toList();

    }

    final doppioniCards = data.where((c) => doppioniIds.contains(c.albumId)).toList();

    // Precompute lookup map once — O(n) build, O(1) per-item access in the list
    final doppioniMap = <String, int>{};
    for (final c in doppioniCards) {
      final key = '${c.serialNumber.toLowerCase()}|${c.rarity.toLowerCase()}|${c.catalogId ?? ''}';
      doppioniMap[key] = (doppioniMap[key] ?? 0) + c.quantity;
    }

    setState(() {
      _allCards = processedCards;
      _doppioniCards = doppioniCards;
      _doppioniQtyMap = doppioniMap;
      _availableAlbums = albums;
      _isLoading = false;
      _applyFilter(_searchController.text);
    });
  }

  // Pure computation — does NOT call setState. Callers must wrap in setState.
  void _applyFilter(String query) {
    final q = query.toLowerCase();
    bool matches(CardModel card) =>
        card.serialNumber.toLowerCase().contains(q);

    _filteredCards = _allCards.where(matches).toList();
    _filteredDoppioniCards = _doppioniCards.where(matches).toList();

    _filteredCards.sort((a, b) => a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase()));
    _filteredDoppioniCards.sort((a, b) => a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase()));
  }

  void _filterCards(String query) {
    // Immediate local filter (fast, no debounce needed)
    _applyFilter(query);
    final hasQuery = query.trim().isNotEmpty;
    final hasLocalResults = _filteredCards.isNotEmpty;
    setState(() {
      _catalogSuggestions = [];
      _catalogSearching = hasQuery && !hasLocalResults;
    });
    // Debounce only the catalog search (network/SQLite call)
    if (hasQuery && !hasLocalResults) {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) _searchCatalog(query.trim());
      });
    }
  }

  Future<void> _searchCatalog(String query) async {
    final results = await _repo.getCatalogCardsByCollection(
      widget.collectionKey,
      query: query,
      language: _preferredLanguage,
      limit: 30,
    );
    if (!mounted) return;
    setState(() {
      _catalogSuggestions = results;
      _catalogSearching = false;
    });
  }



  void _showAddFromCatalog(Map<String, dynamic> catalogCard) {
    CardDialogs.showAddCard(
      context: context,
      collectionName: widget.collectionName,
      collectionKey: widget.collectionKey,
      availableAlbums: _availableAlbums,
      lastUsedAlbumId: _lastUsedAlbumId,
      initialCatalogCard: catalogCard,
      onCardAdded: (int usedAlbumId, String _) {
        setState(() => _lastUsedAlbumId = usedAlbumId);
        _refreshCards();
      },
      getOrCreateDuplicatesAlbum: _getOrCreateDuplicatesAlbum,
    );
  }

  Future<void> _updateQuantity(CardModel card, int delta) async {
    // Catalog card not yet in an album: show album picker first
    if (card.albumId == -1) {
      if (delta <= 0) return;
      final int? selectedId = await showDialog<int>(
        context: context,
        builder: (ctx) {
          final l10n = AppLocalizations.of(ctx)!;
          return AppDialog(
            title: l10n.catalogSelectAlbumTitle,
            icon: Icons.book_outlined,
            contentPadding: EdgeInsets.zero,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: _availableAlbums.map((album) => ListTile(
                title: Text(album.name, style: const TextStyle(color: AppColors.textPrimary)),
                subtitle: Text('${album.currentCount}/${album.maxCapacity} ${AppLocalizations.of(ctx)!.nounCards}', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, album.id),
              )).toList(),
            ),
          );
        },
      );
      if (!context.mounted || selectedId == null) return;
      await _repo.insertCard(card.copyWith(resetId: true, albumId: selectedId, quantity: delta));
      _refreshCards();
      return;
    }

    // In album view: floor at 1. In general view, adjustCardQuantity drains doppioni first.
    if (widget.albumId != null && card.quantity + delta < 1) return;

    // Capacity check for non-doppioni increments in album view
    final album = _availableAlbums.firstWhere(
      (a) => a.id == card.albumId,
      orElse: () => AlbumModel(name: '', collection: card.collection, maxCapacity: 0),
    );
    if (delta > 0 && album.name != 'Doppioni' && album.id != null && album.maxCapacity > 0) {
      final freshCount = await _repo.getCardCountByAlbum(album.id!);
      if (freshCount + delta > album.maxCapacity) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AppConfirmDialog(
            title: l10n.dlgCapacityExceededTitle,
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.warning,
            message: l10n.dlgCapacityExceededMsg(freshCount, album.maxCapacity),
            confirmLabel: l10n.btnProceed,
            confirmColor: AppColors.warning,
          ),
        );
        if (proceed != true) return;
      }
    }

    // Delegate doppioni routing + update to the service
    final willAddToDoppioni = delta > 0 && album.name != 'Doppioni' && card.quantity >= 1;
    await _repo.adjustCardQuantity(
      card, delta,
      collectionKey: widget.collectionKey,
      isAlbumView: widget.albumId != null,
    );
    if (!mounted) return;
    if (willAddToDoppioni) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cardListDoppioneAdded), duration: const Duration(seconds: 1)),
      );
    }
    _refreshCards();
  }

  /// Returns the total quantity for a card: its own quantity + matching doppioni quantity.
  /// Uses a precomputed map (O(1)) instead of a linear scan per item.
  int _getTotalQuantity(CardModel card) {
    final key = '${card.serialNumber.toLowerCase()}|${card.rarity.toLowerCase()}|${card.catalogId ?? ''}';
    return card.quantity + (_doppioniQtyMap[key] ?? 0);
  }

  Future<void> _confirmDelete(CardModel card) async {
    final deleted = await _repo.deleteCardWithRelated(
      card, widget.collectionKey,
      allRelated: widget.albumId == null,
    );
    _refreshCards();
    if (!mounted) return;
    TopUndoBar.show(
      context: context,
      message: '"${card.name}" eliminata',
      onUndo: () async {
        for (final c in deleted) {
          await _repo.insertCard(c);
        }
        _refreshCards();
      },
    );
  }

  Future<int> _getOrCreateDuplicatesAlbum() =>
      _repo.getOrCreateDoppioniAlbum(widget.collectionKey);

  // ─── Multi-select ─────────────────────────────────────────────────────────────

  void _enterSelectionMode(CardModel card) {
    if (card.id == null) return;
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(card.id!);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleCardSelection(CardModel card) {
    if (card.id == null) return;
    setState(() {
      if (_selectedIds.contains(card.id)) {
        _selectedIds.remove(card.id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(card.id!);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(
        _filteredCards.where((c) => c.id != null).map((c) => c.id!),
      );
    });
  }

  void _deselectAll() {
    setState(() => _selectedIds.clear());
  }

  Future<void> _batchDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _filteredCards
        .where((c) => c.id != null && _selectedIds.contains(c.id))
        .toList();
    final count = selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: l10n.dlgDeleteNCardsTitle(count),
        icon: Icons.delete_outline,
        iconColor: AppColors.error,
        message: l10n.dlgDeleteNCardsMsg(count),
        confirmLabel: l10n.btnDelete,
        confirmColor: AppColors.error,
      ),
    );
    if (confirm != true || !mounted) return;
    await Future.wait(selected.map((card) => _repo.deleteCardWithRelated(
      card, widget.collectionKey,
      allRelated: widget.albumId == null,
    )));
    _exitSelectionMode();
    _refreshCards();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.msgNCardsDeleted(count)), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _batchChangeAlbum() async {
    final l10n = AppLocalizations.of(context)!;
    final albumId = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.dlgMoveToAlbumTitle,
        icon: Icons.drive_file_move_outlined,
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _availableAlbums.map((album) => ListTile(
            title: Text(album.name, style: const TextStyle(color: AppColors.textPrimary)),
            subtitle: Text(
              '${album.currentCount}/${album.maxCapacity} ${AppLocalizations.of(ctx)!.nounCards}',
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
            onTap: () => Navigator.pop(ctx, album.id),
          )).toList(),
        ),
      ),
    );
    if (!mounted || albumId == null) return;
    final selected = _filteredCards
        .where((c) => c.id != null && _selectedIds.contains(c.id))
        .toList();
    await Future.wait(selected.map((card) => _repo.updateCard(card.copyWith(albumId: albumId))));
    _exitSelectionMode();
    _refreshCards();
  }

  Future<void> _batchAddToDeck() async {
    final l10n = AppLocalizations.of(context)!;
    final decks = await _repo.getDecksByCollection(widget.collectionKey);
    if (!mounted) return;
    if (decks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.msgNoDeckAvailable),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final deckId = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.dlgAddToDeckTitle,
        icon: Icons.layers_outlined,
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: decks.map((deck) => ListTile(
            title: Text(
              deck['name'] as String? ?? '',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            onTap: () => Navigator.pop(ctx, deck['id'] as int?),
          )).toList(),
        ),
      ),
    );
    if (!mounted || deckId == null) return;
    final selected = _filteredCards
        .where((c) => c.id != null && _selectedIds.contains(c.id))
        .toList();
    await Future.wait(selected.map((card) => _repo.addCardToDeck(deckId, card.id!, 1)));
    _exitSelectionMode();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.msgNCardsAddedToDeck(selected.length)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSelectionHeader() {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedIds.length;
    final total = _filteredCards.length;
    final allSelected = count == total && total > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: _exitSelectionMode,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              count == 0 ? l10n.selectionSelectCards : l10n.selectionNSelected(count),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 18),
            label: Text(allSelected ? l10n.selectionDeselectAll : l10n.selectionSelectAll),
            style: TextButton.styleFrom(foregroundColor: AppColors.blue),
            onPressed: allSelected ? _deselectAll : _selectAll,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedIds.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: const BoxDecoration(
        color: AppColors.bgLight,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.drive_file_move_outlined, size: 18),
              label: Text(l10n.selectionAlbumBtn),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: count > 0 ? _batchChangeAlbum : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: Text(l10n.selectionDeckBtn),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: count > 0 ? _batchAddToDeck : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l10n.selectionDeleteBtn),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: count > 0 ? _batchDelete : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(CardModel card) async {
    final index = _filteredCards.indexOf(card);
    final safeIndex = index < 0 ? 0 : index;
    final decks = card.id != null
        ? await _repo.getDecksForCard(card.id!)
        : <Map<String, dynamic>>[];
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CardDetailPage(
          cards: _filteredCards,
          initialIndex: safeIndex,
          onDelete: _confirmDelete,
          availableAlbums: _availableAlbums,
          onAlbumChanged: _refreshCards,
          initialDecks: decks,
        ),
      ),
    );
  }

  void _showGallery(List<CardModel> cards, int initialIndex) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => FullScreenGallery(
        imageUrls: cards.map((c) => c.imageUrl).toList(),
        names: cards.map((c) => c.name).toList(),
        initialIndex: initialIndex,
      ),
    );
  }

  String _getAlbumName(int albumId) {
    final l10n = AppLocalizations.of(context)!;
    if (albumId == -1) return l10n.cardListAlbumCatalog;
    return _availableAlbums.firstWhere((a) => a.id == albumId, orElse: () => AlbumModel(name: l10n.cardListAlbumUnknown, collection: '', maxCapacity: 0)).name;
  }

  Widget _buildAlbumBanner() {
    final l10n = AppLocalizations.of(context)!;
    final album = _availableAlbums.firstWhere(
      (a) => a.id == widget.albumId,
      orElse: () => AlbumModel(name: 'Album', collection: '', maxCapacity: 0),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        border: Border(bottom: BorderSide(color: AppColors.blue.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          const Icon(Icons.book, color: AppColors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  l10n.cardListAlbumOnly,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.glowBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.statsCardsCount(_allCards.length),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mainCount = _filteredCards.fold(0, (sum, item) => sum + item.quantity);
    final mainValue = _filteredCards.fold(0.0, (sum, item) {
      final effectivePrice = _getEffectiveValue(item);
      return sum + (effectivePrice * item.quantity);
    });
    // In album view doppioni belong to a different album — exclude them from summary
    final doppioniCount = widget.albumId != null
        ? 0
        : _filteredDoppioniCards.fold(0, (sum, item) => sum + item.quantity);
    final doppioniValue = widget.albumId != null
        ? 0.0
        : _filteredDoppioniCards.fold(0.0, (sum, item) {
          final effectivePrice = _getEffectiveValue(item);
          return sum + (effectivePrice * item.quantity);
        });
    final uniqueCards = mainCount;
    final duplicates = doppioniCount;
    final totalCards = mainCount + doppioniCount;
    final totalValue = mainValue + doppioniValue;

    return Column(
      children: [
        if (widget.albumId != null) _buildAlbumBanner(),
        if (_isSelectionMode)
          _buildSelectionHeader()
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l10n.cardListSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: _filterCards,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.textHint.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.list, color: !_isGridView ? AppColors.purple : AppColors.textHint),
                        onPressed: () => setState(() => _isGridView = false),
                        tooltip: l10n.cardListViewTooltipList,
                      ),
                      Container(width: 1, height: 24, color: AppColors.textHint.withValues(alpha: 0.3)),
                      IconButton(
                        icon: Icon(Icons.grid_view, color: _isGridView ? AppColors.purple : AppColors.textHint),
                        onPressed: () => setState(() => _isGridView = true),
                        tooltip: l10n.cardListViewTooltipGrid,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        CollectionSummary(uniqueCards: uniqueCards, duplicates: duplicates, totalCards: totalCards, totalValue: totalValue),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: _isLoading
                ? const Stack(children: [
                    Center(child: CircularProgressIndicator()),
                  ])
                : _filteredCards.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: 400,
                          child: _buildEmptyState(),
                        ),
                      )
                    : _isGridView
                        ? _buildGrid()
                        : _buildList(),
          ),
        ),
        if (_isSelectionMode) _buildSelectionBar(),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _filteredCards.length,
      itemBuilder: (context, index) {
        final card = _filteredCards[index];
        final inAlbum = widget.albumId != null;
        return CardListItem(
          card: card,
          albumName: _getAlbumName(card.albumId),
          totalQuantity: inAlbum ? card.quantity : _getTotalQuantity(card),
          showControls: !inAlbum,
          onUpdateQuantity: _updateQuantity,
          onDelete: _confirmDelete,
          onTap: _isSelectionMode ? _toggleCardSelection : _showDetails,
          onImageTap: _isSelectionMode ? null : () => _showGallery(_filteredCards, index),
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedIds.contains(card.id),
          onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(card),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    // Nessuna ricerca attiva
    if (!hasQuery) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              widget.albumId != null
                  ? l10n.cardListEmptyAlbum
                  : l10n.cardListEmptyCollection,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    // Ricerca in corso nel catalogo
    if (_catalogSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    // Risultati trovati nel catalogo
    if (_catalogSuggestions.isNotEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  l10n.cardListNotInCollection,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _catalogSuggestions.length,
              itemBuilder: (_, i) {
                final card = _catalogSuggestions[i];
                final name = (card['localizedName'] ?? card['name'] ?? '—') as String;
                final setCode = (card['localizedSetCode'] ?? card['setCode'] ?? card['serialNumber'] ?? '') as String;
                return ListTile(
                  leading: const Icon(Icons.style_outlined, color: AppColors.textSecondary),
                  title: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: setCode.isNotEmpty ? Text(setCode, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)) : null,
                  trailing: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(l10n.btnAdd),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () => _showAddFromCatalog(card),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    // Carta non trovata nemmeno nel catalogo
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              l10n.cardListNotInCatalog,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cardListNotInCatalogMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.support_agent),
              label: Text(l10n.cardListReportMissing),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(builder: (context, constraints) {
      final aw = constraints.maxWidth;
      final cols = kIsWeb
          ? (aw > 1100 ? 7 : aw > 860 ? 6 : aw > 640 ? 5 : 4)
          : (aw > 500 ? 3 : 2);
      return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.65,
      ),
      itemCount: _filteredCards.length,
      itemBuilder: (context, index) {
        final card = _filteredCards[index];
        final inAlbum = widget.albumId != null;
        return CardGridItem(
          card: card,
          albumName: _getAlbumName(card.albumId),
          totalQuantity: inAlbum ? card.quantity : _getTotalQuantity(card),
          showControls: !inAlbum,
          onUpdateQuantity: _updateQuantity,
          onTap: _isSelectionMode ? _toggleCardSelection : _showDetails,
          onImageTap: _isSelectionMode ? null : () => _showGallery(_filteredCards, index),
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedIds.contains(card.id),
          onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(card),
        );
      },
    );
    });
  }

  double _getEffectiveValue(CardModel card) {
    if (card.cardtraderValue != null && card.cardtraderValue! > 0) {
      return card.cardtraderValue!;
    }
    return 0.0;
  }
}

// ─── Top undo bar ─────────────────────────────────────────────────────────────

