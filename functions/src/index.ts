// Verifica degli acquisti Google Play e ricezione delle notifiche di Play.
//
// Sostituisce il webhook RevenueCat di deck-master-web
// (src/app/api/webhooks/revenuecat/route.ts), che va rimosso quando questo
// flusso è verde in produzione.
//
// Due ingressi:
//   verifyPurchase — callable, chiamata dall'app subito dopo un acquisto o un
//                    ripristino. È l'unica cosa che accende il Pro.
//   playRtdn       — notifiche di Play (rinnovi, disdette, rimborsi) via
//                    Pub/Sub. È l'unica cosa che lo tiene aggiornato nel tempo.

import { createHash } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import * as logger from "firebase-functions/logger";

import {
  applyProState,
  inheritPurchaseLink,
  linkPurchaseToUser,
  uidForPurchaseToken,
} from "./entitlement";
import { PACKAGE_NAME, PlayApiError, getSubscription } from "./play-api";
import {
  PRO_PRODUCT_IDS,
  actionForNotification,
  concernsPro,
  decodeDeveloperNotification,
  proStateFromSubscription,
} from "./play-events";

initializeApp();

// Stessa regione del resto dell'infrastruttura (il Job Cloud Run price-sync) e
// della costante _kFunctionsRegion in lib/services/billing_service.dart: un
// mismatch qui si manifesta come "not-found" sulla callable, che è un sintomo
// che non fa pensare alla regione.
//
// Service account dedicato, non quello di Compute predefinito. Questo è il SA
// che va autorizzato in Play Console per la Developer API (play-api.ts usa le
// credenziali di default del runtime): col SA predefinito, l'accesso ai dati
// finanziari del Play Console sarebbe stato ereditato da ogni altro servizio
// del progetto che gira con la stessa identità, a partire dal Job Cloud Run
// price-sync. Deve esistere, con `actAs` per chi fa il deploy, prima del
// primo deploy che lo referenzia.
setGlobalOptions({
  region: "europe-west1",
  maxInstances: 10,
  serviceAccount: "play-billing@deck-master-1a35a.iam.gserviceaccount.com",
});

/// Topic Pub/Sub configurato in Play Console → Monetizzazione → Notifiche
/// per sviluppatori in tempo reale.
const RTDN_TOPIC = "play-billing-rtdn";

/// Come l'app deriva l'`obfuscatedAccountId` che passa a Play.
/// Deve restare allineata a `obfuscatedAccountIdFor` in billing_service.dart.
function obfuscatedAccountIdFor(uid: string): string {
  return createHash("sha256").update(uid, "utf8").digest("hex");
}

// ── verifyPurchase ──────────────────────────────────────────────────────────

export const verifyPurchase = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Serve un utente autenticato.");
  }

  const productId = request.data?.productId;
  const purchaseToken = request.data?.purchaseToken;

  if (typeof productId !== "string" || !PRO_PRODUCT_IDS.has(productId)) {
    throw new HttpsError("invalid-argument", "productId non riconosciuto.");
  }
  if (typeof purchaseToken !== "string" || purchaseToken.length === 0) {
    throw new HttpsError("invalid-argument", "purchaseToken mancante.");
  }

  let purchase;
  try {
    purchase = await getSubscription(purchaseToken);
  } catch (e) {
    const error = e as PlayApiError;
    if (error.isNotFound) {
      // Token inventato o già invalidato: non è un errore nostro e non va
      // ritentato, ma non deve nemmeno accendere il Pro.
      logger.warn("[play] token sconosciuto a Play", { uid });
      throw new HttpsError("not-found", "Acquisto non trovato su Google Play.");
    }
    // Errore transitorio: il client lascia l'acquisto senza acknowledge e
    // riprova da solo al prossimo avvio.
    logger.error("[play] subscriptionsv2.get fallita", {
      uid,
      status: error.status,
      message: error.message,
    });
    throw new HttpsError("unavailable", "Verifica non riuscita, riprova.");
  }

  // Il token è il segreto che dimostra l'acquisto, ma chi lo intercettasse
  // potrebbe rivenderlo: se Play ci ha restituito l'identificativo offuscato
  // che l'app aveva passato, deve essere quello di chi sta chiamando.
  const boundAccountId =
    purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  if (boundAccountId && boundAccountId !== obfuscatedAccountIdFor(uid)) {
    logger.warn("[play] acquisto associato a un altro account, rifiutato", {
      uid,
    });
    throw new HttpsError(
      "permission-denied",
      "L'acquisto appartiene a un altro account.",
    );
  }

  if (!concernsPro(purchase)) {
    throw new HttpsError("invalid-argument", "L'acquisto non riguarda il Pro.");
  }

  const now = Date.now();
  const state = proStateFromSubscription(purchase, now);

  // La mappatura si scrive anche quando lo stato non dà accesso: serve
  // comunque alle RTDN successive (un abbonamento in hold che si riprende).
  await linkPurchaseToUser(purchaseToken, uid, productId);

  const result = await applyProState(uid, state, now);
  if (result === "missing-user") {
    logger.error("[play] verifica per un utente senza documento", { uid });
    throw new HttpsError("failed-precondition", "Profilo utente non trovato.");
  }

  logger.info("[play] acquisto verificato", {
    uid,
    productId,
    isPro: state.isPro,
    result,
  });

  return { isPro: state.isPro, proExpiresAt: state.proExpiresAt };
});

