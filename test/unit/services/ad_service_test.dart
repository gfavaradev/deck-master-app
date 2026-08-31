import 'dart:async';

import 'package:deck_master/services/ad_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Copre la sincronizzazione fra inizializzazione di AdMob e caricamento
/// dell'annuncio con premio. `main()` ritarda l'init di qualche secondo per non
/// rubare frame all'intro, mentre la home avvia il preload appena viene
/// montata: senza un'attesa esplicita il load può partire a SDK non ancora
/// pronto e fallisce sempre, mostrando all'utente "Video non disponibile".
void main() {
  setUp(AdService.debugReset);
  tearDown(AdService.debugReset);

  group('AdService.initialize', () {
    test('inizializza il plugin una sola volta anche su chiamate ripetute',
        () async {
      var calls = 0;
      AdService.platformInitializer = () async => calls++;

      await AdService.initialize();
      await AdService.initialize();

      expect(calls, 1);
    });

    test('chiamate concorrenti condividono la stessa inizializzazione',
        () async {
      var calls = 0;
      final gate = Completer<void>();
      AdService.platformInitializer = () async {
        calls++;
        await gate.future;
      };

      final first = AdService.initialize();
      final second = AdService.initialize();
      gate.complete();
      await Future.wait([first, second]);

      expect(calls, 1);
    });

    test('un fallimento non resta memorizzato: la chiamata dopo riprova',
        () async {
      var calls = 0;
      AdService.platformInitializer = () async {
        calls++;
        if (calls == 1) throw StateError('init fallita');
      };

      // Il fallimento va assorbito e loggato, non propagato al chiamante.
      await AdService.initialize();
      await AdService.initialize();

      expect(calls, 2);
    });
  });

  group('formato dell\'unità', () {
    test('carica il formato interstitial con premio, non il rewarded classico',
        () async {
      // L'unità di produzione è un interstitial con premio: caricarla con
      // RewardedAd.load faceva fallire ogni richiesta con "Ad unit doesn't
      // match format" e lo sblocco collezioni non funzionava mai.
      // Il tipo del callback è la prova statica di quale canale viene usato.
      AdService.platformInitializer = () async {};
      RewardedInterstitialAdLoadCallback? seen;
      AdService.rewardedLoader = (_, callback) => seen = callback;

      await AdService.loadRewardedAd(onLoaded: (_) {}, onFailed: (_) {});

      expect(seen, isA<RewardedInterstitialAdLoadCallback>());
    });

    test('in debug usa l\'id di test del formato giusto', () {
      // L'id di test di un formato non vale per un altro: sbagliarlo
      // riprodurrebbe in sviluppo lo stesso errore della produzione.
      expect(AdService.rewardedAdUnitId,
          'ca-app-pub-3940256099942544/5354046379');
    });
  });

  group('AdService.loadRewardedAd', () {
    test('non carica finché MobileAds non è inizializzato', () async {
      final initGate = Completer<void>();
      var loaderCalled = false;
      AdService.platformInitializer = () => initGate.future;
      AdService.rewardedLoader = (_, _) => loaderCalled = true;

      final pending = AdService.loadRewardedAd(
        onLoaded: (_) {},
        onFailed: (_) {},
      );
      await pumpEventQueue();

      expect(loaderCalled, isFalse,
          reason: 'il load è partito prima che l\'init fosse completata');

      initGate.complete();
      await pending;

      expect(loaderCalled, isTrue);
    });

    test('inoltra al chiamante l\'errore di caricamento', () async {
      AdService.platformInitializer = () async {};
      AdService.rewardedLoader = (_, callback) => callback.onAdFailedToLoad(
            LoadAdError(3, 'com.google.android.gms.ads', 'No fill.', null),
          );

      LoadAdError? received;
      await AdService.loadRewardedAd(
        onLoaded: (_) {},
        onFailed: (error) => received = error,
      );

      expect(received, isNotNull);
      expect(received!.code, 3);
      expect(received!.message, 'No fill.');
    });
  });
}
