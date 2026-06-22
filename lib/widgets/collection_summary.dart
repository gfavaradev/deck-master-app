import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/app_preferences.dart';
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
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<String>(
      valueListenable: AppPreferences.currencyNotifier,
      builder: (context, currency, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.glowBlue,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat(l10n.collectionSummaryUnique, _formatCount(uniqueCards), AppColors.blue),
          _buildStat(l10n.collectionSummaryDuplicates, _formatCount(duplicates), AppColors.gold),
          _buildStat(l10n.collectionSummaryTotal, _formatCount(totalCards), AppColors.purple),
          _buildStat(l10n.collectionSummaryValue, CurrencyFormatter.format(totalValue), AppColors.gold),
        ],
      ),
    ));
  }

  String _formatCount(int value) =>
      NumberFormat('#,##0', AppPreferences.instance.languageCode).format(value);

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
