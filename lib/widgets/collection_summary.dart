import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';

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
    // TODO: l10n — 'Uniche', 'Doppioni', 'Totali', 'Valore' not in ARB
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.glowBlue,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Uniche', uniqueCards.toString(), AppColors.blue),
          _buildStat('Doppioni', duplicates.toString(), AppColors.gold),
          _buildStat('Totali', totalCards.toString(), AppColors.purple),
          _buildStat('Valore', CurrencyFormatter.format(totalValue), AppColors.gold),
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
          style: const TextStyle(fontSize: 11, color: AppColors.textHint),
        ),
      ],
    );
  }
}
