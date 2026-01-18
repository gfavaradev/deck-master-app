import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import '../widgets/card_dialogs.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';

class CatalogPage extends StatefulWidget {
  final String collectionName;
  final String collectionKey;

  const CatalogPage({
    super.key,
    required this.collectionName,
    required this.collectionKey,
  });

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _catalogCards = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  double _updateProgress = 0.0;
  List<AlbumModel> _availableAlbums = [];
  List<CardModel> _allOwnedCards = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cards = await _dbHelper.getCatalogCards(widget.collectionKey, query: _searchController.text);
    final albums = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
    final owned = await _dbHelper.getCardsWithCatalog(widget.collectionKey);
    
    setState(() {
      _catalogCards = cards;
      _availableAlbums = albums;
      _allOwnedCards = owned;
      _isLoading = false;
    });
  }

  Future<void> _updateCatalog() async {
    if (widget.collectionKey != 'yugioh') return;

    setState(() {
      _isUpdating = true;
      _updateProgress = 0.0;
    });
    try {
      final cards = await _apiService.fetchYugiohCards();
      await _dbHelper.insertCatalogCards(cards, onProgress: (progress) {
        setState(() => _updateProgress = progress);
      });
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogo aggiornato con successo!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'aggiornamento: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _onSearchChanged() {
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Catalogo ${widget.collectionName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isUpdating)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('${(_updateProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Cerca per nome o seriale...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged();
                  },
                ),
              ),
              onChanged: (_) => _onSearchChanged(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _catalogCards.isEmpty
                    ? const Center(child: Text('Nessuna carta trovata'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.7,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _catalogCards.length,
                        itemBuilder: (context, index) {
                          final card = _catalogCards[index];
                          return InkWell(
                            onTap: () => _showAddDialog(card),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: (card['imageUrl'] != null && card['imageUrl'].toString().isNotEmpty)
                                      ? Image.network(
                                          card['imageUrl'],
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.image_not_supported),
                                        )
                                      : Container(
                                          color: Colors.grey.withValues(alpha: 0.1),
                                          child: const Icon(Icons.style, size: 40, color: Colors.grey),
                                        ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Column(
                                      children: [
                                        if (card['setCode'] != null)
                                          Text(
                                            '[${card['setCode']}]',
                                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                                          ),
                                        Text(
                                          card['name'],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog({}),
        tooltip: 'Aggiungi Carta Manualmente',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(Map<String, dynamic> catalogCard) {
    CardDialogs.showAddCard(
      context: context,
      collectionName: widget.collectionName,
      collectionKey: widget.collectionKey,
      availableAlbums: _availableAlbums,
      allCards: _allOwnedCards,
      initialCatalogCard: catalogCard.isEmpty ? null : catalogCard,
      onCardAdded: () {
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(catalogCard.isEmpty ? 'Carta aggiunta!' : '${catalogCard['name']} aggiunta!')),
        );
      },
      getOrCreateDuplicatesAlbum: () async {
        final albums = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
        final doppioni = albums.where((a) => a.name == 'Doppioni').toList();
        if (doppioni.isNotEmpty) return doppioni.first.id!;
        
        return await _dbHelper.insertAlbum(AlbumModel(
          name: 'Doppioni',
          collection: widget.collectionKey,
          maxCapacity: 999,
        ));
      },
    );
  }
}
