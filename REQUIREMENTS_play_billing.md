# REQUIREMENTS — Abbonamenti Pro con Play Billing diretto (rimozione RevenueCat)

## Obiettivo

Sostituire RevenueCat con Google Play Billing usato direttamente dall'app
(`in_app_purchase`) e con una verifica server-side su Cloud Functions, mantenendo
`users/{uid}.isPro` come unica fonte di verità per l'accesso Pro.

## Contesto / stato attuale

### Cosa fa oggi RevenueCat (poco)

| File | Ruolo |
|---|---|
| `lib/main.dart:96` | `RevenueCatService().attachToAuthChanges()` — una riga |
| `lib/services/revenue_cat_service.dart` | configure/logIn/logOut, offerings, purchase, restore |
| `lib/pages/pro_page.dart` | paywall: `Offerings` per i prezzi, `purchasePackage`, `restorePurchases` |

Le API key sono ancora segnaposto (`appl_XXXX` / `goog_XXXX`), quindi
`RevenueCatService.isConfigured` è `false`: in produzione **non è mai partito un
acquisto e non esiste alcun abbonato**. Nessuna migrazione dati da fare.

### Cosa NON dipende da RevenueCat (non va toccato)

Tutto il gating Pro passa da `SubscriptionService().currentUserHasPro()` →
`users/{uid}` su Firestore → `UserModel.hasProAccess`:

- `lib/pages/deck_detail_page.dart:48,131`
- `lib/pages/main_layout.dart:94,151`
- `lib/pages/ai_deck_builder_page.dart:76`
- `lib/pages/card_scanner_page.dart:129`
- `lib/pages/home_page_simple.dart:44`

Questa è già l'architettura giusta: RevenueCat era solo il *produttore* dello
stato, mai il consumatore.

### Il ponte da ricostruire

`../deck-master-web/src/app/api/webhooks/revenuecat/route.ts` +
`src/lib/subscriptions/revenuecat-events.ts` traducono gli eventi RevenueCat in
scritture su `users/{uid}`. Vanno sostituiti, non modificati. Da quel codice si
riportano tre comportamenti già corretti:

1. Scrittura in transazione, mai `create` di un documento utente parziale.
2. Guardia sugli eventi fuori ordine tramite `proEventAtMs`.
3. Errore → 500/retry, non swallow silenzioso.

### Buco di sicurezza preesistente

`firestore.rules:120-124` consente a un utente di aggiornare il proprio
documento purché non cambi `role`. **Oggi chiunque può scriversi
`isPro: true`.** Va chiuso in questo intervento: con il billing diretto è il
punto centrale del modello di sicurezza.

## Requisiti funzionali

> **Stato al 30/08/2026**: client, backend e regole Firestore completati.
> `flutter analyze` pulito, 250 test Flutter verdi, 21 test Functions verdi,
> 17 test di regole verdi contro l'emulatore, App Bundle release costruito con
> R8 attivo. Resta da fare la configurazione su Play Console e il deploy.

### Client Android

- [x] Rimuovere `purchases_flutter`, aggiungere `in_app_purchase: ^3.3.0`
      (→ `in_app_purchase_android` 0.5.x → Play Billing **8.0.0**; `minSdk 24`
      del progetto soddisfa il requisito SDK 24+ del plugin).
- [x] Nuovo `lib/services/billing_service.dart` in sostituzione di
      `revenue_cat_service.dart`, stessa superficie pubblica dove possibile
      (`getProducts`, `purchase`, `restore`, `isSupportedPlatform`).
- [x] Il listener su `InAppPurchase.instance.purchaseStream` è agganciato
      **all'avvio dell'app** (`main.dart`), non all'apertura del paywall.
      **Correzione allo spec iniziale**: il plugin Android **non** riconsegna da
      solo gli acquisti alla sottoscrizione dello stream — `restorePurchases()`
      è l'unica cosa che interroga Play (`queryPurchases`) e riemette il batch.
      Serve quindi un giro di recupero esplicito, agganciato a
      `authStateChanges`.
- [x] `completePurchase()` (acknowledge) va chiamato **solo dopo** che la
      Cloud Function ha confermato la verifica, ma **entro 3 giorni**: oltre,
      Google rimborsa automaticamente. Se la verifica fallisce, l'acquisto resta
      pending e va ritentato al prossimo avvio — non acknowledgiare mai un
      acquisto non verificato.
- [x] `PurchaseParam.applicationUserName` = UID Firebase, così Play registra
      l'`obfuscatedAccountId` e il backend ha un secondo modo di risalire
      all'utente se la mappatura token→uid si perde.
