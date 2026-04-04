import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/cardtrader_price_badge.dart' show CardtraderAllPricesSection;

class CardDetailPage extends StatefulWidget {
  final CardModel card;
  final String albumName;
  final Function(CardModel) onDelete;
  final List<AlbumModel> availableAlbums;
  final VoidCallback? onAlbumChanged;
  final List<Map<String, dynamic>> cardDecks;

  const CardDetailPage({
    super.key,
    required this.card,
    required this.albumName,
    required this.onDelete,
    this.availableAlbums = const [],
    this.onAlbumChanged,
    this.cardDecks = const [],
  });

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late int? _selectedAlbumId;

  @override
  void initState() {
    super.initState();
    _selectedAlbumId = widget.card.albumId == -1 ? null : widget.card.albumId;
  }

  Future<void> _changeAlbum(int? newId) async {
    if (newId == null || newId == _selectedAlbumId) return;
    setState(() => _selectedAlbumId = newId);
    await DataRepository().updateCard(widget.card.copyWith(albumId: newId));
    widget.onAlbumChanged?.call();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        title: const Text('Elimina carta', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Eliminare "${widget.card.name}" dalla collezione?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.pop(context);
    widget.onDelete(widget.card);
  }

  String _currentAlbumName() {
    if (_selectedAlbumId == null) return widget.albumName;
    return widget.availableAlbums
        .firstWhere(
          (a) => a.id == _selectedAlbumId,
          orElse: () => AlbumModel(
            name: widget.albumName,
            collection: widget.card.collection,
            maxCapacity: 0,
          ),
        )
        .name;
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final hasImage = card.imageUrl != null && card.imageUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          // ── App Bar con immagine espandibile ────────────────────────────────
          SliverAppBar(
            expandedHeight: hasImage ? 320 : 0,
            pinned: true,
            backgroundColor: AppColors.bgMedium,
            iconTheme: const IconThemeData(color: AppColors.textPrimary),
            title: Text(
              card.name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                tooltip: 'Elimina',
                onPressed: _delete,
              ),
            ],
            flexibleSpace: hasImage
                ? FlexibleSpaceBar(
                    background: Container(
                      color: AppColors.bgMedium,
                      padding: const EdgeInsets.only(top: 80, bottom: 8),
                      child: Center(
                        child: CachedNetworkImage(
                          imageUrl: card.imageUrl!,
                          fit: BoxFit.contain,
                          placeholder: (c, u) => const Center(
                            child: CircularProgressIndicator(color: AppColors.gold),
                          ),
                          errorWidget: (c, u, e) => const Icon(
                            Icons.style,
                            size: 80,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),

          // ── Contenuto ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Seriale + rarità + tipo ─────────────────────────────────
                  _InfoSection(card: card),
                  const SizedBox(height: 12),

                  // ── Valore ──────────────────────────────────────────────────
                  _ValueSection(card: card),
                  const SizedBox(height: 12),

                  // ── Album ────────────────────────────────────────────────────
                  _SectionCard(
                    title: 'Album',
                    child: widget.availableAlbums.isNotEmpty
                        ? DropdownButtonFormField<int>(
                            initialValue: _selectedAlbumId,
                            dropdownColor: AppColors.bgLight,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                            ),
                            items: widget.availableAlbums.map((album) {
                              return DropdownMenuItem<int>(
                                value: album.id,
                                child: Text(
                                  album.maxCapacity > 0
                                      ? '${album.name} (${album.currentCount}/${album.maxCapacity})'
                                      : album.name,
                                  style: const TextStyle(color: AppColors.textPrimary),
                                ),
                              );
                            }).toList(),
                            onChanged: _changeAlbum,
                          )
                        : Text(
                            _currentAlbumName(),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),

                  // ── Prezzi CardTrader ────────────────────────────────────────
                  if (card.serialNumber.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Prezzi CardTrader',
                      child: CardtraderAllPricesSection(
                        collection: card.collection,
                        serialNumber: card.serialNumber,
                        cardName: card.name,
                        rarity: card.rarity.isNotEmpty ? card.rarity : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Descrizione ──────────────────────────────────────────────
                  if (card.description.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Descrizione',
                      child: Text(
                        card.description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Deck ─────────────────────────────────────────────────────
                  if (widget.cardDecks.isNotEmpty)
                    _SectionCard(
                      title: 'Deck',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.cardDecks
                            .map((d) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.style,
                                          size: 14, color: AppColors.blue),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${d['name']}  ×${d['quantity']}',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info section ─────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final CardModel card;
  const _InfoSection({required this.card});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seriale
          if (card.serialNumber.isNotEmpty)
            _InfoRow(
              icon: Icons.tag,
              label: 'Seriale',
              value: card.serialNumber,
              valueColor: AppColors.blue,
            ),
          // Rarità
          if (card.rarity.isNotEmpty)
            _InfoRow(
              icon: Icons.star_outline,
              label: 'Rarità',
              value: card.rarity,
              valueColor: _rarityColor(card.rarity),
            ),
          // Tipo
          if (card.type.isNotEmpty)
            _InfoRow(
              icon: Icons.category_outlined,
              label: 'Tipo',
              value: card.type,
            ),
          // Quantità
          _InfoRow(
            icon: Icons.inventory_2_outlined,
            label: 'Quantità',
            value: '× ${card.quantity}',
          ),
        ],
      ),
    );
  }

  static Color _rarityColor(String rarity) {
    final code = rarity.toUpperCase();
    const map = {
      'C': Color(0xFF757575), 'N': Color(0xFF9E9E9E), 'COMMON': Color(0xFF757575),
      'R': Color(0xFF1976D2), 'RARE': Color(0xFF1976D2),
      'SR': Color(0xFF00ACC1), 'SUPER RARE': Color(0xFF00ACC1),
      'UR': Color(0xFFFFB300), 'ULTRA RARE': Color(0xFFFFB300),
      'SCR': Color(0xFF7B1FA2), 'SECRET RARE': Color(0xFF7B1FA2),
      'SLR': Color(0xFFEC407A), 'STARLIGHT RARE': Color(0xFFEC407A),
    };
    if (map.containsKey(code)) return map[code]!;
    for (final e in map.entries) {
      if (code.contains(e.key)) return e.value;
    }
    return AppColors.textHint;
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Value section ────────────────────────────────────────────────────────────

class _ValueSection extends StatelessWidget {
  final CardModel card;
  const _ValueSection({required this.card});

  @override
  Widget build(BuildContext context) {
    final hasCt = card.cardtraderValue != null && card.cardtraderValue! > 0;
    final hasVal = card.value > 0;
    if (!hasCt && !hasVal) return const SizedBox.shrink();

    return _SectionCard(
      title: 'Valore',
      child: Row(
        children: [
          if (hasCt) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cardtraderBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.cardtraderBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store, size: 13, color: AppColors.cardtraderTeal),
                  const SizedBox(width: 4),
                  Text(
                    'CT  €${card.cardtraderValue!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.cardtraderTeal,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (hasVal)
            _PriceTrendWidget(value: card.value, previousValue: card.previousValue),
        ],
      ),
    );
  }
}

class _PriceTrendWidget extends StatelessWidget {
  final double value;
  final double? previousValue;
  const _PriceTrendWidget({required this.value, this.previousValue});

  @override
  Widget build(BuildContext context) {
    final text = '€${value.toStringAsFixed(2)}';
    if (previousValue == null || previousValue == 0 || previousValue == value) {
      return Text(text,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600));
    }
    final isUp = value > previousValue!;
    final color = isUp ? const Color(0xFF4CAF50) : const Color(0xFFE53935);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            style:
                TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 3),
        Icon(isUp ? Icons.trending_up : Icons.trending_down, size: 16, color: color),
      ],
    );
  }
}

// ─── Section card container ───────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;

  const _SectionCard({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}