// ── playRtdn ────────────────────────────────────────────────────────────────

export const playRtdn = onMessagePublished(
  {
    topic: RTDN_TOPIC,
    // Senza `retry` il trigger viene creato con RETRY_POLICY_DO_NOT_RETRY e
    // un'eccezione qui dentro fa semplicemente sparire il messaggio. Il codice
    // sotto rilancia apposta sugli errori transitori della Play API: con la
    // policy di default quel rilancio non ritenterebbe niente, e un rinnovo
    // perso lascerebbe `proExpiresAt` fermo fino all'evento successivo.
    // I casi non recuperabili (payload illeggibile, token sconosciuto) fanno
    // `return`, non `throw`, così non entrano nel ciclo di ritentativi.
    retry: true,
  },
  async (event) => {
    const notification = decodeDeveloperNotification(
      event.data.message.data,
    );

    if (notification === null) {
      // Messaggio illeggibile: lanciare farebbe ritentare Pub/Sub all'infinito
      // su un payload che non migliorerà mai.
      logger.error("[play] notifica non decodificabile, scartata");
      return;
    }

    const action = actionForNotification(notification, PACKAGE_NAME);
    if (action.kind === "ignore") {
      if (action.reason === "test") {
        // La notifica di prova del Play Console è l'unico modo di collaudare la
        // catena Play → Pub/Sub → funzione senza un acquisto vero: va a INFO,
        // altrimenti il collaudo non lascia traccia visibile.
        logger.info("[play] notifica di prova ricevuta: la catena RTDN funziona");
      } else {
        logger.debug("[play] notifica ignorata", { reason: action.reason });
      }
      return;
    }

    const { purchaseToken, eventAtMs } = action;

    if (action.kind === "revoke") {
      // Rimborso o storno: l'accesso va tolto subito, senza aspettare che lo
      // stato dell'abbonamento si aggiorni.
      const uid = await uidForPurchaseToken(purchaseToken);
      if (uid === null) {
        logger.warn("[play] rimborso su un token non mappato");
        return;
      }
      const result = await applyProState(
        uid,
        { isPro: false, proExpiresAt: null },
        eventAtMs,
      );
      logger.info("[play] accesso revocato dopo un rimborso", { uid, result });
      return;
    }

    // Il tipo di notifica dice solo *che* qualcosa è cambiato: lo stato vero si
    // rilegge sempre da Play, così un rinnovo, una disdetta e una ripresa da
    // hold passano tutti per lo stesso percorso.
    let purchase;
    try {
      purchase = await getSubscription(purchaseToken);
    } catch (e) {
      const error = e as PlayApiError;
      if (error.isNotFound) {
        logger.warn("[play] notifica su un token sconosciuto a Play");
        return;
      }
      // Rilanciare fa ritentare Pub/Sub, che è quello che vogliamo su un errore
      // transitorio.
      throw e;
    }

    let uid = await uidForPurchaseToken(purchaseToken);

    if (uid === null && purchase.linkedPurchaseToken) {
      // Cambio di piano: Play ha emesso un token nuovo che non abbiamo mai visto.
      uid = await inheritPurchaseLink(purchaseToken, purchase.linkedPurchaseToken);
    }

    if (uid === null) {
      // Succede se l'app non è mai riuscita a chiamare verifyPurchase. Il
      // recupero all'avvio ripasserà da lì e la mappatura si creerà allora.
      logger.warn("[play] notifica su un token non ancora mappato a un utente");
      return;
    }

    if (!concernsPro(purchase)) {
      logger.debug("[play] notifica su un prodotto non Pro");
      return;
    }

    const state = proStateFromSubscription(purchase, Date.now());
    const result = await applyProState(uid, state, eventAtMs);

    logger.info("[play] stato aggiornato da notifica", {
      uid,
      isPro: state.isPro,
      state: purchase.subscriptionState,
      result,
    });
  },
);