- [x] `pro_page.dart`: `Offerings`/`Package` → `List<ProductDetails>`;
      `storeProduct.priceString/price/currencyCode` → `ProductDetails.price` /
      `.rawPrice` / `.currencyCode`. Il listino di riserva in euro
      (`_fallbackMonthly/_fallbackSemiannual/_fallbackAnnual`) e
      `savingsPercent()` restano invariati.
- [x] **Verificato sul sorgente del plugin**: `GooglePlayProductDetails` usa
      `id: productDetails.productId`, cioè l'id **nudo**, e produce una voce per
      **ogni** base plan/offerta dello stesso abbonamento — tutte con lo stesso
      id. Il formato `<subscriptionId>:<basePlanId>` era una convenzione
      RevenueCat: `matchesProductId()` è stato rimosso da
      `lib/utils/subscription_pricing.dart` insieme ai suoi test, sostituito da
      `cheapestOfferFor()` in `billing_service.dart`, che sceglie il prezzo più
      basso fra le voci con lo stesso id.
- [x] Degradazione su Windows/Web/iOS: paywall visibile con il listino di
      riserva, pulsanti di acquisto e ripristino nascosti.
      **`lib/utils/platform_helper.dart` non esiste** (CLAUDE.md lo cita, ma non
      c'è traccia di `PlatformHelper` in `lib/`): il gate resta
      `BillingService.isSupportedPlatform`, come faceva `RevenueCatService`.

### Vincolo emerso: `cloud_functions` obbliga a un bump di Firebase

`cloud_functions` 6.4.0 dipende da `firebase_core ^4.14.0`, e `firebase_core`
4.14.0 ha rimosso il campo statico `FlutterFirebaseCorePlugin.customAuthDomain`
che `firebase_auth` 6.5.7 referenzia: la build Android fallisce in
`:firebase_auth:compileReleaseJavaWithJavac`. Il bump di `firebase_auth` a
`^6.6.1` non è opzionale, è la condizione per usare le callable. `cloud_firestore`
e `firebase_messaging` non sono stati toccati.

### Backend — Cloud Functions (in questo repo)

- [x] Inizializzare `functions/` (2ª gen, Node 22, TypeScript) e aggiungere il
      blocco `functions` a `firebase.json`, che oggi non ce l'ha.
- [x] `verifyPurchase` — **callable** (`onCall`): l'UID arriva da
      `request.auth.uid`, mai dal payload del client. Input
      `{ productId, purchaseToken }`. Chiama
      `androidpublisher.purchases.subscriptionsv2.get`, deriva
      `isPro`/`proExpiresAt` e scrive `users/{uid}` in transazione con la
      guardia `proEventAtMs`. Scrive anche `play_purchases/{purchaseToken}` →
      `{ uid, productId, linkedAt }` per il lookup successivo dell'RTDN.
- [x] `playRtdn` — trigger Pub/Sub (`onMessagePublished`) sul topic configurato
      in Play Console. Alla notifica **non si crede sul contenuto**: si estrae
      il `purchaseToken` e si rilegge lo stato reale dalla Play Developer API.
      Risoluzione UID: `play_purchases/{purchaseToken}`, con fallback su
      `externalAccountIdentifiers.obfuscatedExternalAccountId`.
- [x] Logica di mappatura stato → `{isPro, proExpiresAt}` isolata in un modulo
      puro (`functions/src/play-events.ts`), sul modello di
      `revenuecat-events.ts`, così è testabile senza rete. Deve coprire:
      rinnovo, disdetta (Pro fino a scadenza), scadenza, grace period,
      account hold, revoca/rimborso (Pro immediatamente `false`), pausa.
- [x] **Deviazione dallo spec, in meglio**: niente chiave JSON né Secret
      Manager. `play-api.ts` usa le credenziali di default del runtime (ADC),
      cioè il service account con cui gira la funzione. Play Console permette di
      autorizzare direttamente quell'indirizzo, quindi non esiste materiale
      crittografico da custodire, ruotare o far trapelare.

### Vulnerabilità preesistente trovata durante i test delle regole

`match /users/{userId}/{document=**}` — in `rules_version = '2'` un wildcard
ricorsivo matcha **anche zero segmenti**, quindi quella regola copriva pure il
documento `/users/{userId}` stesso. Poiché in Firestore basta una regola che
consenta, il suo `allow read, write` scavalcava sia il divieto di cambiare
`role` sia (una volta aggiunto) quello sui campi Pro.

**Conseguenza in produzione**: qualsiasi utente autenticato poteva scriversi
`role: "administrator"` sul proprio documento. Non dava poteri su Firestore
(`isAdmin()` nelle regole guarda l'email, non il ruolo), ma
`UserModel.hasProAccess` ritorna `true` per gli admin: era Pro gratis per
chiunque sapesse scrivere un documento, e l'app lo trattava come amministratore.

Corretto rendendo obbligatorio il segmento di collezione:
`match /users/{userId}/{collection}/{document=**}`. Coperto da
`functions/src/rules-check.ts`, insieme ai test di regressione che verificano
che le sottocollezioni legittime restino accessibili a ogni profondità.

### Sicurezza

- [x] `firestore.rules`: negare al client la scrittura di `isPro`, `proSource`,
      `proExpiresAt`, `proEventAtMs` su `users/{userId}` (le Cloud Functions
      usano l'Admin SDK e bypassano le rules). Mantenere il resto
      dell'update del proprio profilo.
- [x] Verificare che l'attivazione manuale da `deck-master-web` continui a
      funzionare (usa Admin SDK → non impattata).

### Trappola evitata sui default delle regole

`UserModel.toFirestore()` scrive i campi Pro **valorizzati a `null`**, non li
omette. Le prime regole usavano `''` come default in `get()`, e questo rifiutava
la registrazione di ogni nuovo utente (`UserService.createUser` scrive il
documento intero). Il default corretto è `null`. Il caso è bloccato da un test
che riproduce il payload esatto del signup.

### Play Console

- [ ] Creare i 3 abbonamenti con i product ID già cablati in
      `revenue_cat_service.dart:10-12`: `deck_master_pro_monthly`,
      `deck_master_pro_semiannual`, `deck_master_pro_annual`.
- [ ] Configurare il topic Pub/Sub `play-billing-rtdn` per le RTDN (il nome è
      cablato in `functions/src/index.ts`).
- [ ] Play Console → Utenti e autorizzazioni → invitare l'indirizzo del service
      account del runtime delle Functions, con "Visualizza dati finanziari" e
      accesso all'app.

## Vincoli tecnici

- Piattaforme: **Android soltanto** in questa iterazione. iOS/macOS restano con
  il paywall in sola lettura; Windows/Web degradano via `PlatformHelper`.
- Nessun accesso diretto a Firestore dalle pagine: il paywall parla con
  `BillingService` e `SubscriptionService`, mai con `FirebaseFirestore`.
- Localizzazione IT/EN: le stringhe esistenti (`proNotAvailable`,
  `proPurchasesRestored`, `proNoPurchasesToRestore`, `proWelcomeMsg`) si
  riusano. Servono nuove chiavi solo per gli stati che RevenueCat nascondeva:
  verifica in corso, acquisto in attesa di conferma, verifica fallita.
- App Check è in enforcement su Firestore: verificare che le callable non
  vengano rifiutate in debug (vedi memoria `project_appcheck_enforcement`).
- `flutter analyze` pulito; `scripts/**` è escluso dall'analisi ma `functions/**`
  va aggiunto all'esclusione in `analysis_options.yaml`.

## Criteri di accettazione

- [ ] `flutter analyze` pulito sulle modifiche.
- [ ] `flutter test test/ --no-pub` verde.
- [ ] Test unitari nuovi: `functions/src/play-events.ts` (mappatura stati, in
      particolare rimborso e grace period) e `subscription_pricing_test` se il
      formato degli id cambia.
- [ ] Test dell'idempotenza: la stessa RTDN consegnata due volte, e una RTDN
      vecchia dopo una nuova, non devono alterare lo stato.
- [ ] Verifica manuale end-to-end su **build release firmata**, track interno,
      con un account nella lista tester di licenza: acquisto → `isPro: true` in
      Firestore → funzionalità Pro sbloccate; disdetta → Pro fino a scadenza;
      rimborso → Pro revocato.
- [ ] Verifica del percorso di crash: acquisto completato con backend
      irraggiungibile → al riavvio l'acquisto pending viene ripreso e verificato
      (stessa classe di problema di `SyncService.syncOne()`, cfr. CLAUDE.md).

## Fuori scope

- iOS/macOS: App Store Server API + App Store Server Notifications V2 sono una
  seconda fase.
- Upgrade/downgrade fra piani (proration, `ChangeSubscriptionParam`): il primo
  rilascio supporta il solo acquisto da free.
- Codici promozionali, offerte introduttive, prove gratuite.
- Rimozione del webhook RevenueCat da `deck-master-web`: va fatta, ma è un
  intervento sull'altro repo, da coordinare dopo che il nuovo flusso è verde.
