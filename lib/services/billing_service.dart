import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// ID prodotti configurati in Play Console.
///
/// Su Google Play sono `subscriptionId`: un abbonamento può avere più base plan
/// e più offerte, e il negozio restituisce un [ProductDetails] per ognuna, tutte
/// con lo stesso [ProductDetails.id]. La selezione dell'offerta passa dal
/// relativo `offerToken`, non dall'id.
const kProductMonthly = 'deck_master_pro_monthly';
const kProductSemiannual = 'deck_master_pro_semiannual';
const kProductAnnual = 'deck_master_pro_annual';

const kProProductIds = <String>{
  kProductMonthly,
  kProductSemiannual,
  kProductAnnual,
};

/// Regione delle Cloud Functions, allineata al resto dell'infrastruttura
/// (il Job Cloud Run `price-sync` sta in `europe-west1`).
const _kFunctionsRegion = 'europe-west1';

/// Esito di un tentativo di acquisto, per la UI.
enum BillingOutcome {
  /// Acquisto completato e verificato dal server: il Pro è attivo.
  success,

  /// L'utente ha chiuso il foglio di Google Play.
  cancelled,

  /// Play ha accettato l'acquisto ma non l'ha ancora concluso (es. pagamento
  /// differito in contanti). Il Pro arriverà quando Play conferma.
  pending,

  /// Play ha registrato l'acquisto ma il backend non ha potuto verificarlo.
  /// L'acquisto **non** è stato acknowledgiato: si riprende al prossimo avvio.
  verificationFailed,

  /// Billing non disponibile su questa piattaforma o Play Store assente.
  unavailable,

  /// Errore riportato da Play.
  error,
}

