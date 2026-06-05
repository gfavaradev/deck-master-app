import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/wishlist_model.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../theme/app_colors.dart';

class WishlistCatalogPicker extends StatefulWidget {
  const WishlistCatalogPicker({super.key});

  @override
  State<WishlistCatalogPicker> createState() => _WishlistCatalogPickerState();
}

class _WishlistCatalogPickerState extends State<WishlistCatalogPicker> {
  static const _collections = [
    ('yugioh',   'Yu-Gi-Oh!'),
    ('pokemon',  'Pokémon'),
    ('onepiece', 'One Piece'),
  ];

  final _repo = DataRepository();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _selectedCollection = 'yugioh';
  List<Map<String, dynamic>> _results = [];
  final Set<String> _addedIds = {};
  bool _searching = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final lang = await LanguageService.getPreferredLanguageForCollection(_selectedCollection);
    final results = await _repo.getCatalogCardsByCollection(
      _selectedCollection,
      query: query,
      language: lang.toUpperCase(),
      limit: 40,
    );
    if (!mounted) return;
    setState(() { _results = results; _searching = false; });
  }

  Future<void> _add(Map<String, dynamic> card) async {
    if (_adding) return;
    final catalogId = (card['id'] ?? '').toString();
    if (_addedIds.contains(catalogId)) return;

    setState(() => _adding = true);
    final item = WishlistModel(
      catalogId: catalogId,
      name: (card['localizedName'] ?? card['name'] ?? '').toString(),
      collection: _selectedCollection,
      imageUrl: card['imageUrl']?.toString(),
      serialNumber: (card['localizedSetCode'] ?? card['setCode'] ?? '').toString(),
      rarity: (card['localizedRarity'] ?? card['setRarity'] ?? card['rarity'] ?? '').toString(),
      addedAt: DateTime.now().toIso8601String(),
    );

    await _repo.addToWishlist(item);
    if (!mounted) return;
    setState(() { _addedIds.add(catalogId); _adding = false; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.wishlistItemAddedMsg(item.name)),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(l10n.wishlistCatalogSearchTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              _buildCollectionChips(),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: l10n.wishlistCatalogSearchHint,
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    filled: true,
                    fillColor: AppColors.bgLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppColors.textHint),
                            onPressed: () { _searchCtrl.clear(); setState(() => _results = []); },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildCollectionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: _collections.map((c) {
          final selected = _selectedCollection == c.$1;
          final color = AppColors.forCollection(c.$1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(c.$2),
              selected: selected,
              onSelected: (_) {
                setState(() { _selectedCollection = c.$1; _results = []; });
                if (_searchCtrl.text.isNotEmpty) _search();
              },
              selectedColor: color.withValues(alpha: 0.25),
              checkmarkColor: color,
              labelStyle: TextStyle(
                color: selected ? color : AppColors.textHint,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
              backgroundColor: AppColors.bgLight,
              side: BorderSide(color: selected ? color : AppColors.border),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }
    if (_searchCtrl.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text(
              'Cerca una carta per aggiungerla\nalla tua Wishlist', // TODO: l10n
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textHint, fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(l10n.wishlistNoResults,
            style: const TextStyle(color: AppColors.textHint, fontSize: 15)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (ctx, i) => _buildResultTile(_results[i]),
    );
  }

  Widget _buildResultTile(Map<String, dynamic> card) {
    final catalogId = (card['id'] ?? '').toString();
    final alreadyAdded = _addedIds.contains(catalogId);
    final name = (card['localizedName'] ?? card['name'] ?? '').toString();
    final setCode = (card['localizedSetCode'] ?? card['setCode'] ?? '').toString();
    final rarity = (card['localizedRarity'] ?? card['setRarity'] ?? card['rarity'] ?? '').toString();
    final imageUrl = card['imageUrl']?.toString();
    final price = (card['localizedSetPrice'] ?? card['setPrice'] ?? card['localizedSetPrice']) as num?;
    final color = AppColors.forCollection(_selectedCollection);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alreadyAdded ? AppColors.success.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: imageUrl != null && imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  width: 36,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => _placeholder(color),
                )
              : _placeholder(color),
        ),
        title: Text(
          name,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (setCode.isNotEmpty) Text(setCode, style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
            if (rarity.isNotEmpty) Text(rarity, style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 11)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (price != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '€${price.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.cardtraderTeal, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            alreadyAdded
                ? const Icon(Icons.check_circle, color: AppColors.success, size: 28)
                : IconButton(
                    icon: const Icon(Icons.favorite_border, color: AppColors.gold),
                    onPressed: () => _add(card),
                    tooltip: AppLocalizations.of(context)!.wishlistAddToWishlistTooltip,
                  ),
          ],
        ),
        isThreeLine: rarity.isNotEmpty && setCode.isNotEmpty,
      ),
    );
  }

  Widget _placeholder(Color color) {
    return Container(
      width: 36,
      height: 50,
      color: color.withValues(alpha: 0.15),
      child: Icon(Icons.style, color: color.withValues(alpha: 0.4), size: 18),
    );
  }
}
