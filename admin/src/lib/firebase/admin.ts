import "server-only";

import {
  cert,
  getApps,
  initializeApp,
  applicationDefault,
  type App,
  type Credential,
} from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "node:fs";

// Backend server-side: firebase-admin con service account.
// Bypassa App Check e le security rules Firestore — questo è il motivo per cui
// la dashboard non ha il problema di timeout App Check delle build client.
//
// Fonti credenziali, in ordine:
//   1. FIREBASE_SERVICE_ACCOUNT       → JSON del service account (stringa) [Vercel]
//   2. FIREBASE_SERVICE_ACCOUNT_PATH  → percorso al file JSON              [dev locale]
//   3. GOOGLE_APPLICATION_CREDENTIALS → applicationDefault()
//
// L'init è lazy: il build Next non richiede credenziali; l'errore scatta solo
// alla prima chiamata reale (health check / auth).

let cachedApp: App | null = null;

function loadCredential(): Credential {
  const json = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (json) return cert(JSON.parse(json));

  const path = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (path) return cert(JSON.parse(readFileSync(path, "utf8")));

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return applicationDefault();

  throw new Error(
    "Service account Firebase non configurato: imposta FIREBASE_SERVICE_ACCOUNT (JSON) o FIREBASE_SERVICE_ACCOUNT_PATH (percorso file).",
  );
}

export function adminApp(): App {
  if (cachedApp) return cachedApp;
  cachedApp = getApps().length
    ? getApps()[0]
    : initializeApp({ credential: loadCredential() });
  return cachedApp;
}

export const adminAuth = () => getAuth(adminApp());
export const adminDb = () => getFirestore(adminApp());