/// Acquisti in-app tramite Google Play Billing.
///
/// Sostituisce RevenueCat. L'entitlement resta su `users/{uid}.isPro` e viene
/// scritto **solo** dal backend: qui non si tocca mai Firestore. Il client
/// manda `productId` + `purchaseToken` alla callable `verifyPurchase`, che
/// interroga la Play Developer API ed è l'unica ad avere l'ultima parola.
class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  /// Solo Android in questa fase. iOS/macOS useranno StoreKit in una fase
  /// successiva; su Windows e Web il paywall resta in sola lettura.
  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  StreamSubscription<User?>? _authSubscription;

  bool _available = false;
  List<ProductDetails> _products = const [];

  /// Ultimo abbonamento visto come attivo su questo dispositivo.
  ///
  /// Serve solo a puntare il deep link di gestione alla pagina di *quel*
  /// prodotto invece che alla lista di tutti gli abbonamenti dell'utente.
  /// Non è uno stato di autorizzazione — quello vive su Firestore — quindi va
  /// bene che si perda a ogni riavvio: senza, il link ripiega sulla lista.
  String? _activeProductId;

  /// Completer dell'acquisto in corso: gli esiti arrivano dallo stream, non
  /// dal `Future` di `buyNonConsumable`, che dice solo se il foglio si è
  /// aperto. È `null` quando l'acquisto viene ripreso senza UI davanti.
  Completer<BillingOutcome>? _pending;

  /// Ripristino chiesto dall'utente. Non nullo solo mentre è in corso: serve a
  /// distinguerlo dal giro di recupero silenzioso, che salta gli acquisti già
  /// acknowledgiati.
  Completer<bool>? _restore;

  final _proActivatedController = StreamController<void>.broadcast();

  /// Emette quando il backend ha confermato un acquisto: le pagine che tengono
  /// in cache `_isPro` possono rileggere lo stato.
  Stream<void> get onProActivated => _proActivatedController.stream;

  // ── Ciclo di vita ──────────────────────────────────────────────────────────

  /// Aggancia lo stream degli acquisti e l'auth Firebase.
  ///
  /// Va chiamata **una volta all'avvio**, non all'apertura del paywall: Play
  /// consegna su questo stream anche gli acquisti conclusi mentre l'app era
  /// chiusa, e un listener attaccato tardi li perde.
  Future<void> initialize() async {
    if (!isSupportedPlatform) return;

    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      debugPrint('[billing] isAvailable fallita: $e');
      _available = false;
    }
    if (!_available) return;

    _purchaseSubscription ??= _iap.purchaseStream.listen(
      _onPurchasesUpdated,
      onError: (Object e) => debugPrint('[billing] purchaseStream in errore: $e'),
    );

    // Al login si fa un giro di recupero: un acquisto rimasto senza
    // acknowledge (backend irraggiungibile, crash a metà) va ripreso, altrimenti
    // dopo 3 giorni Google lo rimborsa da solo.
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (user != null) _sweepPendingPurchases();
    });
  }

  void dispose() {
    _purchaseSubscription?.cancel();
    _authSubscription?.cancel();
    _purchaseSubscription = null;
    _authSubscription = null;
  }

  // ── Prodotti ───────────────────────────────────────────────────────────────

  /// Offerte disponibili su Play, vuota se il negozio non risponde.
  ///
  /// Può contenere più voci con lo stesso [ProductDetails.id] quando un
  /// abbonamento ha più base plan: la scelta la fa [productFor].
  Future<List<ProductDetails>> loadProducts() async {
    if (!isSupportedPlatform || !_available) return const [];
    try {
      final response = await _iap.queryProductDetails(kProProductIds);
      if (response.error != null) {
        debugPrint('[billing] queryProductDetails: ${response.error!.message}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        // Normale finché i prodotti non sono pubblicati e propagati su Play.
        debugPrint('[billing] prodotti non trovati: ${response.notFoundIDs}');
      }
      _products = response.productDetails;
      return _products;
    } catch (e) {
      debugPrint('[billing] caricamento prodotti fallito: $e');
      return const [];
    }
  }

  /// Offerta da usare per [productId], `null` se il negozio non la espone.
  ProductDetails? productFor(String productId) =>
      cheapestOfferFor(_products, productId);

  // ── Gestione dell'abbonamento ──────────────────────────────────────────────

  /// Pagina di Google Play da cui l'utente gestisce o disdice l'abbonamento.
  ///
  /// La disdetta avviene su Play, mai dentro l'app: l'abbonamento è un
  /// contratto fra l'utente e Google, e la policy Play pretende che dall'app
  /// ci sia comunque un accesso facile a questa pagina.
  Uri manageSubscriptionUri() => playSubscriptionUri(_activeProductId);

  // ── Acquisto ───────────────────────────────────────────────────────────────

  /// Avvia l'acquisto di [product] e attende l'esito reale.
  ///
  /// Il `Future` si risolve quando Play e il backend hanno risposto, non
  /// quando il foglio di pagamento si apre.
  Future<BillingOutcome> purchase(ProductDetails product) async {
    if (!isSupportedPlatform || !_available) return BillingOutcome.unavailable;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return BillingOutcome.error;

    // Un acquisto per volta: due fogli di pagamento sovrapposti lascerebbero
    // il primo completer appeso per sempre.
    if (_pending != null && !_pending!.isCompleted) {
      return BillingOutcome.error;
    }

    final completer = Completer<BillingOutcome>();
    _pending = completer;

    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: product,
          // `obfuscatedAccountId` per Play: l'UID non va passato in chiaro,
          // quindi ne mandiamo l'hash. Il backend risale all'utente dalla
          // mappatura purchaseToken → uid; questo è il riscontro incrociato.
          applicationUserName: obfuscatedAccountIdFor(uid),
          offerToken: (product is GooglePlayProductDetails)
              ? product.offerToken
              : null,
        ),
      );
      if (!started) {
        _pending = null;
        return BillingOutcome.error;
      }
    } catch (e) {
      debugPrint('[billing] avvio acquisto fallito: $e');
      _pending = null;
      return BillingOutcome.error;
    }

    return completer.future;
  }

  /// Ripristina gli acquisti dell'utente.
  ///
  /// Su Play significa rileggere gli abbonamenti attivi dal negozio e
  /// rimandarli al backend per la verifica: la fonte è Play, non un backup
  /// locale. Ritorna `true` se almeno un abbonamento risulta attivo.
  Future<bool> restore() async {
    if (!isSupportedPlatform || !_available) return false;

    final inFlight = _restore;
    if (inFlight != null && !inFlight.isCompleted) return inFlight.future;

    final completer = Completer<bool>();
    _restore = completer;

    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[billing] restore fallito: $e');
      _restore = null;
      return false;
    }

    // Play risponde sempre con un batch, anche vuoto, quindi il completer si
    // chiude da sé. Il tetto di attesa copre solo il caso in cui lo stream non
    // emetta affatto: meglio un "nessun acquisto" che una rotella infinita.
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _restore = null;
        return false;
      },
    );
  }

  /// Giro di recupero silenzioso al login.
  ///
  /// Non passa da [restore] perché non deve riverificare gli abbonamenti già
  /// acknowledgiati: cerca solo quelli rimasti a metà.
  Future<void> _sweepPendingPurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[billing] recupero acquisti pendenti fallito: $e');
    }
  }

  // ── Stream degli acquisti ──────────────────────────────────────────────────

  Future<void> _onPurchasesUpdated(List<PurchaseDetails> purchases) async {
    var anyActive = false;
    for (final purchase in purchases) {
      if (await _handlePurchase(purchase)) anyActive = true;
    }
    // Va chiuso anche su lista vuota: se l'utente non ha acquisti, Play manda
    // un batch vuoto ed è già la risposta definitiva.
    _resolveRestore(anyActive);
  }

  /// Ritorna `true` se l'acquisto risulta attivo e verificato dal backend.
  Future<bool> _handlePurchase(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        // Pagamento differito: niente acknowledge, niente Pro. Play tornerà
        // su questo stream quando l'incasso si conclude.
        _resolve(BillingOutcome.pending);
        return false;

      case PurchaseStatus.canceled:
        await _finishIfNeeded(purchase);
        _resolve(BillingOutcome.cancelled);
        return false;

      case PurchaseStatus.error:
        debugPrint('[billing] errore acquisto: ${purchase.error?.message}');
        await _finishIfNeeded(purchase);
        _resolve(BillingOutcome.error);
        return false;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _activeProductId = purchase.productID;
    }

    // Nel giro di recupero silenzioso un acquisto già acknowledgiato è lavoro
    // già fatto: rimandarlo al backend a ogni login sarebbe una chiamata
    // sprecata per ogni abbonato. In un restore chiesto dall'utente invece si
    // riverifica sempre, perché è proprio il modo di risincronizzare `isPro`.
    final isExplicitRestore = _restore != null && !_restore!.isCompleted;
    if (purchase.status == PurchaseStatus.restored &&
        !isExplicitRestore &&
        _isAlreadyAcknowledged(purchase)) {
      return true;
    }

    final verified = await _verifyOnServer(purchase);

    if (!verified) {
      // Volutamente nessun completePurchase: senza acknowledge Play riconsegna
      // l'acquisto al prossimo giro di recupero e la verifica si ritenta.
      // È lo stesso ragionamento di SyncService.syncOne(), dove il timestamp
      // locale si scrive dopo il download e non prima.
      _resolve(BillingOutcome.verificationFailed);
      return false;
    }

    await _finishIfNeeded(purchase);
    _proActivatedController.add(null);
    _resolve(BillingOutcome.success);
    return true;
  }

  // ── Verifica e acknowledge ─────────────────────────────────────────────────

  /// Manda l'acquisto alla callable `verifyPurchase`.
  ///
  /// L'UID non viaggia nel payload: lo prende la funzione dal token di
  /// autenticazione, così un client manomesso non può attivare il Pro a un
  /// altro utente.
  Future<bool> _verifyOnServer(PurchaseDetails purchase) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
          .httpsCallable('verifyPurchase');
      final result = await callable.call<Map<String, dynamic>>({
        'productId': purchase.productID,
        // Su Android `serverVerificationData` è il purchaseToken di Play.
        'purchaseToken': purchase.verificationData.serverVerificationData,
      });
      return result.data['isPro'] == true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[billing] verifica rifiutata: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[billing] verifica fallita: $e');
      return false;
    }
  }

  /// Acknowledge dell'acquisto presso Play.
  ///
  /// Va fatto entro 3 giorni o Google rimborsa automaticamente, ma solo dopo
  /// che il backend ha confermato: acknowledgiare un acquisto non verificato
  /// significa rinunciare all'unico meccanismo di ritentativo che abbiamo.
  Future<void> _finishIfNeeded(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } catch (e) {
      debugPrint('[billing] completePurchase fallita: $e');
    }
  }

  bool _isAlreadyAcknowledged(PurchaseDetails purchase) =>
      purchase is GooglePlayPurchaseDetails &&
      purchase.billingClientPurchase.isAcknowledged;

  void _resolve(BillingOutcome outcome) {
    final completer = _pending;
    _pending = null;
    if (completer != null && !completer.isCompleted) completer.complete(outcome);
  }

  void _resolveRestore(bool anyActive) {
    final completer = _restore;
    _restore = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(anyActive);
    }
  }
}

