import 'dart:async' show unawaited;
import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/banner_ad_widget.dart';
import '../models/wishlist_model.dart';
import '../services/app_preferences.dart';
import '../services/data_repository.dart';
import '../services/price_alert_service.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_dialog.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final _repo = DataRepository();
  List<WishlistModel> _items = [];
  bool _loading = true;

  void _onCurrencyChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    AppPreferences.currencyNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    AppPreferences.currencyNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  Future<void> _load() async {
    unawaited(_repo.syncWishlistFromCloud());
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
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.wishlistItemRemovedMsg(item.name)),
          action: SnackBarAction(
            label: l10n.wishlistUndoRemove,
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

  Future<void> _editTargetPrice(WishlistModel item) async {
    final l10n = AppLocalizations.of(context)!;
    // Pre-fill converted from EUR to selected currency
    final displayPrice = item.targetPrice != null
        ? CurrencyFormatter.fromEuros(item.targetPrice!).toStringAsFixed(2)
        : '';
    final ctrl = TextEditingController(text: displayPrice);
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.dlgTargetPriceTitle,
        icon: Icons.flag_outlined,
        iconColor: AppColors.warning,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.dlgTargetPriceMsg(item.name),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.dlgTargetPriceLabel,
                border: const OutlineInputBorder(),
                prefixText: CurrencyFormatter.prefixText,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.btnCancel),
          ),
          if (item.targetPrice != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Text(l10n.btnRemove, style: const TextStyle(color: AppColors.error)),
            ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
              Navigator.pop(ctx, val);
            },
            child: Text(l10n.btnSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    // Convert from selected currency back to EUR for storage
    final price = result < 0 ? null : CurrencyFormatter.toEuros(result);
    await _repo.updateWishlistTargetPrice(item.id!, price);
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(l10n.wishlistTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
            ),
            if (!kIsWeb) const BannerAdWidget(),
          ],
        ),
      ),
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
            'Non hai ancora aggiunto carte hai preferiti ',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vai al catalogo e tocca il cuore\nsulle carte che vuoi acquistare.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 14),
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
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
        final l10n = AppLocalizations.of(context)!;
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AppDialog(
            title: l10n.dlgRemoveWishlistTitle,
            icon: Icons.delete_outline,
            iconColor: AppColors.error,
            content: Text(l10n.dlgRemoveWishlistMsg(item.name),
                style: const TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.btnCancel)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.btnRemove),
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
                'Obiettivo: ${CurrencyFormatter.format(targetPrice)}',
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
      return Text(AppLocalizations.of(context)!.wishlistNdLabel, style: const TextStyle(color: AppColors.textHint, fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          CurrencyFormatter.format(ctPrice),
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
