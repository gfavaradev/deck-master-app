// Configurazione condivisa (client + server). Nessun segreto qui: la config
// Firebase pubblica (NEXT_PUBLIC_*) può stare nel bundle client.

export const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY!,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN!,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID!,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET!,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID!,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID!,
  measurementId: process.env.NEXT_PUBLIC_FIREBASE_MEASUREMENT_ID,
};

// Nome del cookie di sessione (HttpOnly). Definito qui — non in auth/session.ts —
// così può essere importato anche dal middleware (edge runtime), che non può
// caricare firebase-admin / moduli "server-only".
export const SESSION_COOKIE = "__session";

// Allowlist admin: coerente con isAdmin() nelle firestore.rules dell'app.
// Override via env ADMIN_EMAILS (CSV) senza ricompilare.
export const ADMIN_EMAILS = (
  process.env.ADMIN_EMAILS ?? "g.favara.dev@gmail.com,vivianaferreri98@gmail.com"
)
  .split(",")
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);

export function isAdminEmail(email?: string | null): boolean {
  return !!email && ADMIN_EMAILS.includes(email.toLowerCase());
}
