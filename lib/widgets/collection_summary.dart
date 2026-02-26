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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.blue.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Uniche', uniqueCards.toString(), Colors.blue),
          _buildStat('Doppioni', duplicates.toString(), Colors.orange),
          _buildStat('Totali', totalCards.toString(), Colors.deepPurple),
          _buildStat('Valore', '€${totalValue.toStringAsFixed(2)}', Colors.green),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
