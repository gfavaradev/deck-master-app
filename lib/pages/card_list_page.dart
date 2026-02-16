import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../widgets/card_item.dart';
import '../widgets/collection_summary.dart';
import '../widgets/card_dialogs.dart';

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
  List<AlbumModel> _availableAlbums = [];
  bool _isGridView = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshCards();
  }

  Future<void> _refreshCards() async {
    // Usa getCardsByCollection per mostrare solo le carte effettivamente possedute
    // (non le carte del catalogo)
    final data = await _repo.getCardsByCollection(widget.collectionKey);
    final albums = await _repo.getAlbumsByCollection(widget.collectionKey);
    if (!mounted) return;

    List<CardModel> processedCards = data;

    final doppioniIds = albums.where((a) => a.name == 'Doppioni').map((a) => a.id).toSet();

    if (widget.albumId != null) {
      // Se siamo in un album specifico, mostriamo solo le carte di quell'album
      processedCards = data.where((c) => c.albumId == widget.albumId).toList();
    } else {
      // Vista generale: escludi le carte dall'album "Doppioni"
      processedCards = data.where((c) => !doppioniIds.contains(c.albumId)).toList();
    }

    setState(() {
      _allCards = processedCards;
      _doppioniCards = data.where((c) => doppioniIds.contains(c.albumId)).toList();
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
        await _repo.insertCard(card.copyWith(
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

    await _repo.updateCard(card.copyWith(quantity: newQuantity));
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
        final allRelated = await _repo.getCardsByCollection(widget.collectionKey);
        final toDelete = allRelated.where((c) => 
          c.name.toLowerCase() == card.name.toLowerCase() && 
          c.serialNumber.toLowerCase() == card.serialNumber.toLowerCase()
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
    final mainValue = _filteredCards.fold(0.0, (sum, item) => sum + (item.value * item.quantity));
    final mainCount = _filteredCards.fold(0, (sum, item) => sum + item.quantity);
    final doppioniCount = _doppioniCards.fold(0, (sum, item) => sum + item.quantity);
    final doppioniValue = _doppioniCards.fold(0.0, (sum, item) => sum + (item.value * item.quantity));
    final uniqueCards = mainCount;
    final duplicates = doppioniCount;
    final totalCards = mainCount + doppioniCount;
    final totalValue = mainValue + doppioniValue;

    return Column(
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
              ? const Center(child: Text('Nessuna carta trovata. Usa il Catalogo per aggiungere carte.'))
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
