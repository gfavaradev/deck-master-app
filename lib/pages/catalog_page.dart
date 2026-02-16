import 'dart:async';
import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
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
  final DataRepository _dbHelper = DataRepository();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _catalogCards = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  List<AlbumModel> _availableAlbums = [];
  List<CardModel> _allOwnedCards = [];
  String _preferredLanguage = 'EN';

  Timer? _debounce;
  static const int _pageSize = 1000; // Increased for local data performance
  int _currentOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _preferredLanguage = await LanguageService.getPreferredLanguage();
    await Future.wait([
      _loadCards(),
      _loadAlbumsAndOwned(),
    ]);
  }

  /// Load albums and owned cards (only once, not on every search)
  Future<void> _loadAlbumsAndOwned() async {
    final albums = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
    final owned = await _dbHelper.getCardsWithCatalog(widget.collectionKey);
    if (mounted) {
      setState(() {
        _availableAlbums = albums;
        _allOwnedCards = owned;
      });
    }
  }

  /// Load first page of cards (reset)
  Future<void> _loadCards() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _hasMore = true;
    });

    List<Map<String, dynamic>> cards;
    if (widget.collectionKey == 'yugioh') {
      cards = await _dbHelper.getYugiohCatalogCards(
        language: _preferredLanguage,
        query: _searchController.text,
        limit: _pageSize,
        offset: 0,
      );
    } else {
      cards = await _dbHelper.getCatalogCards(widget.collectionKey, query: _searchController.text);
    }

    if (mounted) {
      setState(() {
        _catalogCards = cards;
        _currentOffset = cards.length;
        _hasMore = cards.length >= _pageSize;
        _isLoading = false;
      });
    }
  }

  /// Load next page (append)
  Future<void> _loadMoreCards() async {
    if (_isLoadingMore || !_hasMore || widget.collectionKey != 'yugioh') return;

    setState(() => _isLoadingMore = true);

    final cards = await _dbHelper.getYugiohCatalogCards(
      language: _preferredLanguage,
      query: _searchController.text,
      limit: _pageSize,
      offset: _currentOffset,
    );

    if (mounted) {
      setState(() {
        _catalogCards.addAll(cards);
        _currentOffset += cards.length;
        _hasMore = cards.length >= _pageSize;
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreCards();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _loadCards();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isYugioh = widget.collectionKey == 'yugioh';

    return Scaffold(
      appBar: AppBar(
        title: Text('Catalogo ${widget.collectionName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                    _debounce?.cancel();
                    _loadCards();
                  },
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _catalogCards.isEmpty
                    ? const Center(child: Text('Nessuna carta trovata'))
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.7,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _catalogCards.length + (_hasMore && isYugioh ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loading indicator at the end
                          if (index >= _catalogCards.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }

                          final card = _catalogCards[index];
                          final displayName = isYugioh
                              ? (card['localizedName'] ?? card['name'])
                              : card['name'];
                          final enName = card['name'];
                          final showEnFallback = isYugioh &&
                              card['localizedName'] != null &&
                              card['localizedName'] != card['name'];
                          // Show localized set code for yugioh, fallback to base
                          final displaySetCode = isYugioh
                              ? (card['localizedSetCode'] ?? card['setCode'])
                              : card['setCode'];
                          final displayRarityCode = isYugioh
                              ? (card['localizedRarityCode'] ?? card['rarityCode'])
                              : card['rarityCode'];
                          // Is this a foreign-language print? (found via set code search but not in user's language)
                          final bool isForeignPrint = isYugioh && card['isLocalizedPrint'] == 0;

                          return InkWell(
                            onTap: () => _showAddDialog(card),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildCardPlaceholder(card, isYugioh),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Column(
                                      children: [
                                        if (isForeignPrint)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _detectPrintLanguage(card),
                                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.orange),
                                            ),
                                          ),
                                        if (displaySetCode != null)
                                          Text(
                                            '[$displaySetCode]',
                                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                                          ),
                                        if (displayRarityCode != null && displayRarityCode.toString().isNotEmpty)
                                          Text(
                                            displayRarityCode,
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getRarityColor(displayRarityCode)),
                                          ),
                                        Text(
                                          displayName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (showEnFallback)
                                          Text(
                                            enName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 8, color: Colors.grey),
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
    );
  }

  /// Placeholder instead of downloading images - shows icon and artwork URL as text
  Widget _buildCardPlaceholder(Map<String, dynamic> card, bool isYugioh) {
    final artworkUrl = isYugioh ? card['artwork'] : card['imageUrl'];
    return Container(
      color: Colors.grey.withValues(alpha: 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.style,
            size: 36,
            color: card['isOwned'] == 1 ? Colors.green : Colors.grey,
          ),
          if (artworkUrl != null && artworkUrl.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                artworkUrl.toString().split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 7, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Color _getRarityColor(String? rarityCode) {
    if (rarityCode == null) return Colors.grey;
    final code = rarityCode.toUpperCase();
    if (code.contains('SCR') || code.contains('SER') || code.contains('PSCR')) return Colors.purple;
    if (code.contains('UR') || code == 'UTR') return Colors.amber;
    if (code == 'SR' || code.contains('SPR')) return Colors.orange;
    if (code == 'R' || code.contains('RR')) return Colors.blue;
    if (code == 'C' || code == 'N') return Colors.grey;
    return Colors.grey;
  }

  /// Detect the language of a print based on which localized set_name field is populated
  String _detectPrintLanguage(Map<String, dynamic> card) {
    final setCode = (card['setCode'] ?? '').toString().toUpperCase();
    // Try to detect from set code pattern (e.g., LOB-EN005, LOB-IT005)
    final match = RegExp(r'-([A-Z]{2})\d').firstMatch(setCode);
    if (match != null) {
      final code = match.group(1)!;
      const langMap = {'EN': 'EN', 'IT': 'IT', 'FR': 'FR', 'DE': 'DE', 'PT': 'PT', 'SP': 'ES'};
      if (langMap.containsKey(code)) return langMap[code]!;
    }
    return 'EN';
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
        _loadAlbumsAndOwned();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(catalogCard.isEmpty ? 'Carta aggiunta!' : '${catalogCard['localizedName'] ?? catalogCard['name']} aggiunta!')),
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
