import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
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
  // key: "catalogId-serialNumber-rarity" → total quantity owned (all albums)
  Map<String, int> _ownedQuantityMap = {};
  String _preferredLanguage = 'EN';
  bool _hasUpdate = false;
  bool _isDownloadingUpdate = false;
  double? _downloadProgress;
  DateTime? _downloadStartTime;
  int? _lastUsedAlbumId;
  // Multi-selection state
  bool _isSelectionMode = false;
  Set<String> _selectedCardIds = {}; // Use card IDs instead of indices
  bool _isAdding = false;

  Timer? _debounce;
  String _lastQuery = '';
  StreamSubscription<String>? _syncSub;
  StreamSubscription<String>? _langSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _loadAlbumsAndOwned();
    });
    // Reload catalog immediately when the display language changes
    _langSub = LanguageService.onLanguageChanged.listen((lang) {
      if (mounted) {
        _preferredLanguage = lang;
        _loadCards();
      }
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
    _langSub?.cancel();
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
    if (widget.collectionKey != 'yugioh' && widget.collectionKey != 'onepiece') return;

    try {
      final updateInfo = widget.collectionKey == 'onepiece'
          ? await _dbHelper.checkOnepieceCatalogUpdates()
          : await _dbHelper.checkCatalogUpdates();
      if (!mounted) return;

      final isFirst = updateInfo['isFirstDownload'] == true;
      if (isFirst) {
        // Nessun catalogo locale: avvia il download automaticamente in background
        _downloadUpdate();
      } else if (updateInfo['needsUpdate'] == true) {
        // Aggiornamento disponibile: mostra il banner "Aggiorna"
        setState(() => _hasUpdate = true);
      }
    } catch (_) {}
  }

  /// Download catalog update
  Future<void> _downloadUpdate() async {
    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = null;
      _downloadStartTime = DateTime.now();
    });

    try {
      if (widget.collectionKey == 'onepiece') {
        await _dbHelper.redownloadOnepieceCatalog(
          onProgress: (current, total) {
            if (mounted) setState(() => _downloadProgress = current / total);
          },
          onSaveProgress: (progress) {
            if (mounted) setState(() => _downloadProgress = progress);
          },
        );
      } else {
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
      }

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
    // key: "catalogId-serialNumber" → total quantity across all albums
    final map = <String, int>{};
    for (final c in owned) {
      final key = '${c.catalogId}-${c.serialNumber}';
      map[key] = (map[key] ?? 0) + c.quantity;
    }
    if (mounted) {
      setState(() {
        _availableAlbums = albums;
        _allOwnedCards = owned;
        _ownedQuantityMap = map;
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

  /// Rileva la lingua dal codice seriale digitato (es. "LOB-EN001" → "EN", "SDAZ-IT042" → "IT").
  /// Ritorna null se il pattern non è riconosciuto, così il chiamante usa _preferredLanguage.
  String? _detectLanguageFromQuery(String query) {
    final match = RegExp(r'^[A-Z0-9]+-([A-Z]{2})\d', caseSensitive: false)
        .firstMatch(query.trim());
    if (match == null) return null;
    final code = match.group(1)!.toUpperCase();
    const valid = {'EN', 'IT', 'FR', 'DE', 'PT'};
    return valid.contains(code) ? code : null;
  }

  /// Load a single page of cards
  Future<void> _loadPage() async {
    try {
      final detectedLang = widget.collectionKey == 'yugioh'
          ? _detectLanguageFromQuery(_lastQuery)
          : null;
      final effectiveLanguage = detectedLang ?? _preferredLanguage;

      final cards = await _dbHelper.getCatalogCardsByCollection(
        widget.collectionKey,
        query: _lastQuery,
        language: effectiveLanguage,
        limit: _pageSize,
        offset: _currentOffset,
      );

      if (cards.isEmpty || cards.length < _pageSize) {
        _hasMoreCards = false;
      }

      if (mounted && cards.isNotEmpty) {
        setState(() {
          _catalogCards.addAll(cards);
          _currentOffset += cards.length;
          // Sort by localized setCode ascending (YSKR-IT001, YSKR-IT002, etc.)
          _catalogCards.sort((a, b) {
            final setCodeA = (a['localizedSetCode'] ?? a['setCode'] ?? '').toString();
            final setCodeB = (b['localizedSetCode'] ?? b['setCode'] ?? '').toString();
            return setCodeA.compareTo(setCodeB);
          });
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
    final setCode = (card['localizedSetCode'] ?? card['setCode'])?.toString() ?? '';
    final rarityCode = (card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'])?.toString() ?? '';
    final artwork = card['artwork']?.toString() ?? '0';
    return '$id-$setCode-$rarityCode-$artwork';
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
    if (_isAdding || _selectedCardIds.isEmpty) return;
    setState(() => _isAdding = true);

    try {
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

      // Show progress dialog for multiple cards
      ValueNotifier<int>? progressNotifier;
      final totalToAdd = limitedCards.length;
      if (totalToAdd > 1 && mounted) {
        progressNotifier = ValueNotifier<int>(0);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Aggiunta in corso...'),
              content: ValueListenableBuilder<int>(
                valueListenable: progressNotifier!,
                builder: (context, progress, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: totalToAdd > 0 ? progress / totalToAdd : null,
                      ),
                      const SizedBox(height: 12),
                      Text('$progress / $totalToAdd carte elaborate'),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }

      // Add cards to collection; route duplicates to Doppioni (same logic as single-card add)
      int addedCount = 0;
      int updatedCount = 0;
      int doppioniCount = 0;
      int? doppioniAlbumId;

      for (final card in limitedCards) {
        try {
          final catalogId = card['id']?.toString();
          final name = card['localizedName'] ?? card['name'] ?? 'Unknown';
          final serialNumber = card['localizedSetCode'] ?? card['setCode'] ?? '';
          final rarity = card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'] ?? '';

          // Check if this exact print exists in ANY album across the whole collection
          final existingAnywhere = await _dbHelper.findOwnedInstances(
            widget.collectionKey, name, serialNumber, rarity,
          );

          if (existingAnywhere.isNotEmpty) {
            // Already owned → route to Doppioni
            doppioniAlbumId ??= await _getOrCreateDoppioniAlbum();
            final existingInDoppioni = existingAnywhere
                .where((c) => c.albumId == doppioniAlbumId)
                .toList();
            if (existingInDoppioni.isNotEmpty) {
              await _dbHelper.updateCard(existingInDoppioni.first.copyWith(
                quantity: existingInDoppioni.first.quantity + 1,
              ));
            } else {
              await _dbHelper.insertCard(CardModel(
                catalogId: catalogId,
                name: name,
                serialNumber: serialNumber,
                collection: widget.collectionKey,
                albumId: doppioniAlbumId,
                type: card['type'] ?? card['card_type'] ?? '',
                rarity: rarity,
                description: card['localizedDescription'] ?? card['description'] ?? '',
                imageUrl: card['artwork'] ?? card['imageUrl'],
                value: ((card['localizedSetPrice'] ?? card['setPrice'] ?? card['marketPrice']) as num?)?.toDouble() ?? 0.0,
              ));
            }
            doppioniCount++;
          } else {
            // Not yet owned → add to selected album (increment if already there)
            final existingInAlbum = await _dbHelper.findCardInAlbum(
              selectedAlbum.id!, catalogId, serialNumber, rarity,
            );
            if (existingInAlbum != null) {
              await _dbHelper.updateCard(
                existingInAlbum.copyWith(quantity: existingInAlbum.quantity + 1),
              );
              updatedCount++;
            } else {
              await _dbHelper.insertCard(CardModel(
                catalogId: catalogId,
                name: name,
                serialNumber: serialNumber,
                collection: widget.collectionKey,
                albumId: selectedAlbum.id!,
                type: card['type'] ?? card['card_type'] ?? '',
                rarity: rarity,
                description: card['localizedDescription'] ?? card['description'] ?? '',
                imageUrl: card['artwork'] ?? card['imageUrl'],
                value: ((card['localizedSetPrice'] ?? card['setPrice'] ?? card['marketPrice']) as num?)?.toDouble() ?? 0.0,
              ));
              addedCount++;
            }
          }
        } catch (e) {
          debugPrint('Error adding card: $e');
        }
        progressNotifier?.value++;
      }

      // Close progress dialog
      if (progressNotifier != null && mounted) {
        Navigator.pop(context);
        progressNotifier.dispose();
      }

      if (mounted) {
        final parts = <String>[];
        if (addedCount > 0) parts.add('$addedCount aggiunte');
        if (updatedCount > 0) parts.add('$updatedCount quantità aggiornate');
        if (doppioniCount > 0) parts.add('$doppioniCount nei Doppioni');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(parts.isNotEmpty ? parts.join(', ') : 'Nessuna modifica'),
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
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<int> _getOrCreateDoppioniAlbum() async {
    final albums = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
    final existing = albums.where((a) => a.name == 'Doppioni').toList();
    if (existing.isNotEmpty) return existing.first.id!;
    return await _dbHelper.insertAlbum(AlbumModel(
      name: 'Doppioni',
      collection: widget.collectionKey,
      maxCapacity: 1000,
    ));
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
                          final bool isOnePiece = widget.collectionKey == 'onepiece';
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
                              : isOnePiece
                                  ? card['rarity']
                                  : card['rarityCode'];
                          final displayRarityFull = isYugioh
                              ? (card['localizedRarity'] ?? card['setRarity'] ?? displayRarityCode)
                              : isOnePiece
                                  ? card['rarity']
                                  : (card['localizedRarity'] ?? card['setRarity'] ?? card['rarity'] ?? displayRarityCode);
                          // Is this a foreign-language print? (found via set code search but not in user's language)
                          final bool isForeignPrint = isYugioh && card['isLocalizedPrint'] == 0;
                          final String ownedKey =
                              '${card['id']}-${card['localizedSetCode'] ?? card['setCode'] ?? ''}';
                          final int ownedQty = _ownedQuantityMap[ownedKey] ?? 0;

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
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            _buildCardImage(card, isYugioh),
                                            if (ownedQty > 0)
                                              Positioned(
                                                bottom: 4,
                                                right: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.shade700,
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    'x$ownedQty',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
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
                                            if (displaySetCode != null && displayRarityFull != null && displayRarityFull.toString().isNotEmpty)
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: '$displaySetCode • ',
                                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                                                    ),
                                                    TextSpan(
                                                      text: displayRarityFull.toString(),
                                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getRarityColor(displayRarityCode?.toString())),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else if (displaySetCode != null)
                                              Text(
                                                displaySetCode,
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                                              )
                                            else if (displayRarityFull != null && displayRarityFull.toString().isNotEmpty)
                                              Text(
                                                displayRarityFull.toString(),
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getRarityColor(displayRarityCode?.toString())),
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
              onPressed: _isAdding ? null : _addSelectedToCollection,
              icon: _isAdding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_isAdding ? 'Aggiungendo...' : 'Aggiungi ${_selectedCardIds.length}'),
              backgroundColor: _isAdding ? Colors.grey : Colors.deepPurple,
            ),
          ),
      ],
    );
  }

  Widget _buildCardImage(Map<String, dynamic> card, bool isYugioh) {
    final imageUrl = card['artwork'] as String?;
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
      placeholder: (_, _) => Container(
        color: Colors.grey.withValues(alpha: 0.08),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, _, _) => Container(
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

  void _showSetCompletedDialog(Map<String, dynamic> completion, int currentAlbumId) {
    final setName = completion['setName'] as String? ?? '';
    final setIdentifier = (completion['setCode'] as String?) ?? setName;
    final total = completion['totalCards'] as int? ?? 0;
    int? selectedAlbumId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(child: Text('Set completato!', style: const TextStyle(fontSize: 18))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$setName" è completo ($total / $total carte).',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Vuoi spostare tutte le carte di questo set in un album diverso?'),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selectedAlbumId,
                decoration: const InputDecoration(labelText: 'Sposta in album', isDense: true),
                hint: const Text('Mantieni album corrente'),
                items: _availableAlbums.map((album) {
                  return DropdownMenuItem<int>(
                    value: album.id,
                    child: Text('${album.name} (${album.currentCount}/${album.maxCapacity})'),
                  );
                }).toList(),
                onChanged: (val) => setDialogState(() => selectedAlbumId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
            if (selectedAlbumId != null)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _dbHelper.moveSetCardsToAlbum(widget.collectionKey, setIdentifier, selectedAlbumId!);
                  await _loadAlbumsAndOwned();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Carte di "$setName" spostate!')),
                    );
                  }
                },
                child: const Text('Sposta'),
              ),
          ],
        ),
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
      lastUsedAlbumId: _lastUsedAlbumId,
      initialCatalogCard: catalogCard.isEmpty ? null : catalogCard,
      onCardAdded: (int usedAlbumId, String serialNumber) async {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('last_album_id_${widget.collectionKey}', usedAlbumId);
        });
        setState(() => _lastUsedAlbumId = usedAlbumId);
        await _loadAlbumsAndOwned();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(catalogCard.isEmpty ? 'Carta aggiunta!' : '${catalogCard['localizedName'] ?? catalogCard['name']} aggiunta!')),
        );
        // Controlla se il set è stato completato al 100%
        final completion = await _dbHelper.checkSetCompletion(widget.collectionKey, serialNumber);
        if (completion != null && mounted) {
          _showSetCompletedDialog(completion, usedAlbumId);
        }
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
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        border: Border(bottom: BorderSide(color: AppColors.gold.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update, color: AppColors.gold, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aggiornamento disponibile',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Il catalogo è stato aggiornato',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _downloadUpdate,
            icon: const Icon(Icons.download, size: 16, color: Colors.black),
            label: const Text('Aggiorna', style: TextStyle(color: Colors.black)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// Build download progress indicator
  Widget _buildDownloadProgress() {
    String? timeLabel;
    if (_downloadProgress != null && _downloadProgress! > 0.02 && _downloadStartTime != null) {
      final elapsed = DateTime.now().difference(_downloadStartTime!).inSeconds;
      final totalEstSec = (elapsed / _downloadProgress!).round();
      final remaining = totalEstSec - elapsed;
      if (remaining > 0) {
        timeLabel = remaining < 60
            ? '~$remaining sec rimanenti'
            : '~${(remaining / 60).ceil()} min rimanenti';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        border: Border(bottom: BorderSide(color: AppColors.gold.withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Download catalogo in corso...',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              if (_downloadProgress != null)
                Text(
                  '${(_downloadProgress! * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _downloadProgress,
            backgroundColor: AppColors.bgLight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
          if (timeLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              timeLabel,
              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }
}
