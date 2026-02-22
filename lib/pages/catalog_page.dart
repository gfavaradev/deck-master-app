import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../services/sync_service.dart';
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
  bool _hasMoreCards = true;
  int _currentOffset = 0;
  static const int _pageSize = 100; // Carica 100 carte alla volta

  List<AlbumModel> _availableAlbums = [];
  List<CardModel> _allOwnedCards = [];
  String _preferredLanguage = 'EN';
  bool _hasUpdate = false;
  bool _isDownloadingUpdate = false;
  double? _downloadProgress;
  int? _lastUsedAlbumId;

  // Multi-selection state
  bool _isSelectionMode = false;
  Set<String> _selectedCardIds = {}; // Use card IDs instead of indices

  Timer? _debounce;
  String _lastQuery = '';
  StreamSubscription<String>? _syncSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _loadAlbumsAndOwned();
    });
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMoreCards) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8; // Carica quando arrivi all'80%

    if (currentScroll >= threshold) {
      _loadMoreCards();
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _preferredLanguage = await LanguageService.getPreferredLanguage();
    final prefs = await SharedPreferences.getInstance();
    _lastUsedAlbumId = prefs.getInt('last_album_id_${widget.collectionKey}');
    await Future.wait([
      _loadCards(),
      _loadAlbumsAndOwned(),
      _checkForUpdates(),
    ]);
  }

  /// Check if there's a catalog update available
  Future<void> _checkForUpdates() async {
    if (widget.collectionKey != 'yugioh') return;

    try {
      final updateInfo = await _dbHelper.checkCatalogUpdates();
      if (mounted) {
        setState(() {
          _hasUpdate = updateInfo['needsUpdate'] == true;
        });
      }
    } catch (_) {}
  }

  /// Download catalog update
  Future<void> _downloadUpdate() async {
    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = null;
    });

    try {
      await _dbHelper.redownloadYugiohCatalog(
        onProgress: (current, total) {
          if (mounted) {
            setState(() => _downloadProgress = current / total);
          }
        },
        onSaveProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
          _downloadProgress = null;
          _hasUpdate = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogo aggiornato con successo!')),
        );

        // Reload cards after update
        await _loadCards();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
          _downloadProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore aggiornamento: $e')),
        );
      }
    }
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

  /// Load first page of cards with pagination
  Future<void> _loadCards() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _catalogCards = [];
      _hasMoreCards = true;
      _lastQuery = _searchController.text;
    });

    await _loadPage();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load more cards (infinite scroll)
  Future<void> _loadMoreCards() async {
    if (_isLoadingMore || !_hasMoreCards) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _loadPage();

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  /// Load a single page of cards
  Future<void> _loadPage() async {
    try {
      List<Map<String, dynamic>> cards;

      if (widget.collectionKey == 'yugioh') {
        cards = await _dbHelper.getYugiohCatalogCards(
          language: _preferredLanguage,
          query: _lastQuery,
          limit: _pageSize,
          offset: _currentOffset,
        );
      } else {
        // For non-yugioh, load all at once (usually smaller catalogs)
        if (_currentOffset == 0) {
          cards = await _dbHelper.getCatalogCards(widget.collectionKey, query: _lastQuery);
          _hasMoreCards = false;
        } else {
          cards = [];
        }
      }

      if (cards.isEmpty || cards.length < _pageSize) {
        _hasMoreCards = false;
      }

      if (mounted && cards.isNotEmpty) {
        setState(() {
          _catalogCards.addAll(cards);
          _currentOffset += cards.length;
        });

        // Sort by localized setCode ascending (YSKR-IT001, YSKR-IT002, etc.)
        _catalogCards.sort((a, b) {
          final setCodeA = (a['localizedSetCode'] ?? a['setCode'] ?? '').toString();
          final setCodeB = (b['localizedSetCode'] ?? b['setCode'] ?? '').toString();
          return setCodeA.compareTo(setCodeB); // Ascending order
        });
      }
    } catch (e) {
      debugPrint('Error loading cards: $e');
      _hasMoreCards = false;
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _loadCards();
    });
  }

  String _getCardKey(Map<String, dynamic> card) {
    final id = card['id']?.toString() ?? '';
    final setCode = card['setCode']?.toString() ?? '';
    final rarityCode = card['rarityCode']?.toString() ?? card['rarity']?.toString() ?? '';
    return '$id-$setCode-$rarityCode';
  }

  void _toggleSelection(Map<String, dynamic> card) {
    final cardKey = _getCardKey(card);
    setState(() {
      if (_selectedCardIds.contains(cardKey)) {
        _selectedCardIds.remove(cardKey);
        if (_selectedCardIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedCardIds.add(cardKey);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedCardIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _addSelectedToCollection() async {
    if (_selectedCardIds.isEmpty) return;

    // Get selected cards by matching keys
    final selectedCards = _catalogCards
        .where((card) => _selectedCardIds.contains(_getCardKey(card)))
        .toList();

    // Sort albums: last used first, rest in original order
    final sortedAlbums = List<AlbumModel>.from(_availableAlbums);
    if (_lastUsedAlbumId != null) {
      sortedAlbums.sort((a, b) {
        if (a.id == _lastUsedAlbumId) return -1;
        if (b.id == _lastUsedAlbumId) return 1;
        return 0;
      });
    }

    // Show album selection dialog
    final selectedAlbum = await showDialog<AlbumModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleziona Album'),
        content: SizedBox(
          width: double.maxFinite,
          child: sortedAlbums.isEmpty
              ? const Text('Nessun album disponibile. Creane uno prima.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: sortedAlbums.length,
                  itemBuilder: (context, index) {
                    final album = sortedAlbums[index];
                    final isLastUsed = album.id == _lastUsedAlbumId;
                    return ListTile(
                      leading: Icon(
                        isLastUsed ? Icons.star : Icons.photo_album,
                        color: isLastUsed ? Colors.amber : null,
                      ),
                      title: Text(album.name),
                      subtitle: isLastUsed
                          ? const Text('Ultimo usato',
                              style: TextStyle(fontSize: 11, color: Colors.amber))
                          : null,
                      onTap: () => Navigator.pop(context, album),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );

    if (selectedAlbum == null) return;

    // Check album capacity before adding
    final currentCount = await _dbHelper.getCardCountByAlbum(selectedAlbum.id!);
    final remaining = selectedAlbum.maxCapacity - currentCount;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Album "${selectedAlbum.name}" è pieno ($currentCount/${selectedAlbum.maxCapacity}).'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final cardsToAdd = selectedCards.length > remaining ? remaining : selectedCards.length;
    final limitedCards = selectedCards.sublist(0, cardsToAdd);
    if (cardsToAdd < selectedCards.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Album quasi pieno: aggiunte solo $cardsToAdd/${selectedCards.length} carte.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    // Add cards to collection; increment quantity if the same print already exists
    int addedCount = 0;
    int updatedCount = 0;
    for (final card in limitedCards) {
      try {
        final catalogId = card['id']?.toString();
        final serialNumber = card['localizedSetCode'] ?? card['setCode'] ?? '';

        final existing = await _dbHelper.findCardInAlbum(selectedAlbum.id!, catalogId, serialNumber);
        if (existing != null) {
          await _dbHelper.updateCard(existing.copyWith(quantity: existing.quantity + 1));
          updatedCount++;
        } else {
          final cardModel = CardModel(
            catalogId: catalogId,
            name: card['localizedName'] ?? card['name'] ?? 'Unknown',
            serialNumber: serialNumber,
            collection: widget.collectionKey,
            albumId: selectedAlbum.id!,
            type: card['type'] ?? '',
            rarity: card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'] ?? '',
            description: card['localizedDescription'] ?? card['description'] ?? '',
            imageUrl: card['artwork'] ?? card['imageUrl'],
          );
          await _dbHelper.insertCard(cardModel);
          addedCount++;
        }
      } catch (e) {
        debugPrint('Error adding card: $e');
      }
    }

    if (mounted) {
      final parts = <String>[];
      if (addedCount > 0) parts.add('$addedCount aggiunte');
      if (updatedCount > 0) parts.add('$updatedCount quantità aggiornate');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${parts.join(', ')} in "${selectedAlbum.name}"'),
          backgroundColor: Colors.green,
        ),
      );

      // Remember last used album
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_album_id_${widget.collectionKey}', selectedAlbum.id!);
      setState(() => _lastUsedAlbumId = selectedAlbum.id);

      // Clear selection and reload
      _clearSelection();
      await _loadAlbumsAndOwned();
      await _loadCards();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            if (_isSelectionMode) _buildSelectionBanner(),
            if (_hasUpdate) _buildUpdateBanner(),
            if (_isDownloadingUpdate) _buildDownloadProgress(),
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
          // Card count indicator
          if (!_isLoading && _catalogCards.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_catalogCards.length} carte caricate',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (!_hasMoreCards && _catalogCards.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '• Fine catalogo',
                      style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
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
                          crossAxisCount: 2,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _catalogCards.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loading indicator at the end
                          if (index >= _catalogCards.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final card = _catalogCards[index];
                          final bool isYugioh = widget.collectionKey == 'yugioh';
                          final bool isSelected = _selectedCardIds.contains(_getCardKey(card));
                          final displayName = isYugioh
                              ? (card['localizedName'] ?? card['name'])
                              : card['name'];
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
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(card);
                              } else {
                                _showAddDialog(card);
                              }
                            },
                            onLongPress: () => _toggleSelection(card),
                            child: Stack(
                              children: [
                                Card(
                                  elevation: isSelected ? 8 : 1,
                                  color: isSelected
                                      ? Colors.deepPurple.withValues(alpha: 0.1)
                                      : null,
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _buildCardImage(card, isYugioh),
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
                                            if (displaySetCode != null && displayRarityCode != null && displayRarityCode.toString().isNotEmpty)
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: '$displaySetCode • ',
                                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                                                    ),
                                                    TextSpan(
                                                      text: displayRarityCode,
                                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getRarityColor(displayRarityCode)),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else if (displaySetCode != null)
                                              Text(
                                                displaySetCode,
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                                              )
                                            else if (displayRarityCode != null && displayRarityCode.toString().isNotEmpty)
                                              Text(
                                                displayRarityCode,
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getRarityColor(displayRarityCode)),
                                              ),
                                            SizedBox(
                                              height: 16,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  displayName,
                                                  maxLines: 1,
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Selection checkbox overlay
                                if (_isSelectionMode)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => _toggleSelection(card),
                                        activeColor: Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
        ),
        if (_isSelectionMode && _selectedCardIds.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _addSelectedToCollection,
              icon: const Icon(Icons.add),
              label: Text('Aggiungi ${_selectedCardIds.length}'),
              backgroundColor: Colors.deepPurple,
            ),
          ),
      ],
    );
  }

  Widget _buildCardImage(Map<String, dynamic> card, bool isYugioh) {
    final imageUrl = card['imageUrl'] as String?;
    final isOwned = card['isOwned'] == 1;
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.withValues(alpha: 0.08),
        child: Center(
          child: Icon(Icons.style, size: 36, color: isOwned ? Colors.green : Colors.grey),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: Colors.grey.withValues(alpha: 0.08),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => Container(
        color: Colors.grey.withValues(alpha: 0.08),
        child: Center(
          child: Icon(Icons.style, size: 36, color: isOwned ? Colors.green : Colors.grey),
        ),
      ),
    );
  }

  Color _getRarityColor(String? rarityCode) {
    if (rarityCode == null) return Colors.grey;
    final code = rarityCode.toUpperCase();

    // Map of rarity codes to colors (ordered from common to rarest)
    const rarityColors = {
      // Common/Normal
      'C': Color(0xFF757575),           // Grey 600
      'N': Color(0xFF9E9E9E),           // Grey 500
      'COMMON': Color(0xFF757575),

      // Short Print
      'SP': Color(0xFF6D4C41),          // Brown 600
      'SHORT PRINT': Color(0xFF6D4C41),

      // Rare variants
      'R': Color(0xFF1976D2),           // Blue 700
      'RARE': Color(0xFF1976D2),
      'RR': Color(0xFF1565C0),          // Blue 800

      // Super Rare
      'SR': Color(0xFF00ACC1),          // Cyan 600
      'SUPER RARE': Color(0xFF00ACC1),
      'SHR': Color(0xFF0097A7),         // Cyan 700 - Shatterfoil
      'SHATTERFOIL RARE': Color(0xFF0097A7),

      // Ultra Rare
      'UR': Color(0xFFFFB300),          // Amber 700
      'ULTRA RARE': Color(0xFFFFB300),
      'UTR': Color(0xFFFF6F00),         // Orange 900 - Ultimate Rare
      'ULTIMATE RARE': Color(0xFFFF6F00),

      // Secret Rare variants
      'SCR': Color(0xFF7B1FA2),         // Purple 700
      'SECRET RARE': Color(0xFF7B1FA2),
      'PSCR': Color(0xFF6A1B9A),        // Purple 800 - Prismatic Secret
      'PRISMATIC SECRET RARE': Color(0xFF6A1B9A),
      'USCR': Color(0xFF4A148C),        // Purple 900 - Ultra Secret
      'ULTRA SECRET RARE': Color(0xFF4A148C),
      '20SCR': Color(0xFF8E24AA),       // Purple 600 - 20th Secret
      '20TH SECRET RARE': Color(0xFF8E24AA),
      'QCSR': Color(0xFFAB47BC),        // Purple 400 - Quarter Century Secret
      'QUARTER CENTURY SECRET RARE': Color(0xFFAB47BC),

      // Premium variants
      'GR': Color(0xFFB0BEC5),          // Blue Grey 200 - Ghost Rare
      'GHOST RARE': Color(0xFFB0BEC5),
      'SLR': Color(0xFFEC407A),         // Pink 400 - Starlight Rare
      'STARLIGHT RARE': Color(0xFFEC407A),
      'CR': Color(0xFFE91E63),          // Pink 500 - Collectors Rare
      'COLLECTORS RARE': Color(0xFFE91E63),

      // Parallel/Mosaic
      'PR': Color(0xFF26A69A),          // Teal 400 - Parallel Rare
      'PARALLEL RARE': Color(0xFF26A69A),
      'MSR': Color(0xFF00897B),         // Teal 600 - Mosaic Rare
      'MOSAIC RARE': Color(0xFF00897B),
      'DNR': Color(0xFF00796B),         // Teal 700 - Duel Terminal Normal Parallel
      'DUEL TERMINAL NORMAL PARALLEL RARE': Color(0xFF00796B),
      'DT': Color(0xFF00695C),          // Teal 800 - Duel Terminal

      // Gold/Premium Gold
      'GUR': Color(0xFFFFD54F),         // Amber 300 - Gold Rare
      'GOLD RARE': Color(0xFFFFD54F),
      'GScR': Color(0xFFFFC107),        // Amber 500 - Gold Secret
      'GOLD SECRET RARE': Color(0xFFFFC107),
      'PIR': Color(0xFFFFECB3),         // Amber 100 - Premium Gold
      'PREMIUM GOLD RARE': Color(0xFFFFECB3),

      // Special editions
      'HL': Color(0xFFFF7043),          // Deep Orange 400 - Hobby League
      'C1': Color(0xFF8D6E63),          // Brown 300 - Championship
      'C2': Color(0xFFA1887F),          // Brown 200
      'C3': Color(0xFFBCAAA4),          // Brown 100
      'SER': Color(0xFFD32F2F),         // Red 700 - Super Short Print
      'EXTRA SECRET RARE': Color(0xFFD32F2F),

      // Oversized/Special
      'OVERSIZE': Color(0xFF5E35B1),    // Deep Purple 600
      'TKN': Color(0xFF9575CD),         // Deep Purple 300 - Token
      'TOKEN': Color(0xFF9575CD),

      // Astral/Other special
      'ASR': Color(0xFF42A5F5),         // Blue 400 - Astral Rare
      'PHARAOHS RARE': Color(0xFFFDD835), // Yellow 600
      'MILLENNIUM RARE': Color(0xFFFBC02D), // Yellow 700
      'ULTRA RARE (PHARAOHS RARE)': Color(0xFFF9A825), // Yellow 800
      'PLATINUM RARE': Color(0xFFCFD8DC), // Blue Grey 100
      'PLATINUM SECRET RARE': Color(0xFFECEFF1), // Blue Grey 50
    };

    // Try exact match first
    if (rarityColors.containsKey(code)) {
      return rarityColors[code]!;
    }

    // Try partial matches for complex codes
    for (var entry in rarityColors.entries) {
      if (code.contains(entry.key)) {
        return entry.value;
      }
    }

    // Default to grey if unknown
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
      lastUsedAlbumId: _lastUsedAlbumId,
      initialCatalogCard: catalogCard.isEmpty ? null : catalogCard,
      onCardAdded: (int usedAlbumId) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('last_album_id_${widget.collectionKey}', usedAlbumId);
        });
        setState(() => _lastUsedAlbumId = usedAlbumId);
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

  /// Selection mode banner shown instead of AppBar
  Widget _buildSelectionBanner() {
    return Container(
      color: Colors.deepPurple,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _clearSelection,
          ),
          Expanded(
            child: Text(
              '${_selectedCardIds.length} carte selezionate',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.select_all, color: Colors.white),
            onPressed: () {
              setState(() {
                if (_selectedCardIds.length == _catalogCards.length) {
                  _selectedCardIds.clear();
                  _isSelectionMode = false;
                } else {
                  _selectedCardIds = Set.from(
                    _catalogCards.map((card) => _getCardKey(card)),
                  );
                }
              });
            },
            tooltip: 'Seleziona tutto',
          ),
        ],
      ),
    );
  }

  /// Build update available banner
  Widget _buildUpdateBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aggiornamento disponibile',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Il catalogo è stato aggiornato dall\'amministratore',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _downloadUpdate,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Aggiorna'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// Build download progress indicator
  Widget _buildDownloadProgress() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Scaricando aggiornamenti...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              if (_downloadProgress != null)
                Text(
                  '${(_downloadProgress! * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (_downloadProgress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _downloadProgress),
          ],
        ],
      ),
    );
  }
}
