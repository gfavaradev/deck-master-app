// Scrittura dell'entitlement Pro su Firestore.
//
// È l'unico punto del sistema che tocca `users/{uid}.isPro`: l'app lo legge e
// basta (SubscriptionService), e le regole Firestore vietano al client di
// scriverlo. Le funzioni usano l'Admin SDK, che le regole non le applica.

import { getFirestore, type Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import type { ProState } from "./play-events";

/// Mappatura purchaseToken → utente.
///
/// Serve alle RTDN: la notifica di rinnovo porta il token, non l'UID. Senza
/// questa collection un rinnovo non saprebbe a chi applicarsi.
const PURCHASES_COLLECTION = "play_purchases";

export type ApplyResult = "applied" | "stale" | "missing-user";

let db: Firestore | null = null;

function firestore(): Firestore {
  db ??= getFirestore();
  return db;
}

/// Applica [state] all'utente [uid].
///
/// [eventAtMs] è il momento a cui lo stato si riferisce: una notifica più
/// vecchia di quella già applicata viene scartata. Pub/Sub consegna almeno una
/// volta e senza garanzia d'ordine, quindi senza questa guardia un RENEWED in
/// ritardo potrebbe resuscitare un abbonamento già scaduto.
export async function applyProState(
  uid: string,
  state: ProState,
  eventAtMs: number,
): Promise<ApplyResult> {
  const ref = firestore().collection("users").doc(uid);

  return firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);

    // Non creiamo documenti utente da qui: UserModel.fromFirestore pretende
    // uid, email e createdAt, e un documento parziale renderebbe l'utente
    // illeggibile all'app. Se manca è un'anomalia da guardare, non da
    // silenziare: chi acquista ha per forza fatto login prima.
    if (!snap.exists) return "missing-user";

    const lastMs = snap.get("proEventAtMs");
    if (typeof lastMs === "number" && eventAtMs < lastMs) return "stale";

    tx.set(
      ref,
      {
        isPro: state.isPro,
        proSource: "iap",
        proExpiresAt: state.proExpiresAt,
        proEventAtMs: eventAtMs,
      },
      { merge: true },
    );
    return "applied";
  });
}

/// Registra a quale utente appartiene un purchaseToken.
///
/// Scritta alla verifica dell'acquisto, letta dalle RTDN. Il merge tiene conto
/// che lo stesso token viene riverificato a ogni restore.
export async function linkPurchaseToUser(
  purchaseToken: string,
  uid: string,
  productId: string,
): Promise<void> {
  await firestore()
    .collection(PURCHASES_COLLECTION)
    .doc(purchaseToken)
    .set(
      { uid, productId, linkedAtMs: Date.now() },
      { merge: true },
    );
}

/// Utente a cui appartiene [purchaseToken], `null` se non lo sappiamo.
export async function uidForPurchaseToken(
  purchaseToken: string,
): Promise<string | null> {
  const snap = await firestore()
    .collection(PURCHASES_COLLECTION)
    .doc(purchaseToken)
    .get();

  if (!snap.exists) return null;
  const uid = snap.get("uid");
  return typeof uid === "string" && uid.length > 0 ? uid : null;
}

/// Sposta la mappatura da un token vecchio a uno nuovo.
///
/// Play emette un token nuovo a ogni upgrade/downgrade di piano e indica il
/// precedente in `linkedPurchaseToken`: senza questo travaso, la prima RTDN sul
/// token nuovo non troverebbe l'utente.
export async function inheritPurchaseLink(
  newToken: string,
  previousToken: string,
): Promise<string | null> {
  const uid = await uidForPurchaseToken(previousToken);
  if (uid === null) return null;

  const previous = await firestore()
    .collection(PURCHASES_COLLECTION)
    .doc(previousToken)
    .get();
  const productId = previous.get("productId");

  await linkPurchaseToUser(
    newToken,
    uid,
    typeof productId === "string" ? productId : "",
  );
  logger.info("[play] mappatura ereditata da un token precedente", { uid });
  return uid;
}
