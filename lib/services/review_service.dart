import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

/// Gestisce il flusso di richiesta recensione in-app.
///
/// Logica temporale:
///  - Prima richiesta: dopo [_firstShowAfterDays] giorni dal primo avvio
///  - Successive (se l'utente non ha ancora recensito): ogni [_repeatAfterDays] giorni
///  - Una volta che l'utente tappa "Valuta", non viene mai più mostrato
class ReviewService {
  static const _kFirstOpenKey  = 'dm_review_first_open';
  static const _kCompletedKey  = 'dm_review_completed';
  static const _kLastShownKey  = 'dm_review_last_shown';

  static const _firstShowAfterDays = 7;   // giorni dal primo avvio prima del primo popup
  static const _repeatAfterDays    = 30;  // giorni di attesa tra una richiesta e l'altra

  static const _storeUrl =
      'https://play.google.com/store/apps/details?id=com.giuseppe.deckmaster';

  /// Controlla le condizioni temporali e mostra il popup se è il momento.
  /// Chiamare dopo un breve ritardo dall'avvio (es. 5 secondi) così non
  /// disturba le animazioni di caricamento.
  static Future<void> maybePrompt(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Registra il primo avvio (una sola volta)
    if (!prefs.containsKey(_kFirstOpenKey)) {
      await prefs.setInt(_kFirstOpenKey, now);
      return; // non mostrare subito al primissimo avvio
    }

    // Se l'utente ha già recensito, non mostrare più
    if (prefs.getBool(_kCompletedKey) == true) return;

    final firstOpen = prefs.getInt(_kFirstOpenKey) ?? now;
    final daysSinceFirstOpen =
        (now - firstOpen) / Duration.millisecondsPerDay;

    // Troppo presto rispetto al primo avvio
    if (daysSinceFirstOpen < _firstShowAfterDays) return;

    // Controlla se è già stato mostrato di recente
    final lastShown = prefs.getInt(_kLastShownKey);
    if (lastShown != null) {
      final daysSinceLastShown = (now - lastShown) / Duration.millisecondsPerDay;
      if (daysSinceLastShown < _repeatAfterDays) return;
    }

    // Registra quando è stato mostrato e apri il popup
    await prefs.setInt(_kLastShownKey, now);
    if (!context.mounted) return;
    _show(context, prefs);
  }

  static void _show(BuildContext context, SharedPreferences prefs) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ReviewDialog(
        onRate: () async {
          await prefs.setBool(_kCompletedKey, true);
          final uri = Uri.parse(_storeUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    );
  }
}

class _ReviewDialog extends StatelessWidget {
  final Future<void> Function() onRate;
  const _ReviewDialog({required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icona stella
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded, color: AppColors.gold, size: 38),
            ),
            const SizedBox(height: 18),
            const Text(
              'Ti piace DeckMaster?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Una recensione ci aiuta tantissimo a crescere e ci vuole solo un momento.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            // Bottone principale
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onRate();
                },
                child: const Text(
                  '⭐  Valuta DeckMaster',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Bottone secondario
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Più tardi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
