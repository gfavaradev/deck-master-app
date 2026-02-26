import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/collection_model.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';

/// Home page semplificata - mostra solo la griglia delle collezioni
class HomePageSimple extends StatefulWidget {
  final Function(String collectionKey, String collectionName) onCollectionSelected;

  const HomePageSimple({
    super.key,
    required this.onCollectionSelected,
  });

  @override
  State<HomePageSimple> createState() => _HomePageSimpleState();
}

class _HomePageSimpleState extends State<HomePageSimple> {
  static const _catalogAvailable = {'yugioh'};

  final DataRepository _repo = DataRepository();
  List<CollectionModel> _unlockedCollections = [];
  List<CollectionModel> _availableCollections = [];
  bool _isLoading = true;

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
        await _downloadYugiohCards(check);
      }
    }

    _loadCollections();
  }

  Future<void> _downloadYugiohCards([Map<String, dynamic>? updateInfo]) async {
    if (!mounted) return;

    final statusNotifier = ValueNotifier<String>('Connessione a Firestore...');
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
      statusNotifier.value = updateInfo?['canDoIncremental'] == true
          ? 'Aggiornamento catalogo in corso...'
          : 'Scaricando le carte Yu-Gi-Oh da Firestore...';

      await _repo.downloadYugiohCatalog(
        updateInfo: updateInfo,
        onProgress: (currentChunk, totalChunks) {
          progressNotifier.value = currentChunk / totalChunks;
          detailNotifier.value = 'Chunk $currentChunk di $totalChunks';
        },
        onSaveProgress: (progress) {
          statusNotifier.value = 'Salvando nel database locale...';
          progressNotifier.value = progress;
          detailNotifier.value = '${(progress * 100).toInt()}%';
        },
      );

      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogo scaricato con successo!')),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
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
              itemBuilder: (context, index) =>
                  _buildCollectionTile(_unlockedCollections[index], true),
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
            itemBuilder: (context, index) =>
                _buildCollectionTile(_availableCollections[index], false),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionTile(CollectionModel collection, bool isUnlocked) {
    final bool hasCatalog = _catalogAvailable.contains(collection.key);
    final Color color = _getCollectionColor(collection.key);
    final String logoUrl = _getCollectionLogoUrl(collection.key);

    return InkWell(
      onTap: () {
        if (!hasCatalog) return;
        if (isUnlocked) {
          widget.onCollectionSelected(collection.key, collection.name);
        } else {
          _showUnlockDialog(collection);
        }
      },
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: isUnlocked
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFCDD8FF), Color(0xFFDDD0FF)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFB4BCD8), Color(0xFFC4BCD8)],
                ),
          border: Border.all(
            color: isUnlocked
                ? AppColors.gold.withValues(alpha: 0.55)
                : const Color(0x33FFFFFF),
            width: isUnlocked ? 1.5 : 1.0,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Opacity(
                  opacity: isUnlocked ? 1.0 : 0.5,
                  child: Image.asset(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.style,
                      size: 50,
                      color: isUnlocked ? color : AppColors.textHint,
                    ),
                  ),
                ),
              ),
            ),
            if (!hasCatalog)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xCC0D0F1E),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                  ),
                  child: const Text(
                    'Prossimamente',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              )
            else if (!isUnlocked)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.lock_outline, size: 18, color: AppColors.gold),
              ),
          ],
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
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
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
      case 'yugioh':
        return Colors.red;
      case 'pokemon':
        return Colors.yellow;
      case 'magic':
        return Colors.orange;
      case 'onepiece':
        return Colors.black;
      default:
        return Colors.blue;
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
