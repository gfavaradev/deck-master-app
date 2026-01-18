import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/database_helper.dart';
import '../widgets/card_item.dart';
import '../widgets/collection_summary.dart';
import '../widgets/card_dialogs.dart';
import 'album_list_page.dart';
import 'deck_list_page.dart';
import 'catalog_page.dart';

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
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<CardModel> _allCards = [];
  List<CardModel> _allOwnedCards = []; // Added to track all cards for duplicate detection
  List<CardModel> _filteredCards = [];
  List<AlbumModel> _availableAlbums = [];
  bool _isGridView = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshCards();
  }

  Future<void> _refreshCards() async {
    final data = await _dbHelper.getCardsWithCatalog(widget.collectionKey);
    final albums = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
    if (!mounted) return;

    List<CardModel> processedCards = data;

    if (widget.albumId != null) {
      // Se siamo in un album specifico, mostriamo solo le carte di quell'album
      processedCards = data.where((c) => c.albumId == widget.albumId).toList();
    } else {
      // Vista generale: mostriamo solo le carte possedute (quantity > 0)
      // Il catalogo completo è accessibile tramite il pulsante Cerca nella AppBar
      processedCards = data.where((c) => c.quantity > 0).toList();
    }

    setState(() {
      _allCards = processedCards;
      _allOwnedCards = data;
      _availableAlbums = albums;
      _filterCards(_searchController.text);
    });
  }

  void _filterCards(String query) {
    setState(() {
      _filteredCards = _allCards
          .where((card) => card.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
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

      if (selectedId != null) {
        await _dbHelper.insertCard(card.copyWith(
          resetId: true,
          albumId: selectedId,
          quantity: delta,
        ));
        _refreshCards();
      }
      return;
    }

    final album = _availableAlbums.firstWhere((a) => a.id == card.albumId);
    final isDoppioni = album.name == 'Doppioni';

    if (delta > 0 && !isDoppioni && card.quantity >= 1) {
      final doppioniAlbumId = await _getOrCreateDuplicatesAlbum();
      final existingInDoppioni = _allCards.where((c) => 
        c.albumId == doppioniAlbumId &&
        c.name.toLowerCase() == card.name.toLowerCase() &&
        c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase()
      ).toList();

      if (existingInDoppioni.isNotEmpty) {
        await _dbHelper.updateCard(existingInDoppioni.first.copyWith(
          quantity: existingInDoppioni.first.quantity + delta
        ));
      } else {
        await _dbHelper.insertCard(card.copyWith(
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

    if (delta > 0 && album.currentCount + delta > album.maxCapacity) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Capacità Superata'),
          content: Text('Aumentare la quantità supererà la capacità massima dell\'album (${album.maxCapacity}). Vuoi procedere comunque?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Procedi')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await _dbHelper.updateCard(card.copyWith(quantity: newQuantity));
    _refreshCards();
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
        final allRelated = await _dbHelper.getCardsByCollection(widget.collectionKey);
        final toDelete = allRelated.where((c) => 
          c.name.toLowerCase() == card.name.toLowerCase() && 
          c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase()
        );
        for (var c in toDelete) {
          await _dbHelper.deleteCard(c.id!);
        }
      } else {
        // Se siamo in un album specifico, eliminiamo solo quella specifica istanza
        await _dbHelper.deleteCard(card.id!);
      }
      _refreshCards();
    }
  }

  Future<int> _getOrCreateDuplicatesAlbum() async {
    final existing = _availableAlbums.where((a) => a.name == 'Doppioni').toList();
    if (existing.isNotEmpty) return existing.first.id!;
    
    final id = await _dbHelper.insertAlbum(AlbumModel(
      name: 'Doppioni',
      collection: widget.collectionKey,
      maxCapacity: 1000,
    ));
    await _refreshCards();
    return id;
  }

  void _showAddCardDialog() {
    CardDialogs.showAddCard(
      context: context,
      collectionName: widget.collectionName,
      collectionKey: widget.collectionKey,
      availableAlbums: _availableAlbums,
      allCards: _allOwnedCards,
      onCardAdded: _refreshCards,
      getOrCreateDuplicatesAlbum: _getOrCreateDuplicatesAlbum,
    );
  }

  void _showDetails(CardModel card) {
    CardDialogs.showDetails(
      context: context,
      card: card,
      albumName: _getAlbumName(card.albumId),
      onDelete: _confirmDelete,
    );
  }

  String _getAlbumName(int albumId) {
    if (albumId == -1) return 'Catalogo';
    return _availableAlbums.firstWhere((a) => a.id == albumId, orElse: () => AlbumModel(name: 'Sconosciuto', collection: '', maxCapacity: 0)).name;
  }

  @override
  Widget build(BuildContext context) {
    final totalValue = _filteredCards.fold(0.0, (sum, item) => sum + (item.value * item.quantity));
    final totalCards = _filteredCards.fold(0, (sum, item) => sum + item.quantity);
    final uniqueKeys = _filteredCards.map((c) => '${c.name.toLowerCase()}_${c.serialNumber.toLowerCase()}').toSet();
    final uniqueCards = uniqueKeys.length;
    final duplicates = totalCards - uniqueCards;

    String title = widget.collectionName;
    if (widget.albumId != null) {
      title += ' - ${_getAlbumName(widget.albumId!)}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Catalogo',
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (context) => CatalogPage(
                  collectionName: widget.collectionName,
                  collectionKey: widget.collectionKey,
                )
              )
            ).then((_) => _refreshCards()),
          ),
          IconButton(
            icon: const Icon(Icons.deck),
            tooltip: 'Gestisci Deck',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DeckListPage(collectionName: widget.collectionName, collectionKey: widget.collectionKey))),
          ),
          IconButton(
            icon: const Icon(Icons.book),
            tooltip: 'Gestisci Album',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlbumListPage(collectionName: widget.collectionName, collectionKey: widget.collectionKey))).then((_) => _refreshCards()),
          ),
          IconButton(icon: Icon(_isGridView ? Icons.list : Icons.grid_view), onPressed: () => setState(() => _isGridView = !_isGridView)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(hintText: 'Cerca carta...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              onChanged: _filterCards,
            ),
          ),
          CollectionSummary(uniqueCards: uniqueCards, duplicates: duplicates, totalCards: totalCards, totalValue: totalValue),
          Expanded(
            child: _filteredCards.isEmpty
                ? const Center(child: Text('Nessuna carta trovata.'))
                : _isGridView ? _buildGrid() : _buildList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddCardDialog, child: const Icon(Icons.add)),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _filteredCards.length,
      itemBuilder: (context, index) {
        final card = _filteredCards[index];
        return CardListItem(card: card, albumName: _getAlbumName(card.albumId), onUpdateQuantity: _updateQuantity, onDelete: _confirmDelete, onTap: _showDetails);
      },
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.75),
      itemCount: _filteredCards.length,
      itemBuilder: (context, index) {
        final card = _filteredCards[index];
        return CardGridItem(card: card, albumName: _getAlbumName(card.albumId), onUpdateQuantity: _updateQuantity, onTap: _showDetails);
      },
    );
  }
}
