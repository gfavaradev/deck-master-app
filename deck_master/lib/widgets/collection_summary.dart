import 'package:flutter/material.dart';

class CollectionSummary extends StatelessWidget {
  final int uniqueCards;
  final int duplicates;
  final int totalCards;
  final double totalValue;

  const CollectionSummary({
    super.key,
    required this.uniqueCards,
    required this.duplicates,
    required this.totalCards,
    required this.totalValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.withValues(alpha: 0.1),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Uniche: $uniqueCards', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Doppioni: $duplicates', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              Text('Totale: $totalCards', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Valore: €${totalValue.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          )
        ],
      ),
    );
  }
}
