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

  @override
  void initState() {
    super.initState();
    _refreshCards();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _refreshCards();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchController.dispose();
    super.dispose();
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

    final doppioniIds = albums.where((a) => a.name == 'Doppioni').map((a) => a.id).toSet();

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
      _filterCards(_searchController.text);
    });
  }

  void _filterCards(String query) {
    setState(() {
      final q = query.toLowerCase();
      bool matches(CardModel card) =>
          card.name.toLowerCase().contains(q) ||
          card.serialNumber.toLowerCase().contains(q) ||
          card.rarity.toLowerCase().contains(q);

      _filteredCards = _allCards.where(matches).toList();
      _filteredDoppioniCards = _doppioniCards.where(matches).toList();

      // Sort by serialNumber ascending (like catalog)
      _filteredCards.sort((a, b) => a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase()));
      _filteredDoppioniCards.sort((a, b) => a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase()));
    });
  }

  Future<void> _updateQuantity(CardModel card, int delta) async {
    // Gestione carte dal catalogo (non ancora in un album)
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
      await _repo.insertCard(card.copyWith(
        resetId: true,
        albumId: selectedId,
        quantity: delta,
      ));
      _refreshCards();
      return;
    }

    final album = _availableAlbums.firstWhere(
      (a) => a.id == card.albumId,
      orElse: () => AlbumModel(name: 'Sconosciuto', collection: card.collection, maxCapacity: 0),
    );
    final isDoppioni = album.name == 'Doppioni';

    // Minus on a non-doppioni card: drain doppioni first, floor main at 1
    if (delta < 0 && !isDoppioni) {
      if (widget.albumId == null) {
        // General view: check doppioni list for matching card
        final doppioniMatch = _doppioniCards.where((c) =>
          c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
          c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
          (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId)
        ).toList();

        if (doppioniMatch.isNotEmpty) {
          final doppioniCard = doppioniMatch.first;
          final newDoppioniQty = doppioniCard.quantity - 1;
          if (newDoppioniQty <= 0) {
            await _repo.deleteCard(doppioniCard.id!);
          } else {
            await _repo.updateCard(doppioniCard.copyWith(quantity: newDoppioniQty));
          }
          _refreshCards();
          return;
        }
        // No doppioni left: floor the main card at 1, do nothing
        return;
      } else {
        // Album view: floor the card at 1
        if (card.quantity + delta < 1) return;
      }
    }

    // Plus on a non-doppioni card with quantity >= 1: add to Doppioni
    if (delta > 0 && !isDoppioni && card.quantity >= 1) {
      final doppioniAlbumId = await _getOrCreateDuplicatesAlbum();
      final existingInDoppioni = _doppioniCards.where((c) =>
        c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
        c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
        (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId)
      ).toList();

      if (existingInDoppioni.isNotEmpty) {
        await _repo.updateCard(existingInDoppioni.first.copyWith(
          quantity: existingInDoppioni.first.quantity + delta
        ));
      } else {
        await _repo.insertCard(card.copyWith(
          resetId: true,
          albumId: doppioniAlbumId,
          quantity: delta,
        ));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doppione aggiunto all\'album "Doppioni"'), duration: Duration(seconds: 1))
      );
      _refreshCards();
      return;
    }

    final newQuantity = card.quantity + delta;
    if (newQuantity < 1) {
      _confirmDelete(card);
      return;
    }

    if (delta > 0 && album.id != null && album.maxCapacity > 0) {
      final freshCount = await _repo.getCardCountByAlbum(album.id!);
      if (freshCount + delta > album.maxCapacity) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Capacità Superata'),
            content: Text('Aumentare la quantità supererà la capacità massima dell\'album ($freshCount/${album.maxCapacity}). Vuoi procedere comunque?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Procedi')),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    await _repo.updateCard(card.copyWith(quantity: newQuantity));
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
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina Carta'),
        content: Text('Sei sicuro di voler eliminare "${card.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (proceed == true) {
      if (widget.albumId == null) {
        // Se siamo nella vista generale, eliminiamo TUTTE le istanze di questa carta (tutti gli album)
        final allRelated = await _repo.getCardsByCollection(widget.collectionKey);
        final toDelete = allRelated.where((c) =>
          c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase() &&
          c.rarity.toLowerCase() == card.rarity.toLowerCase() &&
          (c.catalogId == null || card.catalogId == null || c.catalogId == card.catalogId)
        );
        for (var c in toDelete) {
          await _repo.deleteCard(c.id!);
        }
      } else {
        // Se siamo in un album specifico, eliminiamo solo quella specifica istanza
        await _repo.deleteCard(card.id!);
      }
      _refreshCards();
    }
  }

  Future<int> _getOrCreateDuplicatesAlbum() async {
    final existing = _availableAlbums.where((a) => a.name == 'Doppioni').toList();
    if (existing.isNotEmpty) return existing.first.id!;
    
    final id = await _repo.insertAlbum(AlbumModel(
      name: 'Doppioni',
      collection: widget.collectionKey,
      maxCapacity: 1000,
    ));
    await _refreshCards();
    return id;
  }

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
    // Summary always uses full lists (not filtered) so values don't change during search
    final mainCount = _filteredCards.fold(0, (sum, item) => sum + item.quantity);
    final mainValue = _filteredCards.fold(0.0, (sum, item) => sum + (item.value * item.quantity));
    final doppioniCount = _filteredDoppioniCards.fold(0, (sum, item) => sum + item.quantity);
    final doppioniValue = _filteredDoppioniCards.fold(0.0, (sum, item) => sum + (item.value * item.quantity));
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
                      onPressed: () {
                        setState(() => _isGridView = false);
                      },
                      tooltip: 'Vista Lista',
                    ),
                    Container(width: 1, height: 24, color: AppColors.textHint.withValues(alpha: 0.3)),
                    IconButton(
                      icon: Icon(Icons.grid_view, color: _isGridView ? AppColors.purple : AppColors.textHint),
                      onPressed: () {
                        setState(() => _isGridView = true);
                      },
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
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredCards.isEmpty
                  ? Center(
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
                    )
                  : _isGridView ? _buildGrid() : _buildList(),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
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
}
