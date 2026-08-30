// Accesso alla Google Play Developer API.
//
// L'autenticazione usa le credenziali di default del runtime (ADC), cioè il
// service account con cui gira la funzione: nessuna chiave JSON nel repo né in
// Secret Manager. Quel service account va autorizzato una volta in Play Console
// (Utenti e autorizzazioni → invita l'indirizzo del SA → "Visualizza dati
// finanziari" + accesso all'app), esattamente come si farebbe con una chiave,
// ma senza materiale crittografico da custodire e ruotare.

import { google } from "googleapis";
import type { androidpublisher_v3 } from "googleapis";
import type { SubscriptionPurchase } from "./play-events";

/// Package dell'app: le notifiche e i token che non lo riguardano vanno
/// scartati.
export const PACKAGE_NAME = "com.giuseppe.deckmaster";

const SCOPE = "https://www.googleapis.com/auth/androidpublisher";

let client: androidpublisher_v3.Androidpublisher | null = null;

function publisher(): androidpublisher_v3.Androidpublisher {
  // Il client va costruito una volta sola e riusato fra invocazioni: ricrearlo
  // a ogni chiamata rifà anche il giro di autenticazione.
  client ??= google.androidpublisher({
    version: "v3",
    auth: new google.auth.GoogleAuth({ scopes: [SCOPE] }),
  });
  return client;
}

export class PlayApiError extends Error {
  constructor(
    message: string,
    readonly status: number | undefined,
  ) {
    super(message);
    this.name = "PlayApiError";
  }

  /// Vero se Play dice che il token non esiste o non è nostro: ritentare non
  /// serve a niente, va trattato come "nessun abbonamento".
  get isNotFound(): boolean {
    return this.status === 400 || this.status === 404 || this.status === 410;
  }
}

/// Stato reale di un abbonamento, letto da Play.
export async function getSubscription(
  purchaseToken: string,
): Promise<SubscriptionPurchase> {
  try {
    const response = await publisher().purchases.subscriptionsv2.get({
      packageName: PACKAGE_NAME,
      token: purchaseToken,
    });
    return response.data as SubscriptionPurchase;
  } catch (e) {
    const err = e as { message?: string; code?: number; status?: number };
    throw new PlayApiError(
      err.message ?? "chiamata a subscriptionsv2.get fallita",
      err.code ?? err.status,
    );
  }
}
