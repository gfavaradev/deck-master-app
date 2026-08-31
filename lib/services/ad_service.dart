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

  // ── Rewarded interstitial IDs ─────────────────────────────────────────────
  //
  // L'unità di produzione è un **interstitial con premio**, non un rewarded
  // classico: nell'SDK sono due classi diverse (`RewardedInterstitialAd` vs
  // `RewardedAd`) con due canali di caricamento distinti. Caricare l'una con
  // l'altra fa fallire ogni richiesta con "Ad unit doesn't match format" —
  // era la causa dello sblocco collezioni che non funzionava mai.
  //
  // Se un giorno l'unità venisse ricreata come Rewarded classico, qui va
  // cambiata la classe, non solo l'id.
  static const _androidRewardedProdId  = 'ca-app-pub-8286949651686497/1949048086';
  static const _iosRewardedProdId      = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  // Id di test ufficiali Google per il formato interstitial con premio.
  static const _androidRewardedTestId  = 'ca-app-pub-3940256099942544/5354046379';
  static const _iosRewardedTestId      = 'ca-app-pub-3940256099942544/6978759866';

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  // google_mobile_ads supporta solo Android e iOS: su desktop/web qualsiasi
  // chiamata al plugin lancia MissingPluginException (nessun canale nativo
  // registrato). Usato anche dai widget per evitare di caricare ad su quelle piattaforme.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || _isIos);

  // iOS non ha ancora App ID/unit ID di produzione configurati.
  static bool get _iosReady => !_iosBannerProdId.contains('XXXX');

  /// Ad unit ID banner: test in debug, produzione in release.
  static String get bannerAdUnitId {
    if (kDebugMode) return _isIos ? _iosBannerTestId : _androidBannerTestId;
    return _isIos ? _iosBannerProdId : _androidBannerProdId;
  }

  /// Ad unit ID dell'interstitial con premio: test in debug, prod in release.
  static String get rewardedAdUnitId {
    if (kDebugMode) return _isIos ? _iosRewardedTestId : _androidRewardedTestId;
    return _isIos ? _iosRewardedProdId : _androidRewardedProdId;
  }

  // ── Inizializzazione ──────────────────────────────────────────────────────

  /// Inizializzazione in corso o completata. Condivisa fra tutti i chiamanti.
  static Future<void>? _initFuture;

  /// Init effettiva del plugin. Sostituibile nei test: `MobileAds` parla con i
  /// canali nativi, che sotto `flutter test` non esistono.
  @visibleForTesting
  static Future<void> Function() platformInitializer = _initializePlatform;

  /// Load effettiva dell'annuncio. Stesso motivo di [platformInitializer].
  @visibleForTesting
  static void Function(
    String adUnitId,
    RewardedInterstitialAdLoadCallback callback,
  ) rewardedLoader = _loadRewardedPlatform;

  /// Riporta il servizio allo stato iniziale fra un test e l'altro.
  @visibleForTesting
  static void debugReset() {
    _initFuture = null;
    platformInitializer = _initializePlatform;
    rewardedLoader = _loadRewardedPlatform;
  }

  /// Inizializza AdMob una sola volta.
  ///
  /// Chiamate ripetute e concorrenti condividono lo stesso Future, così chi
  /// deve caricare un annuncio può attenderlo: `main()` rimanda l'init di
  /// qualche secondo per non rubare frame all'intro, e un load partito prima
  /// che l'SDK sia pronto fallisce sempre.
  ///
  /// Un'inizializzazione fallita non viene memorizzata: il tentativo successivo
  /// riparte da capo invece di restare bloccato su un Future in errore.
  static Future<void> initialize() {
    if (!isSupportedPlatform) return Future.value();
    if (_isIos && !kDebugMode && !_iosReady) return Future.value();
    return _initFuture ??= platformInitializer().catchError((Object e) {
      _initFuture = null;
      debugPrint('[AdService] inizializzazione fallita: $e');
    });
  }

  static Future<void> _initializePlatform() async {
    await MobileAds.instance.initialize();
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        // google_mobile_ads 9 ha fuso i due flag COPPA/GDPR
        // (tagForChildDirectedTreatment + tagForUnderAgeOfConsent) in un unico
        // segnale. La coppia precedente era "no"/"no", cioè app non rivolta ai
        // minori e utenti non sotto l'età del consenso: l'equivalente nel nuovo
        // enum è `unspecified`, che dichiara che nessun trattamento per età si
        // applica alla richiesta. `child` e `teen` sono gli unici altri valori
        // e attiverebbero restrizioni che prima non c'erano.
        ageRestrictedTreatment: AgeRestrictedTreatment.unspecified,
        maxAdContentRating: MaxAdContentRating.ma,
        testDeviceIds: kDebugMode ? ['1F9CDB810B965089B9CAD8D41B30B255'] : [],
      ),
    );
  }

  // ── Rewarded ──────────────────────────────────────────────────────────────

  /// Carica un interstitial con premio e lo restituisce via callback.
  ///
  /// Attende [initialize] prima di partire, altrimenti il preload della home
  /// può scattare a SDK non ancora pronto e fallire sistematicamente.
  ///
  /// [onLoaded] → ad pronto.
  /// [onFailed] → errore di caricamento, già loggato qui con il codice AdMob.
  static Future<void> loadRewardedAd({
    required void Function(RewardedInterstitialAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) async {
    await initialize();
    rewardedLoader(
      rewardedAdUnitId,
      RewardedInterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (error) {
          // Senza questo log l'unica traccia del fallimento era la snackbar
          // "Video non disponibile", che non dice quale sia la causa.
          debugPrint(
            '[AdService] rewarded non caricato: code=${error.code} '
            'domain=${error.domain} message=${error.message}',
          );
          onFailed(error);
        },
      ),
    );
  }

  static void _loadRewardedPlatform(
    String adUnitId,
    RewardedInterstitialAdLoadCallback callback,
  ) {
    RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(nonPersonalizedAds: true),
      rewardedInterstitialAdLoadCallback: callback,
    );
  }

  /// Mostra un interstitial con premio già caricato.
  ///
  /// Il formato può essere mostrato senza opt-in, ma la policy Google chiede
  /// comunque una schermata introduttiva con possibilità di rifiutare: qui
  /// arriva sempre dal dialog "Guarda il video / Annulla" della home, che la
  /// soddisfa. Non chiamarlo mai a freddo su un cambio di schermata.
  ///
  /// [onRewarded] → ricompensa guadagnata (chiamato prima della chiusura).
  /// [onDismissed] → ad chiusa (con o senza ricompensa).
  /// [onFailed]    → errore durante la visualizzazione.
  static void showRewardedAd(
    RewardedInterstitialAd ad, {
    required VoidCallback onRewarded,
    required VoidCallback onDismissed,
    required void Function(AdError error) onFailed,
  }) {
    bool rewarded = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedInterstitialAd>(
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