/// Identificativo opaco dell'utente da passare a Play come
/// `obfuscatedAccountId`.
///
/// Play vieta di mandare l'id dell'account in chiaro e accetta al massimo 64
/// caratteri: l'esadecimale di SHA-256 ne occupa esattamente 64.
String obfuscatedAccountIdFor(String uid) =>
    sha256.convert(utf8.encode(uid)).toString();

/// Offerta più economica fra quelle che il negozio espone per [productId].
///
/// Google Play restituisce un [ProductDetails] per **ogni** base plan e ogni
/// offerta dello stesso abbonamento, tutti con lo stesso [ProductDetails.id]:
/// un `firstWhere` sull'id prenderebbe quello che capita per primo. Fra piani
/// equivalenti si sceglie il prezzo più basso, perché mostrare o addebitare
/// più del minimo disponibile non è mai la scelta giusta verso l'utente.
ProductDetails? cheapestOfferFor(
  List<ProductDetails> products,
  String productId,
) {
  ProductDetails? best;
  for (final product in products) {
    if (product.id != productId) continue;
    if (best == null || product.rawPrice < best.rawPrice) best = product;
  }
  return best;
}

/// URL della pagina di gestione abbonamenti di Google Play.
///
/// Con [productId] punta direttamente a quell'abbonamento — un tap in meno per
/// disdire — altrimenti apre la lista di tutti quelli dell'utente, che è la
/// forma di ripiego documentata da Google.
Uri playSubscriptionUri(String? productId) {
  const base = 'https://play.google.com/store/account/subscriptions';
  if (productId == null || productId.isEmpty) return Uri.parse(base);
  return Uri.parse(base).replace(
    queryParameters: {'sku': productId, 'package': kAndroidPackageName},
  );
}

/// Package dell'app su Google Play, richiesto dal deep link di gestione.
const kAndroidPackageName = 'com.giuseppe.deckmaster';
