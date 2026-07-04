"use client";

import { initializeApp, getApps, getApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { firebaseConfig } from "@/lib/config";

// SDK client Firebase: usato SOLO per l'autenticazione (login admin).
// Tutti gli accessi ai dati passano dal backend server-side (firebase-admin),
// che bypassa App Check e le security rules — vedi lib/firebase/admin.ts.
const app = getApps().length ? getApp() : initializeApp(firebaseConfig);

export const auth = getAuth(app);
