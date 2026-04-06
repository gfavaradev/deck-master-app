import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Gestione centralizzata di Google AdMob.
///
/// Setup richiesto:
///  1. Crea un account AdMob su https://admob.google.com
///  2. Crea un'app Android e iOS in AdMob e ottieni i due App ID
///  3. Sostituisci [_androidAppId] e [_iosAppId] con i tuoi valori
///  4. Crea un'unità pubblicitaria Banner e sostituisci
///     [_androidBannerProdId] e [_iosBannerProdId]
///  5. Aggiungi gli App ID a:
///     - android/app/src/main/AndroidManifest.xml (meta-data APPLICATION_ID)
///     - ios/Runner/Info.plist (GADApplicationIdentifier)
class AdService {
  AdService._();

  // ── IDs produzione (da sostituire con i tuoi dati AdMob) ──────────────────
  static const _androidBannerProdId = 'ca-app-pub-8286949651686497/7191944552';
  static const _iosBannerProdId     = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';

  // ── IDs test ufficiali Google (non modificare) ────────────────────────────
  static const _androidBannerTestId = 'ca-app-pub-3940256099942544/6300978111';
  static const _iosBannerTestId     = 'ca-app-pub-3940256099942544/2934735716';

  /// Ad unit ID da usare: test in debug, produzione in release.
  static String get bannerAdUnitId {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (kDebugMode) {
      return isIos ? _iosBannerTestId : _androidBannerTestId;
    }
    return isIos ? _iosBannerProdId : _androidBannerProdId;
  }

  /// Inizializza AdMob. Chiamare una sola volta in main() prima di runApp.
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    // Registra i dispositivi di test per evitare click non validi durante lo sviluppo.
    // Aggiungi qui l'ID del tuo dispositivo (visibile nei log AdMob all'avvio).
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: ['1F9CDB810B965089B9CAD8D41B30B255'],
      ),
    );
  }
}
