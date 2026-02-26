import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/card_model.dart';

class CardListItem extends StatelessWidget {
  final CardModel card;
  final String albumName;
  final int totalQuantity;
  final bool showControls;
  final Function(CardModel, int) onUpdateQuantity;
  final Function(CardModel) onDelete;
  final Function(CardModel) onTap;

  const CardListItem({
    super.key,
    required this.card,
    required this.albumName,
    required this.totalQuantity,
    this.showControls = true,
    required this.onUpdateQuantity,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('card_${card.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        // Mostra conferma prima di eliminare
        onDelete(card);
        return false; // Non dismissare automaticamente
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      child: ListTile(
        leading: const Icon(Icons.style, size: 40),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${card.serialNumber} ${card.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${card.rarity} • Album: $albumName • €${card.value.toStringAsFixed(2)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: showControls
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () => onUpdateQuantity(card, -1),
                  ),
                  Text(
                    totalQuantity.toString(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: () => onUpdateQuantity(card, 1),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'x$totalQuantity',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
        onTap: () => onTap(card),
      ),
    );
  }
}

class CardGridItem extends StatelessWidget {
  final CardModel card;
  final String albumName;
  final int totalQuantity;
  final bool showControls;
  final Function(CardModel, int) onUpdateQuantity;
  final Function(CardModel) onTap;

  const CardGridItem({
    super.key,
    required this.card,
    required this.albumName,
    required this.totalQuantity,
    this.showControls = true,
    required this.onUpdateQuantity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card image with quantity badge overlay
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  card.imageUrl != null && card.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: card.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.grey.withValues(alpha: 0.08),
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.withValues(alpha: 0.08),
                            child: Center(child: Icon(Icons.style, size: 48, color: Colors.green.shade600)),
                          ),
                        )
                      : Container(
                          color: Colors.grey.withValues(alpha: 0.08),
                          child: Center(child: Icon(Icons.style, size: 48, color: Colors.green.shade600)),
                        ),
                  // Quantity badge overlay
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'x$totalQuantity',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Card info (similar to catalog)
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Column(
                children: [
                  // Serial + Rarity
                  if (card.serialNumber.isNotEmpty || card.rarity.isNotEmpty)
                    RichText(
                      text: TextSpan(
                        children: [
                          if (card.serialNumber.isNotEmpty)
                            TextSpan(
                              text: card.serialNumber,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          if (card.serialNumber.isNotEmpty && card.rarity.isNotEmpty)
                            const TextSpan(
                              text: ' • ',
                              style: TextStyle(fontSize: 9, color: Colors.grey),
                            ),
                          if (card.rarity.isNotEmpty)
                            TextSpan(
                              text: card.rarity,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _getRarityColor(card.rarity),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Card name
                  SizedBox(
                    height: 16,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        card.name,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Album + Value
                  Text(
                    '$albumName • €${card.value.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Quantity controls
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: showControls
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () => onUpdateQuantity(card, -1),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          totalQuantity.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => onUpdateQuantity(card, 1),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    )
                  : Center(
                      child: Text(
                        'x$totalQuantity',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRarityColor(String? rarityCode) {
    if (rarityCode == null || rarityCode.isEmpty) return Colors.grey;
    final code = rarityCode.toUpperCase();

    const rarityColors = {
      'C': Color(0xFF757575),
      'N': Color(0xFF9E9E9E),
      'COMMON': Color(0xFF757575),
      'SP': Color(0xFF6D4C41),
      'SHORT PRINT': Color(0xFF6D4C41),
      'R': Color(0xFF1976D2),
      'RARE': Color(0xFF1976D2),
      'RR': Color(0xFF1565C0),
      'SR': Color(0xFF00ACC1),
      'SUPER RARE': Color(0xFF00ACC1),
      'SHR': Color(0xFF0097A7),
      'SHATTERFOIL RARE': Color(0xFF0097A7),
      'UR': Color(0xFFFFB300),
      'ULTRA RARE': Color(0xFFFFB300),
      'UTR': Color(0xFFFF6F00),
      'ULTIMATE RARE': Color(0xFFFF6F00),
      'SCR': Color(0xFF7B1FA2),
      'SECRET RARE': Color(0xFF7B1FA2),
      'PSCR': Color(0xFF6A1B9A),
      'PRISMATIC SECRET RARE': Color(0xFF6A1B9A),
      'USCR': Color(0xFF4A148C),
      'ULTRA SECRET RARE': Color(0xFF4A148C),
      '20SCR': Color(0xFF8E24AA),
      '20TH SECRET RARE': Color(0xFF8E24AA),
      'QCSR': Color(0xFFAB47BC),
      'QUARTER CENTURY SECRET RARE': Color(0xFFAB47BC),
      'GR': Color(0xFFB0BEC5),
      'GHOST RARE': Color(0xFFB0BEC5),
      'SLR': Color(0xFFEC407A),
      'STARLIGHT RARE': Color(0xFFEC407A),
      'CR': Color(0xFFE91E63),
      'COLLECTORS RARE': Color(0xFFE91E63),
    };

    if (rarityColors.containsKey(code)) {
      return rarityColors[code]!;
    }

    for (var entry in rarityColors.entries) {
      if (code.contains(entry.key)) {
        return entry.value;
      }
    }

    return Colors.grey;
  }
}
