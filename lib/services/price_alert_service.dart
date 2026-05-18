import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data_repository.dart';
import 'notification_service.dart';

/// Controlla la wishlist e invia notifiche locali quando un prezzo
/// scende sotto il prezzo obiettivo impostato dall'utente.
/// Usa SharedPreferences per non ri-notificare fino a quando il prezzo
/// non torna sopra il target (poi scende di nuovo).
class PriceAlertService {
  static const _keyPrefix = 'price_alert_fired_';

  /// Esegui il check. Sicuro da chiamare in qualsiasi momento — gestisce
  /// errori internamente senza propagarli.
  static Future<void> checkAlerts() async {
    if (kIsWeb) return;
    try {
      await _doCheck();
    } catch (_) {}
  }

  static Future<void> _doCheck() async {
    final repo = DataRepository();
    final items = await repo.getWishlistItems(); // already enriched with prices
    if (items.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final notif = NotificationService();

    for (final item in items) {
      if (item.id == null) continue;
      if (item.targetPrice == null) continue;
      if (item.cardtraderValue == null) continue;

      final key = '$_keyPrefix${item.id}';
      final alreadyFired = prefs.getBool(key) ?? false;
      final belowTarget = item.cardtraderValue! <= item.targetPrice!;

      if (belowTarget && !alreadyFired) {
        await notif.showPriceAlertNotification(
          id: item.id!,
          cardName: item.name,
          currentPrice: item.cardtraderValue!,
          targetPrice: item.targetPrice!,
        );
        await prefs.setBool(key, true);
      } else if (!belowTarget && alreadyFired) {
        // Prezzo risalito sopra il target → reset per future notifiche
        await prefs.remove(key);
      }
    }
  }
}
