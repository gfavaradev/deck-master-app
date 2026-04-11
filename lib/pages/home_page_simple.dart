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
  static const _catalogAvailable = {'yugioh', 'onepiece', 'pokemon'};

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
        final locked = all.where((c) => !c.isUnlocked).toList();
        locked.sort((a, b) {
          final aHas = _catalogAvailable.contains(a.key) ? 0 : 1;
          final bHas = _catalogAvailable.contains(b.key) ? 0 : 1;
          return aHas.compareTo(bHas);
        });
        _availableCollections = locked;
        _isLoading = false;
      });
    }
  }

  Future<void> _unlock(CollectionModel collection) async {
    await _repo.unlockCollection(collection.key);
    await _loadCollections();
    _checkAndPromptCatalogDownload(collection);
  }

  Future<void> _checkAndPromptCatalogDownload(CollectionModel collection) async {
    if (!mounted) return;
    try {
      final info = await _repo.checkCollectionCatalogUpdates(collection.key);
      if (!mounted || info['needsUpdate'] != true) return;
      _showCatalogDownloadDialog(collection, info);
    } catch (_) {}
  }

  void _showCatalogDownloadDialog(CollectionModel collection, Map<String, dynamic> info) {
    final totalCards = info['totalCards'] as int? ?? 0;
    final mb = (totalCards * 3 / 1024).clamp(1.0, 999.0);
    final sizeStr = '~${mb.toStringAsFixed(0)} MB';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Catalogo ${collection.name}'),
        content: Text(
          'Il catalogo di ${collection.name} è disponibile ($sizeStr).\nVuoi scaricarlo adesso?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Più tardi'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadCatalog(collection, info);
            },
            child: const Text('Scarica'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCatalog(CollectionModel collection, Map<String, dynamic> info) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Download catalogo ${collection.name} in corso...'),
        duration: const Duration(minutes: 10),
      ),
    );
    try {
      await _repo.downloadCollectionCatalog(collection.key, updateInfo: info);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Catalogo ${collection.name} scaricato con successo!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore download: $e')),
        );
      }
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
          if (_availableCollections.isNotEmpty) ...[
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isUnlocked
                ? [AppColors.bgMedium, color.withValues(alpha: 0.18)]
                : [AppColors.bgMedium, color.withValues(alpha: 0.07)],
          ),
          border: Border.all(
            color: isUnlocked
                ? color.withValues(alpha: 0.65)
                : color.withValues(alpha: 0.22),
            width: isUnlocked ? 1.5 : 1.0,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 12,
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
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                  ),
                  child: const Text(
                    'Prossimamente',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF7A5C00),
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
                child: Icon(Icons.lock_outline, size: 18, color: Color(0xFF7A5C00)),
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

  Color _getCollectionColor(String key) => switch (key) {
    'yugioh'           => const Color(0xFFE53935),
    'pokemon'          => const Color(0xFFFFCA28),
    'magic'            => const Color(0xFFEF6C00),
    'onepiece'         => const Color(0xFFE53935),
    'digimon'          => const Color(0xFF1E88E5),
    'dragon-ball-super'=> const Color(0xFFFF8F00),
    'lorcana'          => const Color(0xFF8E24AA),
    'flesh-and-blood'  => const Color(0xFFC62828),
    'vanguard'         => const Color(0xFF00897B),
    'star-wars'        => const Color(0xFFFFEE58),
    'riftbound'        => const Color(0xFF1565C0),
    'gundam'           => const Color(0xFF546E7A),
    'union-arena'      => const Color(0xFF43A047),
    _                  => const Color(0xFF78909C),
  };

  String _getCollectionLogoUrl(String key) => switch (key) {
    'yugioh'           => 'assets/images/collections/yugioh-logo.png',
    'pokemon'          => 'assets/images/collections/pokemon-logo.png',
    'magic'            => 'assets/images/collections/magic-logo.png',
    'onepiece'         => 'assets/images/collections/one-piece-logo.webp',
    'digimon'          => 'assets/images/collections/digimon-logo.png',
    'dragon-ball-super'=> 'assets/images/collections/dragon-ball-super-logo.png',
    'lorcana'          => 'assets/images/collections/lorcana-logo.png',
    'flesh-and-blood'  => 'assets/images/collections/flesh-and-blood-logo.png',
    'vanguard'         => 'assets/images/collections/vanguard-logo.png',
    'star-wars'        => 'assets/images/collections/star-wars-logo.png',
    'riftbound'        => 'assets/images/collections/riftbound-logo.png',
    'gundam'           => 'assets/images/collections/gundam-logo.png',
    'union-arena'      => 'assets/images/collections/union-arena-logo.png',
    _                  => 'assets/images/collections/yugioh-logo.png',
  };
}
