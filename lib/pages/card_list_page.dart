import 'dart:async';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
import '../widgets/card_item.dart';
import '../widgets/collection_summary.dart';
import '../widgets/card_dialogs.dart';
import '../theme/app_colors.dart';
import 'support_page.dart';
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
  List<AlbumModel> _availableAlbums = [];
  bool _isGridView = false;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<String>? _syncSub;

  List<Map<String, dynamic>> _catalogSuggestions = [];
  bool _catalogSearching = false;
  int? _lastUsedAlbumId;
  String _preferredLanguage = 'EN';

  @override
  void initState() {
    super.initState();
    _refreshCards();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _refreshCards();
    });
    LanguageService.getPreferredLanguageForCollection(widget.collectionKey).then((lang) {
      if (mounted) setState(() => _preferredLanguage = lang);
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
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
      debugPrint('🔍 Album View - Album ID: ${widget.albumId}, Carte trovate: ${processedCards.length}/${data.length}');
    } else {
      // Vista generale: escludi le carte dall'album "Doppioni"
      processedCards = data.where((c) => !doppioniIds.contains(c.albumId)).toList();
      debugPrint('🔍 Vista Generale - Carte (escluso Doppioni): ${processedCards.length}/${data.length}');
    }

    setState(() {
      _allCards = processedCards;
      _doppioniCards = data.where((c) => doppioniIds.contains(c.albumId)).toList();
      _availableAlbums = albums;
      _isLoading = false;
      _applyFilter(_searchController.text);
    });
  }

  // Pure computation — does NOT call setState. Callers must wrap in setState.
  void _applyFilter(String query) {
    final q = query.toLowerCase();
    bool matches(CardModel card) =>
        card.name.toLowerCase().contains(q) ||
        card.serialNumber.toLowerCase().contains(q) ||
        card.rarity.toLowerCase().contains(q);

    _filteredCards = _allCards.where(matches).toList();
    _filteredDoppioniCards = _doppioniCards.where(matches).toList();

    _filteredCards.sort((a, b) => a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase()));
    _filteredDoppioniCards.sort((a, b) => a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase()));
  }

  void _filterCards(String query) {
    _applyFilter(query);
    final hasQuery = query.trim().isNotEmpty;
    final hasLocalResults = _filteredCards.isNotEmpty;
    setState(() {
      _catalogSuggestions = [];
      _catalogSearching = hasQuery && !hasLocalResults;
    });
    if (hasQuery && !hasLocalResults) _searchCatalog(query.trim());
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
      allCards: _allCards,
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
        builder: (context) => AlertDialog(
          title: const Text('Seleziona Album'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _availableAlbums.map((album) => ListTile(
              title: Text(album.name),
              onTap: () => Navigator.pop(context, album.id),
            )).toList(),
          ),
        ),
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
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Capacità Superata'),
            content: Text('Supererà la capacità massima ($freshCount/${album.maxCapacity}). Procedere?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Procedi')),
            ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doppione aggiunto all\'album "Doppioni"'), duration: Duration(seconds: 1)),
      );
    }
    _refreshCards();
  }

  /// Returns the total quantity for a card: its own quantity + matching doppioni quantity
  int _getTotalQuantity(CardModel card) {
    final doppioniQty = _doppioniCards
      .where((c) =>
        c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
        c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
        (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId))
      .fold(0, (sum, c) => sum + c.quantity);
    return card.quantity + doppioniQty;
  }

  Future<void> _confirmDelete(CardModel card) async {
    final deleted = await _repo.deleteCardWithRelated(
      card, widget.collectionKey,
      allRelated: widget.albumId == null,
    );
    _refreshCards();
    if (!mounted) return;
    _TopUndoBar.show(
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

  Future<void> _showDetails(CardModel card) async {
    final decks = card.id != null
        ? await _repo.getDecksForCard(card.id!)
        : <Map<String, dynamic>>[];
    if (!mounted) return;
    CardDialogs.showDetails(
      context: context,
      card: card,
      albumName: _getAlbumName(card.albumId),
      onDelete: _confirmDelete,
      availableAlbums: _availableAlbums,
      onAlbumChanged: _refreshCards,
      cardDecks: decks,
    );
  }

  String _getAlbumName(int albumId) {
    if (albumId == -1) return 'Catalogo';
    return _availableAlbums.firstWhere((a) => a.id == albumId, orElse: () => AlbumModel(name: 'Sconosciuto', collection: '', maxCapacity: 0)).name;
  }

  Widget _buildAlbumBanner() {
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
                const Text(
                  'Stai visualizzando solo le carte di questo album',
                  style: TextStyle(
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
              '${_allCards.length} carte',
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cerca per nome, seriale o rarità...',
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
                      tooltip: 'Vista Lista',
                    ),
                    Container(width: 1, height: 24, color: AppColors.textHint.withValues(alpha: 0.3)),
                    IconButton(
                      icon: Icon(Icons.grid_view, color: _isGridView ? AppColors.purple : AppColors.textHint),
                      onPressed: () => setState(() => _isGridView = true),
                      tooltip: 'Vista Griglia',
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
          onTap: _showDetails,
        );
      },
    );
  }

  Widget _buildEmptyState() {
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
                  ? 'Nessuna carta in questo album.\nAggiungi carte dal Catalogo selezionando questo album.'
                  : 'Nessuna carta trovata.\nUsa il Catalogo per aggiungere carte.',
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
                  'Non in collezione — trovata nel catalogo',
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
                    label: const Text('Aggiungi'),
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
            const Text(
              'Carta non disponibile nel catalogo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Questa carta non è ancora presente nel nostro catalogo. Puoi segnalarcela e la aggiungeremo il prima possibile.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.support_agent),
              label: const Text('Segnala carta mancante'),
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
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.65, // Same as catalog
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
          onTap: _showDetails,
        );
      },
    );
  }

  double _getEffectiveValue(CardModel card) {
    if (card.cardtraderValue != null && card.cardtraderValue! > 0) {
      return card.cardtraderValue!;
    }
    return card.value;
  }
}

// ─── Top undo bar ─────────────────────────────────────────────────────────────

class _TopUndoBar {
  static OverlayEntry? _entry;

  static void show({
    required BuildContext context,
    required String message,
    required VoidCallback onUndo,
  }) {
    _entry?.remove();
    _entry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _UndoBarWidget(
        message: message,
        onUndo: () {
          onUndo();
          _dismiss();
        },
        onExpired: _dismiss,
      ),
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  static void _dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _UndoBarWidget extends StatefulWidget {
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onExpired;

  const _UndoBarWidget({
    required this.message,
    required this.onUndo,
    required this.onExpired,
  });

  @override
  State<_UndoBarWidget> createState() => _UndoBarWidgetState();
}

class _UndoBarWidgetState extends State<_UndoBarWidget> {
  int _remaining = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_remaining <= 1) {
        t.cancel();
        widget.onExpired();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPad + kToolbarHeight + 8,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgMedium,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Countdown ring
              SizedBox(
                width: 34,
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _remaining / 5,
                      strokeWidth: 2.5,
                      color: Colors.red.shade400,
                      backgroundColor: Colors.red.withValues(alpha: 0.15),
                    ),
                    Text(
                      '$_remaining',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onUndo,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange.shade300,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Annulla',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
