import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/catalog_download_service.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/card_dialogs.dart';
import '../widgets/language_flag.dart';
import '../models/album_model.dart';
import '../models/card_model.dart';
import '../models/wishlist_model.dart';
import 'card_detail_page.dart';

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
  // key: "catalogId-serialNumber" → total quantity owned (all albums)
  Map<String, int> _ownedQuantityMap = {};
  String _preferredLanguage = 'EN';
  List<String> _supportedLanguages = [];   // tutte le lingue per questa collezione
  Set<String> _availableCatalogLanguages = {'EN'}; // lingue con dati reali nel DB
  bool _isDownloadingUpdate = false;
  bool _isCatalogMissing = false; // true = nessun catalogo locale, bisogna scaricarlo
  double? _downloadProgress; // null = connecting, 0.0-1.0 = downloading/saving
  String _downloadMessage = '';
  String? _loadError;
  int? _lastUsedAlbumId;
  // Multi-selection state
  bool _isSelectionMode = false;
  Set<String> _selectedCardIds = {}; // Use card IDs instead of indices
  bool _isAdding = false;
  Set<String> _wishlistCatalogIds = {};

  Timer? _debounce;
  String _lastQuery = '';
  StreamSubscription<String>? _syncSub;
  StreamSubscription<String>? _langSub;
  StreamSubscription<CatalogDownloadState>? _dlSub;
  StreamSubscription<CatalogDownloadOutcome>? _dlOutcomeSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
    // Un download può essere già in corso da prima che questa pagina esistesse
    // (avviato dalla home, o lasciato indietro uscendo dalla collezione): si
    // parte dallo stato corrente e poi si seguono gli aggiornamenti. Il
    // riallineamento va dopo il primo frame, non qui: `_onDownloadState`
    // risolve `AppLocalizations` dal context, e in `initState` non si possono
    // ancora leggere gli InheritedWidget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onDownloadState(CatalogDownloadService().state);
    });
    _dlSub = CatalogDownloadService().onStateChanged.listen(_onDownloadState);
    _dlOutcomeSub =
        CatalogDownloadService().onFinished.listen(_onDownloadFinished);
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _loadAlbumsAndOwned();
    });
    // Reload catalog immediately when the display language changes for this collection
    _langSub = LanguageService.onLanguageChanged.listen((event) {
      final parts = event.split(':');
      if (parts.length == 2 && parts[0] == widget.collectionKey && mounted) {
        _preferredLanguage = parts[1];
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
    // Solo le sottoscrizioni: il download vive nel servizio e prosegue.
    _dlSub?.cancel();
    _dlOutcomeSub?.cancel();
    _syncSub?.cancel();
    _langSub?.cancel();
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _preferredLanguage = await LanguageService.getPreferredLanguageForCollection(widget.collectionKey);
    final prefs = await SharedPreferences.getInstance();
    _lastUsedAlbumId = prefs.getInt('last_album_id_${widget.collectionKey}');
    _supportedLanguages = LanguageService.collectionLanguages[widget.collectionKey] ?? [];

    // Ogni task è isolato con il proprio fallback: se uno fallisce (es. una
    // query su una tabella appena migrata/non ancora pronta) non deve
    // impedire agli altri di completare — altrimenti l'intero Future.wait
    // si interrompe e sia il rilevamento "catalogo mancante" sia le lingue
    // disponibili restano al loro valore iniziale, mostrando dati scorretti.
    final results = await Future.wait<dynamic>([
      _loadCards(),
      _loadAlbumsAndOwned(),
      _checkCatalogMissing(),
      _dbHelper.getAvailableCatalogLanguages(widget.collectionKey)
          .catchError((_) => <String>{'EN'}),
      _dbHelper.getAllWishlistCatalogIds()
          .catchError((_) => <String>{}),
    ]);
    if (mounted) {
      setState(() => _wishlistCatalogIds = results[4] as Set<String>);
    }

    if (mounted) {
      setState(() => _availableCatalogLanguages = results[3] as Set<String>);
    }

    // The saved/detected preferred language (LanguageService) only knows which
    // languages a TCG theoretically supports, not which ones the just-downloaded
    // catalog actually has data for — e.g. the device locale is IT and IT is in
    // Digimon's theoretical language list, but the catalog was downloaded before
    // translations were generated. Reconcile against the real DB check so the
    // flag/label shown always matches an actually-available language.
    if (mounted && !_availableCatalogLanguages.contains(_preferredLanguage.toUpperCase())) {
      final corrected = _availableCatalogLanguages.contains('EN')
          ? 'EN'
          : (_availableCatalogLanguages.isNotEmpty ? _availableCatalogLanguages.first : 'EN');
      if (corrected != _preferredLanguage) {
        setState(() => _preferredLanguage = corrected);
        _loadCards();
      }
    }

    // Fallback: if the Firestore check didn't flag the catalog as missing but
    // there are actually zero cards in the local DB, show the download button.
    // We check the real DB count (not the filtered search result) so this
    // doesn't trigger when the user searches for something with no matches.
    if (mounted && _isSupportedCollection && !_isCatalogMissing) {
      final totalInDb = await _dbHelper.getCatalogCardCount(widget.collectionKey);
      if (mounted && totalInDb == 0) {
        setState(() => _isCatalogMissing = true);
      }
    }
  }

  bool get _isSupportedCollection {
    const supported = {
      'yugioh', 'pokemon', 'onepiece', 'magic',
      'digimon', 'lorcana', 'flesh-and-blood', 'vanguard',
      'dragon-ball-super', 'star-wars', 'riftbound', 'gundam', 'union-arena',
    };
    return supported.contains(widget.collectionKey);
  }

  /// Controlla se il catalogo locale è assente (primo download).
  /// Gli aggiornamenti vengono segnalati nelle Notifiche, non qui.
  Future<void> _checkCatalogMissing() async {
    try {
      final Map<String, dynamic> updateInfo;
      switch (widget.collectionKey) {
        case 'yugioh':
          updateInfo = await _dbHelper.checkCatalogUpdates();
        case 'onepiece':
          updateInfo = await _dbHelper.checkOnepieceCatalogUpdates();
        case 'pokemon':
          updateInfo = await _dbHelper.checkPokemonCatalogUpdates();
        case 'magic':
          updateInfo = await _dbHelper.checkMagicCatalogUpdates();
        default:
          // Cataloghi v36 generici (Digimon, Lorcana, FAB, ecc.)
          updateInfo = await _dbHelper.checkGenericCatalogUpdates(widget.collectionKey);
      }
      if (!mounted) return;
      if (updateInfo['needsUpdate'] == true && updateInfo['isFirstDownload'] == true) {
        setState(() => _isCatalogMissing = true);
      }
    } catch (_) {}
  }


  Color get _themeAccent => AppColors.forCollection(widget.collectionKey);

  IconData get _themeIcon => switch (widget.collectionKey) {
    'yugioh'            => Icons.auto_fix_high_rounded,
    'pokemon'           => Icons.catching_pokemon_rounded,
    'onepiece'          => Icons.sailing_rounded,
    'magic'             => Icons.auto_awesome,
    'digimon'           => Icons.device_hub,
    'dragon-ball-super' => Icons.electric_bolt,
    'lorcana'           => Icons.castle,
    'flesh-and-blood'   => Icons.shield_outlined,
    'vanguard'          => Icons.military_tech,
    'star-wars'         => Icons.star_outlined,
    'riftbound'         => Icons.blur_on,
    'gundam'            => Icons.smart_toy,
    'union-arena'       => Icons.sports_kabaddi,
    _                   => Icons.style_outlined,
  };

  String _phaseMessage(String phase) {
    final l10n = AppLocalizations.of(context)!;
    return switch (widget.collectionKey) {
      'yugioh' => switch (phase) {
        'connecting'  => l10n.downloadYugiohConnecting,
        'downloading' => l10n.downloadYugiohDownloading,
        _             => l10n.downloadYugiohSaving,
      },
      'pokemon' => switch (phase) {
        'connecting'  => l10n.downloadPokemonConnecting,
        'downloading' => l10n.downloadPokemonDownloading,
        _             => l10n.downloadPokemonSaving,
      },
      'onepiece' => switch (phase) {
        'connecting'  => l10n.downloadOnepieceConnecting,
        'downloading' => l10n.downloadOnepieceDownloading,
        _             => l10n.downloadOnepieceSaving,
      },
      'magic' => switch (phase) {
        'connecting'  => l10n.downloadMagicConnecting,
        'downloading' => l10n.downloadMagicDownloading,
        _             => l10n.downloadMagicSaving,
      },
      _ => switch (phase) {
        'connecting'  => l10n.downloadPhaseConnecting,
        'downloading' => l10n.downloadPhaseDownloading,
        _             => l10n.downloadPhaseSaving,
      },
    };
  }

  /// Download del catalogo (solo per primo download da empty state).
  ///
  /// Il ciclo vive in [CatalogDownloadService], non qui: questa pagina viene
  /// smontata appena si esce dalla collezione, e prima con lei spariva ogni
  /// traccia del download — che intanto continuava a girare, invisibile.
  Future<void> _downloadUpdate() async {
    if (CatalogDownloadService().state.isRunning) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.catalogDownloadBusy),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    await CatalogDownloadService().start(
      updates: [
        {
          'collectionKey': widget.collectionKey,
          'collectionName': widget.collectionName,
        }
      ],
      labels: CatalogDownloadLabels(
        notificationTitle: l10n.downloadTitle,
        starting: l10n.downloadStarting,
        operationName: l10n.downloadCatalog,
        perCatalog: l10n.downloadCollectionProgress,
        perCatalogPct: l10n.downloadCollectionProgressPct,
        singlePct: l10n.downloadProgressPct,
      ),
    );
  }

  /// Riflette sullo stato locale un avanzamento che riguarda questa collezione.
  void _onDownloadState(CatalogDownloadState state) {
    if (!mounted) return;
    final mine = state.isRunning && state.currentKey == widget.collectionKey;
    setState(() {
      _isDownloadingUpdate = mine;
      _downloadProgress = mine ? state.progress : null;
      if (mine) {
        _downloadMessage = _phaseMessage(switch (state.phase) {
          CatalogDownloadPhase.connecting => 'connecting',
          CatalogDownloadPhase.downloading => 'downloading',
          CatalogDownloadPhase.saving => 'saving',
        });
      }
    });
  }

  /// A download finito ricarica la lista, così l'empty state lascia il posto
  /// alle carte senza dover riaprire la pagina.
  Future<void> _onDownloadFinished(CatalogDownloadOutcome outcome) async {
    if (!mounted) return;
    final failure = outcome.failures[widget.collectionName];
    if (failure != null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.catalogDownloadError(failure)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
      return;
    }
    if (outcome.successCount == 0) return;
    setState(() {
      _isDownloadingUpdate = false;
      _isCatalogMissing = false;
      _downloadProgress = null;
      _isLoading = true;
      _catalogCards = [];
    });
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.catalogDownloaded)));
    await Future.wait([_loadPage(), _loadAlbumsAndOwned()]);
    if (mounted) setState(() => _isLoading = false);
  }

  /// Load albums and owned quantity map (lightweight — no full CardModel load).
  Future<void> _loadAlbumsAndOwned() async {
    try {
      final albums = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
      final map = await _dbHelper.getOwnedQuantityMap(widget.collectionKey);
      if (mounted) {
        setState(() {
          _availableAlbums = albums;
          _ownedQuantityMap = map;
        });
      }
    } catch (_) {
      // Non bloccare il resto di _init() — riprovato implicitamente alla
      // prossima apertura della pagina.
    }
  }

  /// Load first page of cards with pagination
  Future<void> _loadCards() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
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
      final detectedLang = widget.collectionKey == 'yugioh'
          ? LanguageService.detectLanguageFromQuery(_lastQuery)
          : null;
      final effectiveLanguage = detectedLang ?? _preferredLanguage;

      var cards = await _dbHelper.getCatalogCardsByCollection(
        widget.collectionKey,
        query: _lastQuery,
        language: effectiveLanguage,
        limit: _pageSize,
        offset: _currentOffset,
      );

      // Il catalogo locale può essere popolato ma non ancora tradotto nella
      // lingua selezionata (es. subito dopo una risincronizzazione admin, prima
      // che "Genera Seriali Mancanti" venga eseguito) — le query non-EN filtrano
      // solo le carte con un print localizzato, quindi tornerebbero vuote anche
      // con un catalogo pieno. In quel caso ripieghiamo su EN invece di mostrare
      // "Nessuna carta trovata" per un catalogo che in realtà è presente.
      if (cards.isEmpty &&
          _currentOffset == 0 &&
          _lastQuery.isEmpty &&
          effectiveLanguage.toUpperCase() != 'EN') {
        final fallbackCards = await _dbHelper.getCatalogCardsByCollection(
          widget.collectionKey,
          query: _lastQuery,
          language: 'EN',
          limit: _pageSize,
          offset: 0,
        );
        if (fallbackCards.isNotEmpty) {
          cards = fallbackCards;
          _preferredLanguage = 'EN'; // solo per questa sessione di navigazione
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.catalogLanguageFallbackToEn)),
            );
          }
        }
      }

      if (cards.isEmpty || cards.length < _pageSize) {
        _hasMoreCards = false;
      }

      if (mounted && cards.isNotEmpty) {
        // Sort outside setState to avoid O(n log n) inside a build-blocking call.
        final merged = [..._catalogCards, ...cards];
        merged.sort((a, b) {
          final setCodeA = (a['localizedSetCode'] ?? a['setCode'] ?? '').toString();
          final setCodeB = (b['localizedSetCode'] ?? b['setCode'] ?? '').toString();
          return setCodeA.compareTo(setCodeB);
        });
        setState(() {
          _catalogCards = merged;
          _currentOffset += cards.length;
        });
      }
    } catch (e) { // ignore: empty_catches

      _hasMoreCards = false;
      if (mounted) setState(() => _loadError = AppLocalizations.of(context)!.catalogLoadError);
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

  Future<void> _toggleWishlist(Map<String, dynamic> card) async {
    final catalogId = card['id']?.toString() ?? '';
    if (catalogId.isEmpty) return;
    final isInWishlist = _wishlistCatalogIds.contains(catalogId);
    if (isInWishlist) {
      setState(() => _wishlistCatalogIds.remove(catalogId));
      await _dbHelper.removeFromWishlistByCatalogId(catalogId);
    } else {
      setState(() => _wishlistCatalogIds.add(catalogId));
      final item = WishlistModel(
        catalogId: catalogId,
        name: (card['localizedName'] ?? card['name'] ?? '').toString(),
        collection: widget.collectionKey,
        imageUrl: card['artwork'] as String?,
        serialNumber: (card['localizedSetCode'] ?? card['setCode'])?.toString(),
        rarity: (card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'])?.toString(),
        addedAt: DateTime.now().toIso8601String(),
      );
      await _dbHelper.addToWishlist(item);
    }
  }

  Future<void> _addSelectedToCollection() async {
    if (_isAdding || _selectedCardIds.isEmpty) return;
    setState(() => _isAdding = true);

    try {
      final selectedCards = _catalogCards
          .where((card) => _selectedCardIds.contains(_getCardKey(card)))
          .toList();

      // Sort albums: last used first
      final sortedAlbums = List<AlbumModel>.from(_availableAlbums)
        ..sort((a, b) {
          if (a.id == _lastUsedAlbumId) return -1;
          if (b.id == _lastUsedAlbumId) return 1;
          return 0;
        });

      // Album picker
      final selectedAlbum = await showDialog<AlbumModel>(
        context: context,
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(l10n.catalogSelectAlbumTitle),
            content: SizedBox(
              width: double.maxFinite,
              child: sortedAlbums.isEmpty
                  ? Text(l10n.catalogNoAlbumAvailable)
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
                              ? Text(l10n.catalogLastUsed, style: const TextStyle(fontSize: 11, color: Colors.amber))
                              : null,
                          onTap: () => Navigator.pop(context, album),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.btnCancel)),
            ],
          );
        },
      );
      if (selectedAlbum == null) return;

      // Capacity check
      final currentCount = await _dbHelper.getCardCountByAlbum(selectedAlbum.id!);
      final remaining = selectedAlbum.maxCapacity - currentCount;
      if (remaining <= 0) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.catalogAlbumFull(selectedAlbum.name, currentCount, selectedAlbum.maxCapacity)),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
      final limitedCards = selectedCards.length > remaining
          ? selectedCards.sublist(0, remaining)
          : selectedCards;
      if (limitedCards.length < selectedCards.length && mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.catalogAlbumNearlyFull(limitedCards.length, selectedCards.length)),
          backgroundColor: Colors.orange,
        ));
      }

      // Progress dialog
      ValueNotifier<int>? progressNotifier;
      if (limitedCards.length > 1 && mounted) {
        progressNotifier = ValueNotifier<int>(0);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final l10n = AppLocalizations.of(context)!;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: Text(l10n.catalogAddingProgress),
                content: ValueListenableBuilder<int>(
                  valueListenable: progressNotifier!,
                  builder: (context, progress, _) {
                    final l10n = AppLocalizations.of(context)!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(value: limitedCards.isNotEmpty ? progress / limitedCards.length : null),
                        const SizedBox(height: 12),
                        Text(l10n.catalogCardsProgress(progress, limitedCards.length)),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      }

      // Delegate add logic to the service
      final result = await _dbHelper.addCatalogCardsToAlbum(
        limitedCards, selectedAlbum, widget.collectionKey,
        onProgress: (done, total) => progressNotifier?.value = done,
      );

      if (progressNotifier != null && mounted) {
        Navigator.pop(context);
        progressNotifier.dispose();
      }

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final added = result['added'] ?? 0;
        final updated = result['updated'] ?? 0;
        final doppioni = result['doppioni'] ?? 0;
        final parts = <String>[
          if (added > 0) l10n.catalogAdded(added),
          if (updated > 0) l10n.catalogUpdatedQty(updated),
          if (doppioni > 0) l10n.catalogDoppioni(doppioni),
        ];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(parts.isNotEmpty ? parts.join(', ') : l10n.catalogNoChange),
          backgroundColor: Colors.green,
        ));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_album_id_${widget.collectionKey}', selectedAlbum.id!);
        setState(() => _lastUsedAlbumId = selectedAlbum.id);
        _clearSelection();
        await _loadAlbumsAndOwned();
        await _loadCards();
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Stessa formula su tutte le piattaforme/larghezze — niente più un calcolo
    // separato per web che lasciava mobile/tablet bloccati a 2-3 colonne.
    final sw = MediaQuery.of(context).size.width;
    final catalogCols = sw > 1400
        ? 7
        : sw > 1100
            ? 6
            : sw > 820
                ? 5
                : sw > 560
                    ? 4
                    : sw > 380
                        ? 3
                        : 2;
    return Stack(
      children: [
        Column(
          children: [
            if (_isSelectionMode) _buildSelectionBanner(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: l10n.catalogSearchHint,
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
                if (_supportedLanguages.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildLanguageButton(),
                ],
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null && _catalogCards.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadCards,
                                icon: const Icon(Icons.refresh),
                                label: Text(l10n.btnRetry),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _catalogCards.isEmpty
                        ? _isCatalogMissing
                            ? _buildCatalogMissingState()
                            : Center(child: Text(l10n.catalogNoCards))
                        : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: catalogCols,
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
                          final bool isSelected = _selectedCardIds.contains(_getCardKey(card));
                          // Unico percorso per tutte le collezioni — i campi localizzati (YGO)
                          // hanno priorità; per le altre collezioni sono null e si usa il fallback.
                          final displayName = (card['localizedName'] ?? card['name'] ?? '').toString();
                          final displaySetCode = (card['localizedSetCode'] ?? card['setCode'])?.toString();
                          final displayRarityCode = (card['localizedRarityCode'] ?? card['rarityCode'] ?? card['rarity'])?.toString();
                          final displayRarityFull = (card['localizedRarity'] ?? card['setRarity'] ?? card['rarity'] ?? displayRarityCode)?.toString();
                          // Foreign print badge: solo YGO quando isLocalizedPrint == 0
                          final bool isForeignPrint = card['isLocalizedPrint'] == 0;
                          final String catalogId = card['id']?.toString() ?? '';
                          final String ownedKey =
                              '${card['id']}-${card['localizedSetCode'] ?? card['setCode'] ?? ''}';
                          final int ownedQty = _ownedQuantityMap[ownedKey] ?? 0;

                          return RepaintBoundary(
                            child: InkWell(
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
                                            _buildCardImage(card, index),
                                            if (ownedQty > 0)
                                              Positioned(
                                                bottom: 4,
                                                left: 4,
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
                                            if (!_isSelectionMode)
                                              Positioned(
                                                bottom: 4,
                                                right: 4,
                                                child: GestureDetector(
                                                  onTap: () => _toggleWishlist(card),
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.55),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: AnimatedSwitcher(
                                                      duration: const Duration(milliseconds: 200),
                                                      transitionBuilder: (child, anim) =>
                                                          ScaleTransition(scale: anim, child: child),
                                                      child: Icon(
                                                        _wishlistCatalogIds.contains(catalogId)
                                                            ? Icons.favorite
                                                            : Icons.favorite_border,
                                                        key: ValueKey(_wishlistCatalogIds.contains(catalogId)),
                                                        color: _wishlistCatalogIds.contains(catalogId)
                                                            ? Colors.red
                                                            : Colors.white,
                                                        size: 16,
                                                      ),
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
                          ));
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
              label: Text(_isAdding ? l10n.catalogAddingN : l10n.catalogAddN(_selectedCardIds.length)),
              backgroundColor: _isAdding ? Colors.grey : Colors.deepPurple,
            ),
          ),
      ],
    );
  }

  Widget _buildCardImage(Map<String, dynamic> card, int cardIndex) {
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
    return GestureDetector(
      onTap: _isSelectionMode ? null : () => _showCardDetail(cardIndex),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        memCacheWidth: 300,
        memCacheHeight: 420,
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
      ),
    );
  }

  /// Converte una carta del catalogo (mappa grezza) in un [CardModel] leggero
  /// sufficiente per la pagina di dettaglio in sola lettura. La carta non è
  /// posseduta: nessun id locale, album -1, quantità di default.
  CardModel _catalogCardToModel(Map<String, dynamic> card) {
    return CardModel(
      catalogId: card['id']?.toString(),
      name: (card['localizedName'] ?? card['name'] ?? '').toString(),
      serialNumber: (card['localizedSetCode'] ?? card['setCode'] ?? '').toString(),
      collection: (card['collection'] ?? widget.collectionKey).toString(),
      albumId: -1,
      type: (card['humanReadableCardType'] ?? card['type'] ?? '').toString(),
      rarity: (card['localizedRarityCode'] ??
              card['rarityCode'] ??
              card['rarity'] ??
              '')
          .toString(),
      description:
          (card['localizedDescription'] ?? card['description'] ?? '').toString(),
      imageUrl: card['artwork'] as String?,
    );
  }

  /// Apre la pagina di dettaglio della carta del catalogo (sola lettura),
  /// navigabile con swipe fra tutte le carte attualmente caricate.
  void _showCardDetail(int index) {
    if (index < 0 || index >= _catalogCards.length) return;
    final cards = _catalogCards.map(_catalogCardToModel).toList();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(
          cards: cards,
          initialIndex: index,
          onDelete: (_) {},
          catalogMode: true,
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

  /// Detect the language of a print based on set code pattern.
  /// YuGiOh: LOB-EN005 → EN, LOB-IT005 → IT
  /// One Piece: OP01-001 → JP, OP01-EN001 → EN, OP01-FR001 → FR
  String _detectPrintLanguage(Map<String, dynamic> card) {
    final setCode = (card['setCode'] ?? '').toString().toUpperCase();
    if (!setCode.contains('-')) return 'JP';
    final afterDash = setCode.substring(setCode.indexOf('-') + 1);
    if (afterDash.isEmpty) return 'JP';
    // One Piece JP: collector number starts with a digit
    if (afterDash[0].compareTo('0') >= 0 && afterDash[0].compareTo('9') <= 0) return 'JP';
    // 2-letter language prefix (EN, FR, IT, DE, PT, KO, ZH, ...)
    final match = RegExp(r'^([A-Z]{2})').firstMatch(afterDash);
    if (match != null) {
      return match.group(1)!; // Ritorna direttamente il codice (EN, FR, KO, ZH, …)
    }
    return 'EN';
  }

  /// Badge lingua per carte One Piece.
  Widget _buildLanguageButton() {
    return GestureDetector(
      onTap: _showLanguagePicker,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Center(
          child: LanguageFlag(languageCode: _preferredLanguage, width: 26),
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgMedium,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              l10n.catalogLanguageTitle,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l10n.catalogLanguageUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Container(height: 0.5, color: AppColors.divider),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
          for (final code in _supportedLanguages) ...[
            Builder(
              builder: (_) {
                final isAvailable = _availableCatalogLanguages.contains(code);
                final isSelected = code == _preferredLanguage;
                return Opacity(
                  opacity: isAvailable ? 1.0 : 0.4,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isAvailable
                          ? () {
                              Navigator.pop(ctx);
                              LanguageService.setPreferredLanguageForCollection(
                                  widget.collectionKey, code);
                              setState(() => _preferredLanguage = code);
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            LanguageFlag(languageCode: code, width: 30),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                LanguageService.languageLabels[code] ?? code,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (!isAvailable)
                              Text(
                                l10n.catalogLanguageNotAvailable,
                                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                              )
                            else if (isSelected)
                              const Icon(Icons.check, color: AppColors.blue, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 58)),
          ],
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 12),
        ],
        ),
      ),
    );
  }

  void _showSetCompletedDialog(Map<String, dynamic> completion, int currentAlbumId) {
    final setName = completion['setName'] as String? ?? '';
    final setIdentifier = (completion['setCode'] as String?) ?? setName;
    final total = completion['totalCards'] as int? ?? 0;
    int? selectedAlbumId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.catalogSetCompleted, style: const TextStyle(fontSize: 18))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.catalogSetCompletedMsg(setName, total, total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(l10n.catalogMoveToAlbum),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selectedAlbumId,
                  decoration: InputDecoration(labelText: l10n.catalogMoveInAlbumLabel, isDense: true),
                  hint: Text(l10n.catalogKeepCurrentAlbum),
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
                child: Text(l10n.btnClose),
              ),
              if (selectedAlbumId != null)
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _dbHelper.moveSetCardsToAlbum(widget.collectionKey, setIdentifier, selectedAlbumId!);
                    await _loadAlbumsAndOwned();
                    if (mounted) {
                      final l10n = AppLocalizations.of(context)!;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.catalogCardsMoved(setName))),
                      );
                    }
                  },
                  child: Text(l10n.btnMove),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAddDialog(Map<String, dynamic> catalogCard) {
    CardDialogs.showAddCard(
      context: context,
      collectionName: widget.collectionName,
      collectionKey: widget.collectionKey,
      availableAlbums: _availableAlbums,
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
          SnackBar(content: Text(catalogCard.isEmpty ? 'Carta aggiunta!' : '${catalogCard['localizedName'] ?? catalogCard['name']} aggiunta!')), // TODO: l10n
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
    final l10n = AppLocalizations.of(context)!;
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
              l10n.catalogCardsSelected(_selectedCardIds.length),
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
            tooltip: l10n.catalogSelectAll,
          ),
        ],
      ),
    );
  }

  /// Empty state quando il catalogo non è ancora stato scaricato
  Widget _buildCatalogMissingState() {
    final l10n = AppLocalizations.of(context)!;
    final accent = _themeAccent;

    if (_isDownloadingUpdate) {
      final pct = _downloadProgress != null
          ? '${(_downloadProgress! * 100).toInt()}%'
          : '···';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_themeIcon, size: 64, color: accent),
              const SizedBox(height: 20),
              Text(
                widget.collectionName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 260,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.catalogDownloadLabel,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          pct,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _downloadProgress,
                        minHeight: 6,
                        backgroundColor: AppColors.bgDark,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _downloadMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_themeIcon, size: 64, color: accent),
            const SizedBox(height: 16),
            Text(
              l10n.catalogNoCatalogDownloaded(widget.collectionName),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.catalogDownloadPrompt,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _downloadUpdate,
              icon: const Icon(Icons.download_rounded),
              label: Text(l10n.catalogDownloadBtn),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
