import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// ID entitlement configurato in RevenueCat dashboard
const _kProEntitlement = 'pro';

/// ID prodotti da configurare in App Store Connect e Google Play Console
const kProductMonthly    = 'deck_master_pro_monthly';
const kProductSemiannual = 'deck_master_pro_semiannual';
const kProductAnnual     = 'deck_master_pro_annual';

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
  StreamSubscription<User?>? _authSubscription;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static String get _apiKey =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)
          ? _appleApiKey
          : _googleApiKey;

  /// Vero quando le API key sono state sostituite con quelle reali.
  ///
  /// Con i segnaposto `Purchases.configure` fallisce a ogni login: meglio non
  /// chiamarlo affatto che riempire i log di errori a ogni avvio.
  static bool get isConfigured => !_apiKey.contains('XXXX');

  /// Collega RevenueCat allo stato di autenticazione Firebase.
  ///
  /// Da chiamare una volta all'avvio. L'UID Firebase diventa l'appUserID, così
  /// l'abbonamento segue l'account e non il dispositivo, ed è la stessa chiave
  /// con cui il webhook ritrova l'utente su Firestore.
  void attachToAuthChanges() {
    if (!isSupportedPlatform || !isConfigured) return;
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (user != null) {
        initialize(user.uid);
      } else {
        logOut();
      }
    });
  }

  /// Inizializza RevenueCat con l'UID Firebase come customerID.
  /// Normalmente la chiama [attachToAuthChanges] a ogni login.
  Future<void> initialize(String userId) async {
    if (!isSupportedPlatform || !isConfigured) return;
    try {
      if (_initialized) {
        await Purchases.logIn(userId);
        return;
      }
      await Purchases.configure(
        PurchasesConfiguration(_apiKey)..appUserID = userId,
      );
      Purchases.addCustomerInfoUpdateListener(_customerInfoController.add);
      _initialized = true;
    } catch (e) {
      // Un errore qui non deve impedire il login: l'utente resta senza Pro
      // finché non si risolve, ma l'app funziona.
      debugPrint('[RevenueCat] inizializzazione fallita: $e');
    }
  }

  /// Scollega l'utente da RevenueCat al logout, così l'abbonamento non resta
  /// associato al prossimo account che accede dallo stesso dispositivo.
  Future<void> logOut() async {
    if (!isSupportedPlatform || !_initialized) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('[RevenueCat] logout fallito: $e');
    }
  }

  /// Ritorna le offerte disponibili (packages mensile/annuale).
  Future<Offerings?> getOfferings() async {
    if (!isSupportedPlatform || !_initialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) { // ignore: empty_catches
      return null;
    }
  }

  /// Esegue l'acquisto di un package.
  /// Ritorna true se l'acquisto è andato a buon fine.
  Future<bool> purchasePackage(Package package) async {
    if (!isSupportedPlatform || !_initialized) return false;
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
    if (!isSupportedPlatform || !_initialized) return false;
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
    if (!isSupportedPlatform || !_initialized) return false;
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
