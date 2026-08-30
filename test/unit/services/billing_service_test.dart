import 'package:deck_master/services/billing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

ProductDetails _offer(String id, double price) => ProductDetails(
  id: id,
  title: id,
  description: id,
  price: '€${price.toStringAsFixed(2)}',
  rawPrice: price,
  currencyCode: 'EUR',
);

void main() {
  group('cheapestOfferFor', () {
    test('sceglie il base plan più economico fra quelli con lo stesso id', () {
      // Play restituisce una voce per ogni base plan/offerta dello stesso
      // abbonamento, tutte con lo stesso id: un firstWhere prenderebbe quella
      // che capita per prima, qui la 39.99.
      final products = [
        _offer(kProductAnnual, 39.99),
        _offer(kProductAnnual, 34.99),
        _offer(kProductMonthly, 4.99),
      ];

      expect(cheapestOfferFor(products, kProductAnnual)?.rawPrice, 34.99);
    });

    test('non confonde prodotti diversi', () {
      final products = [
        _offer(kProductMonthly, 4.99),
        _offer(kProductSemiannual, 22.99),
      ];

      expect(cheapestOfferFor(products, kProductAnnual), isNull);
      expect(
        cheapestOfferFor(products, kProductSemiannual)?.rawPrice,
        22.99,
      );
    });

    test('non si accontenta di un id che è prefisso di un altro', () {
      final products = [_offer('deck_master_pro_monthly', 4.99)];
      expect(cheapestOfferFor(products, 'deck_master_pro_month'), isNull);
    });

    test('regge un listino vuoto', () {
      expect(cheapestOfferFor(const [], kProductAnnual), isNull);
    });
  });

  group('obfuscatedAccountIdFor', () {
    const uid = 'aBcD1234567890eFgH';

    test('non lascia trapelare l\'UID in chiaro', () {
      // Play vieta di mandare l'identificativo dell'account come lo conosciamo.
      expect(obfuscatedAccountIdFor(uid), isNot(contains(uid)));
    });

    test('sta nei 64 caratteri ammessi da Play', () {
      expect(obfuscatedAccountIdFor(uid).length, 64);
    });

    test('è deterministico: lo stesso utente dà sempre lo stesso id', () {
      expect(obfuscatedAccountIdFor(uid), obfuscatedAccountIdFor(uid));
    });

    test('utenti diversi danno id diversi', () {
      expect(
        obfuscatedAccountIdFor(uid),
        isNot(obfuscatedAccountIdFor('${uid}x')),
      );
    });
  });

  group('kProProductIds', () {
    test('copre i tre piani mostrati dal paywall', () {
      expect(kProProductIds, {
        kProductMonthly,
        kProductSemiannual,
        kProductAnnual,
      });
    });
  });

  group('playSubscriptionUri', () {
    test('punta al singolo abbonamento quando conosciamo il prodotto', () {
      final uri = playSubscriptionUri(kProductAnnual);
      expect(uri.host, 'play.google.com');
      expect(uri.path, '/store/account/subscriptions');
      expect(uri.queryParameters['sku'], kProductAnnual);
      expect(uri.queryParameters['package'], kAndroidPackageName);
    });

    test('ripiega sulla lista completa senza prodotto', () {
      // Succede al primo avvio, prima che un acquisto passi dallo stream: la
      // pagina generale funziona comunque ed è la forma documentata da Google.
      final uri = playSubscriptionUri(null);
      expect(uri.toString(),
          'https://play.google.com/store/account/subscriptions');
      expect(uri.hasQuery, isFalse);
    });

    test('tratta la stringa vuota come prodotto assente', () {
      expect(playSubscriptionUri('').hasQuery, isFalse);
    });
  });
}
