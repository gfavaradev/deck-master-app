import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../models/wishlist_model.dart';
import '../services/data_repository.dart';
import '../services/price_alert_service.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/tutorial_content_widget.dart';
import 'wishlist_catalog_picker.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final _repo = DataRepository();
  List<WishlistModel> _items = [];
  bool _loading = true;

  final _fabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    if (TutorialService.instance.isActive && TutorialService.instance.phase == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 450));
        if (mounted) _startPhase2Tutorial();
      });
    }
  }

  void _startPhase2Tutorial() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'wishlist_fab',
          keyTarget: _fabKey,
          shape: ShapeLightFocus.RRect,
          radius: 28,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: const TutorialContentWidget(
                title: 'Aggiungi alla Wishlist',
                description: 'Tocca qui per aggiungere le carte che vuoi acquistare. Puoi impostare un prezzo obiettivo e ricevere un avviso quando viene raggiunto.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'SALTA',
      onFinish: _onPhase2Done,
      onSkip: () { _onPhase2Done(); return true; },
    ).show(context: context);
  }

  void _onPhase2Done() {
    TutorialService.instance.advanceTo(3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _load() async {
    final items = await _repo.getWishlistItems();
    if (!mounted) return;
    setState(() { _items = items; _loading = false; });
    PriceAlertService.checkAlerts();
  }

  Future<void> _remove(WishlistModel item) async {
    await _repo.removeFromWishlist(item.id!);
    if (!mounted) return;
    setState(() => _items.removeWhere((e) => e.id == item.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name} rimossa dalla Wishlist'),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () async {
              final restored = WishlistModel(
                catalogId: item.catalogId,
                name: item.name,
                collection: item.collection,
                imageUrl: item.imageUrl,
                serialNumber: item.serialNumber,
                rarity: item.rarity,
                targetPrice: item.targetPrice,
                addedAt: item.addedAt,
              );
              await _repo.addToWishlist(restored);
              await _load();
            },
          ),
        ),
      );
    }
  }

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const WishlistCatalogPicker()),
    );
    if (added == true) _load();
  }

  Future<void> _editTargetPrice(WishlistModel item) async {
    final ctrl = TextEditingController(
      text: item.targetPrice != null ? item.targetPrice!.toStringAsFixed(2) : '',
    );
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Prezzo obiettivo',
        icon: Icons.flag_outlined,
        iconColor: AppColors.warning,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Imposta il prezzo obiettivo per ${item.name}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Prezzo (€)',
                border: OutlineInputBorder(),
                prefixText: '€ ',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          if (item.targetPrice != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: const Text('Rimuovi', style: TextStyle(color: AppColors.error)),
            ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
              Navigator.pop(ctx, val);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    final price = result < 0 ? null : result;
    await _repo.updateWishlistTargetPrice(item.id!, price);
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Wishlist'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: _fabKey,
        onPressed: _openAdd,
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi carta'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border, size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          const Text(
            'La tua Wishlist è vuota',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aggiungi le carte che vuoi acquistare\ne tieni traccia dei prezzi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 14),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openAdd,
            style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi carta'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final alerts = _items.where((it) =>
        it.targetPrice != null &&
        it.cardtraderValue != null &&
        it.cardtraderValue! <= it.targetPrice!).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.gold,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: _items.length + (alerts.isNotEmpty ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (alerts.isNotEmpty && i == 0) return _buildAlertBanner(alerts.length);
          final idx = alerts.isNotEmpty ? i - 1 : i;
          return _buildCard(_items[idx]);
        },
      ),
    );
  }

  Widget _buildAlertBanner(int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'carta ha' : 'carte hanno'} raggiunto il prezzo obiettivo!',
              style: const TextStyle(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(WishlistModel item) {
    final color = AppColors.forCollection(item.collection);
    final ctPrice = item.cardtraderValue;
    final targetPrice = item.targetPrice;
    final isAboveTarget = targetPrice != null && ctPrice != null && ctPrice <= targetPrice;

    return Dismissible(
      key: Key('wish_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AppDialog(
            title: 'Rimuovi dalla Wishlist',
            icon: Icons.delete_outline,
            iconColor: AppColors.error,
            content: Text('Rimuovere "${item.name}" dalla wishlist?',
                style: const TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Rimuovi'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _remove(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editTargetPrice(item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildImage(item, color),
                const SizedBox(width: 12),
                Expanded(child: _buildInfo(item, color, ctPrice, targetPrice, isAboveTarget)),
                const SizedBox(width: 8),
                _buildPrice(ctPrice, targetPrice, isAboveTarget),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(WishlistModel item, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
          ? Image.network(
              item.imageUrl!,
              width: 52,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => _imagePlaceholder(color),
            )
          : _imagePlaceholder(color),
    );
  }

  Widget _imagePlaceholder(Color color) {
    return Container(
      width: 52,
      height: 72,
      color: color.withValues(alpha: 0.15),
      child: Icon(Icons.style, color: color.withValues(alpha: 0.5), size: 28),
    );
  }

  Widget _buildInfo(WishlistModel item, Color color, double? ctPrice, double? targetPrice, bool isAboveTarget) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        if (item.serialNumber != null && item.serialNumber!.isNotEmpty)
          Text(
            item.serialNumber!,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        if (item.rarity != null && item.rarity!.isNotEmpty)
          Text(
            item.rarity!,
            style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 11),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _collectionLabel(item.collection),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
            if (targetPrice != null) ...[
              const SizedBox(width: 6),
              Icon(
                isAboveTarget ? Icons.check_circle : Icons.flag_outlined,
                size: 14,
                color: isAboveTarget ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 2),
              Text(
                'Obiettivo: €${targetPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  color: isAboveTarget ? AppColors.success : AppColors.warning,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPrice(double? ctPrice, double? targetPrice, bool isAboveTarget) {
    if (ctPrice == null) {
      return const Text('N/D', style: TextStyle(color: AppColors.textHint, fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '€${ctPrice.toStringAsFixed(2)}',
          style: TextStyle(
            color: isAboveTarget ? AppColors.success : AppColors.cardtraderTeal,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isAboveTarget)
          const Text(
            'Sotto obiettivo!',
            style: TextStyle(color: AppColors.success, fontSize: 10),
          ),
      ],
    );
  }

  String _collectionLabel(String key) => switch (key) {
    'yugioh'   => 'Yu-Gi-Oh!',
    'pokemon'  => 'Pokémon',
    'onepiece' => 'One Piece',
    _          => key,
  };
}
