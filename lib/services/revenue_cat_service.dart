import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// ID entitlement configurato in RevenueCat dashboard
const _kProEntitlement = 'pro';

/// ID prodotti da configurare in App Store Connect e Google Play Console
const kProductMonthly = 'deck_master_pro_monthly';
const kProductAnnual = 'deck_master_pro_annual';

/// Servizio che wrappa RevenueCat per gestire abbonamenti Pro.
/// Da configurare:
///  1. Creare i prodotti in App Store Connect e Google Play Console
///  2. Sostituire le API key con quelle del progetto RevenueCat
///  3. Configurare l'entitlement "pro" nel dashboard RevenueCat
class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  // TODO: sostituire con le API key del progetto RevenueCat
  static const String _appleApiKey = 'appl_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
  static const String _googleApiKey = 'goog_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';

  bool _initialized = false;

  /// Inizializza RevenueCat con l'UID Firebase come customerID.
  /// Chiamare dopo il login dell'utente.
  Future<void> initialize(String userId) async {
    if (kIsWeb) return;
    if (_initialized) {
      await Purchases.logIn(userId);
      return;
    }

    final apiKey = defaultTargetPlatform == TargetPlatform.iOS
        ? _appleApiKey
        : _googleApiKey;

    await Purchases.configure(
      PurchasesConfiguration(apiKey)..appUserID = userId,
    );
    Purchases.addCustomerInfoUpdateListener(_customerInfoController.add);
    _initialized = true;
  }

  /// Ritorna le offerte disponibili (packages mensile/annuale).
  Future<Offerings?> getOfferings() async {
    if (kIsWeb || !_initialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) { // ignore: empty_catches
      return null;
    }
  }

  /// Esegue l'acquisto di un package.
  /// Ritorna true se l'acquisto è andato a buon fine.
  Future<bool> purchasePackage(Package package) async {
    if (kIsWeb || !_initialized) return false;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return result.customerInfo.entitlements.active.containsKey(_kProEntitlement);
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) return false;
      return false;
    } catch (e) { // ignore: empty_catches
      return false;
    }
  }

  /// Controlla se l'utente corrente ha l'entitlement Pro attivo.
  Future<bool> hasPro() async {
    if (kIsWeb || !_initialized) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(_kProEntitlement);
    } catch (e) { // ignore: empty_catches
      return false;
    }
  }

  /// Ripristina gli acquisti precedenti.
  /// Ritorna true se Pro è stato ripristinato.
  Future<bool> restorePurchases() async {
    if (kIsWeb || !_initialized) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(_kProEntitlement);
    } catch (e) { // ignore: empty_catches
      return false;
    }
  }

  final _customerInfoController = StreamController<CustomerInfo>.broadcast();

  /// Stream che emette [CustomerInfo] aggiornato quando cambia lo stato abbonamento.
  Stream<CustomerInfo> get customerInfoStream => _customerInfoController.stream;

}
