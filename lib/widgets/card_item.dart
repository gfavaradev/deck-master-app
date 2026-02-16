import 'package:flutter/material.dart';
import '../models/card_model.dart';

class CardListItem extends StatelessWidget {
  final CardModel card;
  final String albumName;
  final Function(CardModel, int) onUpdateQuantity;
  final Function(CardModel) onDelete;
  final Function(CardModel) onTap;

  const CardListItem({
    super.key,
    required this.card,
    required this.albumName,
    required this.onUpdateQuantity,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.style, size: 40),
      title: Text('[${card.serialNumber}] ${card.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.rarity),
          Text('Album: $albumName €${card.value.toStringAsFixed(2)}'),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: () => onUpdateQuantity(card, -1),
          ),
          Text(
            card.quantity.toString(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => onUpdateQuantity(card, 1),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => onDelete(card),
          ),
        ],
      ),
      onTap: () => onTap(card),
    );
  }
}

class CardGridItem extends StatelessWidget {
  final CardModel card;
  final String albumName;
  final Function(CardModel, int) onUpdateQuantity;
  final Function(CardModel) onTap;

  const CardGridItem({
    super.key,
    required this.card,
    required this.albumName,
    required this.onUpdateQuantity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onTap(card),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.style, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      '[${card.serialNumber}]',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    Text(
                      card.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('Rarità: ${card.rarity}', style: const TextStyle(fontSize: 10)),
                    Text('Album: $albumName', style: const TextStyle(fontSize: 10)),
                    Text(
                      '€${card.value.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: () => onUpdateQuantity(card, -1),
                ),
                Text(
                  card.quantity.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => onUpdateQuantity(card, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
