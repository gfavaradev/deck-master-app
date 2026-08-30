import 'dart:async';

/// Cancello di avvio per gli init pesanti (AdMob, download in background,
/// notifiche, billing).
///
/// Partivano tutti a `main()`, quindi cadevano in mezzo ai frame dell'intro
/// animata dello splash — caricamento moduli, canali di piattaforma e lavoro
/// sull'isolate principale proprio durante caduta/apertura della bustina e
/// migrazione delle carte, che è dove l'animazione scattava. Qui aspettano che
/// l'intro abbia finito di girare: fino a quel momento l'utente non può
/// comunque interagire con nulla che dipenda da questi servizi.
///
/// Il fallback esiste perché il cancello non deve poter restare chiuso per
/// sempre se lo splash non arriva mai a completare l'intro (errore in fase di
/// auth, avvio da deep link, esecuzione in test).
class StartupGate {
  StartupGate._();

  static final Completer<void> _completer = Completer<void>();
  static Timer? _fallback;

  /// Future che si completa a intro finita (o allo scadere del [fallback]).
  static Future<void> get introFinished {
    if (!_completer.isCompleted) _fallback ??= Timer(_fallbackDelay, open);
    return _completer.future;
  }

  static const Duration _fallbackDelay = Duration(seconds: 12);

  /// Apre il cancello. Idempotente: lo splash può chiamarlo più volte.
  static void open() {
    _fallback?.cancel();
    _fallback = null;
    if (!_completer.isCompleted) _completer.complete();
  }
}
