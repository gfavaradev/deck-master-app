import 'package:flutter/material.dart';
import '../models/collection_model.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';

/// Home page semplificata - mostra solo la griglia delle collezioni
class HomePageSimple extends StatefulWidget {
  final Function(String collectionKey, String collectionName) onCollectionSelected;
  /// Chiamata dopo aver sbloccato una nuova collezione: lascia che MainLayout
  /// gestisca il check/download catalogo con il suo indicatore circolare.
  final VoidCallback? onCatalogRefreshNeeded;

  const HomePageSimple({
    super.key,
    required this.onCollectionSelected,
    this.onCatalogRefreshNeeded,
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
    // Delega a MainLayout: usa il suo pallino con percentuale e la cloud-icon "Più tardi"
    widget.onCatalogRefreshNeeded?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final double width = MediaQuery.of(context).size.width;
    final int crossAxisCount = width > 1200 ? 6 : (width > 900 ? 5 : (width > 600 ? 4 : 2));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_unlockedCollections.isNotEmpty) ...[
            _buildSectionTitle('Le mie Collezioni'),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: _unlockedCollections.length,
              itemBuilder: (context, index) =>
                  _buildCollectionTile(_unlockedCollections[index], true),
            ),
            const SizedBox(height: 32),
          ],
          if (_availableCollections.isNotEmpty) ...[
            _buildSectionTitle('Collezioni Disponibili'),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.gold, Color(0xFFF5D76E)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionTile(CollectionModel collection, bool isUnlocked) {
    final bool hasCatalog = _catalogAvailable.contains(collection.key);
    final Color color = AppColors.forCollection(collection.key);
    final String logoUrl = _getCollectionLogoUrl(collection.key);

    // Sfondo neutro cremoso uniforme per tutte le card
    const Color cardBg = Color(0xFFE8DFCC);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!hasCatalog) return;
          if (isUnlocked) {
            widget.onCollectionSelected(collection.key, collection.name);
          } else {
            _showUnlockDialog(collection);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cardBg,
            border: Border.all(
              color: isUnlocked
                  ? color.withValues(alpha: 0.70)
                  : color.withValues(alpha: 0.22),
              width: isUnlocked ? 1.5 : 1.0,
            ),
            boxShadow: isUnlocked
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Opacity(
                    opacity: isUnlocked ? 1.0 : 0.38,
                    child: Image.asset(
                      logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, e) => Icon(
                        Icons.style,
                        size: 40,
                        color: isUnlocked ? color : AppColors.textHint,
                      ),
                    ),
                  ),
                ),
              ),
              if (!isUnlocked && hasCatalog)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_outline, size: 13, color: color.withValues(alpha: 0.85)),
                  ),
                ),
              if (!hasCatalog)
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.60),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Prossimamente',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnlockDialog(CollectionModel collection) {
    showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: 'Sblocca ${collection.name}',
        icon: Icons.lock_open_outlined,
        iconColor: AppColors.blue,
        message: 'Vuoi aggiungere ${collection.name} alle tue collezioni?',
        confirmLabel: 'Sblocca',
        confirmColor: AppColors.blue,
      ),
    ).then((confirmed) {
      if (confirmed == true) _unlock(collection);
    });
  }

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
