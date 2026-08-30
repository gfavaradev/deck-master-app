// Interpretazione dello stato di un abbonamento Google Play.
//
// Separata dalle funzioni perché è logica pura e senza I/O: decide *cosa* deve
// valere l'accesso Pro, mentre index.ts si occupa di autenticazione, chiamate
// alla Play Developer API, ordine degli eventi e scrittura su Firestore.
//
// Rimpiazza `revenuecat-events.ts` di deck-master-web, da cui eredita due
// scelte: lo stato si deduce dalla scadenza quando c'è, e `proExpiresAt` è una
// stringa ISO8601 perché `UserModel.fromFirestore` fa un cast diretto a String
// (un Timestamp Firestore la romperebbe).

/// Product ID degli abbonamenti Pro.
/// Devono combaciare con le costanti in lib/services/billing_service.dart.
export const PRO_PRODUCT_IDS = new Set([
  "deck_master_pro_monthly",
  "deck_master_pro_semiannual",
  "deck_master_pro_annual",
]);

export type SubscriptionLineItem = {
  productId?: string | null;
  expiryTime?: string | null;
};

/// Sottoinsieme di `SubscriptionPurchaseV2` che ci serve davvero.
export type SubscriptionPurchase = {
  subscriptionState?: string | null;
  lineItems?: SubscriptionLineItem[] | null;
  /// Token dell'abbonamento precedente quando l'utente cambia piano: Play ne
  /// emette uno nuovo e indica qui quello che sostituisce.
  linkedPurchaseToken?: string | null;
  externalAccountIdentifiers?: {
    obfuscatedExternalAccountId?: string | null;
  } | null;
  testPurchase?: unknown;
};

export type ProState = {
  isPro: boolean;
  /// ISO8601, il formato che l'app Flutter legge con DateTime.tryParse.
  proExpiresAt: string | null;
};

/// Stati che danno diritto all'accesso Pro finché la scadenza non è passata.
///
/// `CANCELED` è dentro di proposito: significa solo che il rinnovo automatico
/// è stato disattivato, e l'utente ha pagato fino alla scadenza. Toglierglielo
/// subito sarebbe rubargli i giorni che ha già comprato.
///
/// `IN_GRACE_PERIOD` è dentro perché è esattamente ciò a cui serve il periodo
/// di tolleranza: il pagamento è fallito, Google riprova, e nel frattempo il
/// servizio non va interrotto.
const ENTITLED_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_CANCELED",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
]);

// Fuori restano, tutti senza accesso:
//   ON_HOLD                    — pagamento fallito oltre la tolleranza
//   PAUSED                     — sospensione chiesta dall'utente
//   PENDING                    — creato ma mai pagato
//   EXPIRED                    — scaduto
//   PENDING_PURCHASE_CANCELED  — transazione in sospeso annullata
//   UNSPECIFIED                — stato ignoto: si nega, non si tira a indovinare

/// Scadenza più lontana fra le voci che riguardano un abbonamento Pro.
///
/// Un acquisto può contenere più `lineItems` (bundle, cambi di piano): conta
/// la più lontana, perché è fino a lì che l'utente ha pagato. Le voci di
/// prodotti che non sono nostri vengono ignorate.
export function proExpiryMsOf(purchase: SubscriptionPurchase): number | null {
  let latest: number | null = null;

  for (const item of purchase.lineItems ?? []) {
    const productId = item.productId;
    if (!productId || !PRO_PRODUCT_IDS.has(productId)) continue;

    const expiry = item.expiryTime;
    if (!expiry) continue;

    const ms = Date.parse(expiry);
    if (Number.isNaN(ms)) continue;

    if (latest === null || ms > latest) latest = ms;
  }

  return latest;
}

