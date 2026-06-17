import 'package:flutter/material.dart';
import '../services/app_preferences.dart';
import '../utils/currency_formatter.dart';

/// AppBar title for an album detail screen: name on the left, total value
/// of the album's cards on the right (updates live as cards are added/removed).
class AlbumAppBarTitle extends StatelessWidget {
  final String albumName;
  final double totalValue;

  const AlbumAppBarTitle({
    super.key,
    required this.albumName,
    required this.totalValue,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppPreferences.currencyNotifier,
      builder: (context, currency, _) => Row(
        children: [
          Expanded(child: Text(albumName, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(
            CurrencyFormatter.format(totalValue),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
