import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/collection_model.dart';
import '../services/data_repository.dart';
import 'card_list_page.dart';
import 'catalog_page.dart';
import 'album_list_page.dart';
import 'deck_list_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DataRepository _repo = DataRepository();
  List<CollectionModel> _unlockedCollections = [];
  List<CollectionModel> _availableCollections = [];
  bool _isLoading = true;
  CollectionModel? _selectedCollection;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    final all = await _repo.getCollections();
    if (mounted) {
      setState(() {
        _unlockedCollections = all.where((c) => c.isUnlocked).toList();
        _availableCollections = all.where((c) => !c.isUnlocked).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _unlock(CollectionModel collection) async {
    await _repo.unlockCollection(collection.key);

    // If unlocking Yu-Gi-Oh, download catalog only if not already present/up to date
    if (!kIsWeb && collection.key == 'yugioh') {
      final check = await _repo.checkCatalogUpdates();
      final needsDownload = check['needsUpdate'] == true || check['isFirstDownload'] == true;
      if (needsDownload) {
        await _downloadYugiohCards();
      }
    }

    _loadCollections();
  }

  Future<void> _downloadYugiohCards() async {
    if (!mounted) return;

    // State for progress dialog
    final statusNotifier = ValueNotifier<String>('Connessione al server...');
    final progressNotifier = ValueNotifier<double?>(null);
    final detailNotifier = ValueNotifier<String>('');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Download in corso'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double?>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) {
                  return CircularProgressIndicator(value: progress);
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, status, _) {
                  return Text(status, textAlign: TextAlign.center);
                },
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: detailNotifier,
                builder: (context, detail, _) {
                  return Text(
                    detail,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    void disposeNotifiers() {
      statusNotifier.dispose();
      progressNotifier.dispose();
      detailNotifier.dispose();
    }

    try {
      statusNotifier.value = 'Scaricando le carte Yu-Gi-Oh...';

      await _repo.downloadYugiohCatalog(
        onProgress: (currentChunk, totalChunks) {
          progressNotifier.value = currentChunk / totalChunks;
          detailNotifier.value = 'Chunk $currentChunk di $totalChunks';
        },
        onSaveProgress: (progress) {
          statusNotifier.value = 'Salvando nel database...';
          progressNotifier.value = progress;
          detailNotifier.value = '${(progress * 100).toInt()}%';
        },
      );

      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Carte scaricate con successo!')),
        );
      }
      disposeNotifiers();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il download: $e')),
        );
      }
      disposeNotifiers();
    }
  }

  Widget _buildHomeContent() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_unlockedCollections.isNotEmpty) ...[
                  _buildSectionTitle('Le mie Collezioni'),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: _unlockedCollections.length,
                    itemBuilder: (context, index) => _buildCollectionTile(context, _unlockedCollections[index], true),
                  ),
                  const SizedBox(height: 30),
                ],
                
                _buildSectionTitle('Collezioni Disponibili'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _availableCollections.length,
                  itemBuilder: (context, index) => _buildCollectionTile(context, _availableCollections[index], false),
                ),
              ],
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final bool inCollection = _selectedCollection != null;

    final Widget body;
    final String appBarTitle;
    final List<Widget> appBarActions;

    if (inCollection) {
      body = CardListPage(
        collectionName: _selectedCollection!.name,
        collectionKey: _selectedCollection!.key,
      );
      appBarTitle = _selectedCollection!.name;
      appBarActions = [
        IconButton(
          icon: const Icon(Icons.bar_chart),
          tooltip: 'Statistiche',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StatsPage()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Catalogo',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CatalogPage(
                collectionName: _selectedCollection!.name,
                collectionKey: _selectedCollection!.key,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.deck),
          tooltip: 'Gestisci Deck',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeckListPage(
                collectionName: _selectedCollection!.name,
                collectionKey: _selectedCollection!.key,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.book),
          tooltip: 'Gestisci Album',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlbumListPage(
                collectionName: _selectedCollection!.name,
                collectionKey: _selectedCollection!.key,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Impostazioni',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsPage()),
          ),
        ),
      ];
    } else {
      body = _buildHomeContent();
      appBarTitle = 'Deck Master';
      appBarActions = [
        IconButton(
          icon: const Icon(Icons.bar_chart),
          tooltip: 'Statistiche',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StatsPage()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Impostazioni',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsPage()),
          ),
        ),
      ];
    }

    return Scaffold(
      appBar: AppBar(
        leading: inCollection
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Torna alla Home',
                onPressed: () => setState(() => _selectedCollection = null),
              )
            : null,
        title: Text(appBarTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: appBarActions,
      ),
      body: body,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCollectionTile(BuildContext context, CollectionModel collection, bool isUnlocked) {
    Color color = _getCollectionColor(collection.key);
    String logoUrl = _getCollectionLogoUrl(collection.key);

    return InkWell(
      onTap: () {
        if (isUnlocked) {
          setState(() {
            _selectedCollection = collection;
          });
        } else {
          _showUnlockDialog(collection);
        }
      },
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.4,
        child: Card(
          elevation: isUnlocked ? 4 : 0,
          color: isUnlocked ? Colors.white : Colors.grey.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: isUnlocked ? color.withValues(alpha: 0.5) : Colors.grey),
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: Image.asset(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.style, size: 50, color: isUnlocked ? color : Colors.grey),
                  ),
                ),
              ),
              if (!isUnlocked)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.lock, size: 18, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnlockDialog(CollectionModel collection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sblocca ${collection.name}'),
        content: Text('Vuoi aggiungere ${collection.name} alle tue collezioni?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _unlock(collection);
            },
            child: const Text('Sblocca'),
          ),
        ],
      ),
    );
  }

  Color _getCollectionColor(String key) {
    switch (key) {
      case 'yugioh': return Colors.red;
      case 'pokemon': return Colors.yellow;
      case 'magic': return Colors.orange;
      case 'onepiece': return Colors.black;
      default: return Colors.blue;
    }
  }

  String _getCollectionLogoUrl(String key) {
    switch (key) {
      case 'yugioh':
        return 'assets/imagges/collections/yugioh-logo.png';
      case 'pokemon':
        return 'assets/imagges/collections/pokemon-logo.png';
      case 'magic':
        return 'assets/imagges/collections/magic-logo.png';
      case 'onepiece':
        return 'assets/imagges/collections/one-piece-logo.webp';
      default:
        return 'assets/imagges/collections/yugioh-logo.png';
    }
  }
}