/// Stato Pro derivato da un acquisto letto dalla Play Developer API.
///
/// Lo stato dichiarato da Play e la scadenza devono essere d'accordo entrambi:
/// uno stato buono con scadenza passata capita quando la nostra lettura arriva
/// dopo la scadenza ma prima che Play aggiorni lo stato, e in quel caso vale
/// la scadenza. È lo stesso ragionamento di `UserModel.hasProAccess`, che
/// ricontrolla comunque la data lato client e si autocorregge.
export function proStateFromSubscription(
  purchase: SubscriptionPurchase,
  nowMs: number,
): ProState {
  const expiryMs = proExpiryMsOf(purchase);
  const proExpiresAt = expiryMs === null ? null : new Date(expiryMs).toISOString();

  const state = purchase.subscriptionState ?? "";
  if (!ENTITLED_STATES.has(state)) {
    return { isPro: false, proExpiresAt };
  }

  // Nessuna voce Pro nell'acquisto: è un abbonamento a un altro prodotto, non
  // dà accesso anche se è attivo.
  if (expiryMs === null) {
    return { isPro: false, proExpiresAt: null };
  }

  return { isPro: expiryMs > nowMs, proExpiresAt };
}

/// Vero se l'acquisto contiene almeno un prodotto Pro.
export function concernsPro(purchase: SubscriptionPurchase): boolean {
  return (purchase.lineItems ?? []).some(
    (item) => item.productId != null && PRO_PRODUCT_IDS.has(item.productId),
  );
}

// ── Real-Time Developer Notifications ───────────────────────────────────────

export type SubscriptionNotification = {
  version?: string;
  notificationType?: number;
  purchaseToken?: string;
  subscriptionId?: string;
};

export type VoidedPurchaseNotification = {
  purchaseToken?: string;
  orderId?: string;
  productType?: number;
  refundType?: number;
};

export type DeveloperNotification = {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string | number;
  subscriptionNotification?: SubscriptionNotification;
  voidedPurchaseNotification?: VoidedPurchaseNotification;
  testNotification?: { version?: string };
};

export type NotificationAction =
  | { kind: "ignore"; reason: string }
  | { kind: "refresh"; purchaseToken: string; eventAtMs: number }
  | { kind: "revoke"; purchaseToken: string; eventAtMs: number };

/// Decodifica il payload base64 di un messaggio Pub/Sub in una notifica Play.
/// Ritorna `null` se non è JSON valido: un messaggio malformato non va
/// ritentato all'infinito.
export function decodeDeveloperNotification(
  base64Data: string | undefined,
): DeveloperNotification | null {
  if (!base64Data) return null;
  try {
    const json = Buffer.from(base64Data, "base64").toString("utf8");
    const parsed: unknown = JSON.parse(json);
    if (typeof parsed !== "object" || parsed === null) return null;
    return parsed as DeveloperNotification;
  } catch {
    return null;
  }
}

/// Cosa fare di una notifica.
///
/// Il contenuto della notifica non viene mai creduto sulla parola: dice solo
/// *quale* acquisto è cambiato, poi lo stato vero si rilegge dall'API. L'unica
/// eccezione è il rimborso, dove l'accesso va tolto subito senza aspettare che
/// Play aggiorni lo stato dell'abbonamento.
export function actionForNotification(
  notification: DeveloperNotification,
  expectedPackageName: string,
): NotificationAction {
  if (notification.testNotification) {
    return { kind: "ignore", reason: "test" };
  }

  // Il topic Pub/Sub è per progetto, non per app: un'altra app dello stesso
  // progetto scriverebbe qui, e i suoi token non sono nostri.
  if (
    notification.packageName != null &&
    notification.packageName !== expectedPackageName
  ) {
    return { kind: "ignore", reason: "package" };
  }

  const eventAtMs = Number(notification.eventTimeMillis ?? Date.now());
  const safeEventAtMs = Number.isFinite(eventAtMs) ? eventAtMs : Date.now();

  const voided = notification.voidedPurchaseNotification;
  if (voided?.purchaseToken) {
    return {
      kind: "revoke",
      purchaseToken: voided.purchaseToken,
      eventAtMs: safeEventAtMs,
    };
  }

  const subscription = notification.subscriptionNotification;
  if (subscription?.purchaseToken) {
    return {
      kind: "refresh",
      purchaseToken: subscription.purchaseToken,
      eventAtMs: safeEventAtMs,
    };
  }

  // Acquisti one-time e notifiche di revisione rimborso: non abbiamo prodotti
  // che li generino.
  return { kind: "ignore", reason: "unsupported" };
}
