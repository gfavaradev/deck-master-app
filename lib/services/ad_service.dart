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

  // ── Banner IDs ────────────────────────────────────────────────────────────
  static const _androidBannerProdId  = 'ca-app-pub-8286949651686497/7191944552';
  static const _iosBannerProdId      = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  static const _androidBannerTestId  = 'ca-app-pub-3940256099942544/6300978111';
  static const _iosBannerTestId      = 'ca-app-pub-3940256099942544/2934735716';

  // ── Rewarded IDs ──────────────────────────────────────────────────────────
  static const _androidRewardedProdId  = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  static const _iosRewardedProdId      = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  static const _androidRewardedTestId  = 'ca-app-pub-3940256099942544/5224354917';
  static const _iosRewardedTestId      = 'ca-app-pub-3940256099942544/1712485313';

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  // iOS non ha ancora App ID/unit ID di produzione configurati.
  static bool get _iosReady => !_iosBannerProdId.contains('XXXX');

  /// Ad unit ID banner: test in debug, produzione in release.
  static String get bannerAdUnitId {
    if (kDebugMode) return _isIos ? _iosBannerTestId : _androidBannerTestId;
    return _isIos ? _iosBannerProdId : _androidBannerProdId;
  }

  /// Ad unit ID rewarded: test in debug, produzione in release.
  static String get rewardedAdUnitId {
    if (kDebugMode) return _isIos ? _iosRewardedTestId : _androidRewardedTestId;
    return _isIos ? _iosRewardedProdId : _androidRewardedProdId;
  }

  /// Inizializza AdMob. Chiamare una sola volta in main() prima di runApp.
  static Future<void> initialize() async {
    if (_isIos && !kDebugMode && !_iosReady) return;
    await MobileAds.instance.initialize();
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: ['1F9CDB810B965089B9CAD8D41B30B255'],
      ),
    );
  }

  /// Carica un rewarded ad e lo restituisce via callback.
  /// [onLoaded] → ad pronto.
  /// [onFailed] → errore di caricamento.
  static void loadRewardedAd({
    required void Function(RewardedAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  /// Mostra un rewarded ad già caricato.
  /// [onRewarded] → ricompensa guadagnata (chiamato prima della chiusura).
  /// [onDismissed] → ad chiusa (con o senza ricompensa).
  /// [onFailed]    → errore durante la visualizzazione.
  static void showRewardedAd(
    RewardedAd ad, {
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
    required void Function(AdError error) onFailed,
  }) {
    bool rewarded = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (rewarded) onRewarded();
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        onFailed(error);
      },
    );
    ad.show(onUserEarnedReward: (a, r) => rewarded = true);
  }
}
