// Verifica comportamentale di firestore.rules sui campi dell'abbonamento Pro.
//
// Non è un test unitario come gli altri: gira contro l'emulatore Firestore,
// quindi si lancia con `npm run test:rules` e non con `npm test`.
//
// Copre il buco che c'era prima: `allow update` lasciava all'utente il proprio
// documento purché non cambiasse `role`, quindi bastava una scrittura dal
// client per regalarsi il Pro.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, describe, it } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

const UID = "utente-normale";
const ADMIN_UID = "utente-admin";
const ADMIN_EMAIL = "g.favara.dev@gmail.com";

let env: RulesTestEnvironment;

function userDoc(uid: string) {
  return {
    uid,
    email: `${uid}@example.com`,
    createdAt: "2026-01-01T00:00:00.000Z",
    role: "user",
    isActive: true,
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-deck-master",
    firestore: {
      // __dirname è functions/lib dopo la compilazione.
      rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  // Stato iniziale scritto scavalcando le regole, come farebbe l'Admin SDK.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", UID), userDoc(UID));
    await setDoc(doc(db, "users", ADMIN_UID), userDoc(ADMIN_UID));
  });
});

after(async () => {
  await env.cleanup();
});

describe("firestore.rules — campi Pro", () => {
  it("SONDA: l'utente può auto-promuoversi ad amministratore?", async () => {
    // Se questa passa, la regola sulle sottocollezioni sta scavalcando quella
    // sul documento: `{document=**}` in rules_version 2 matcha anche zero
    // segmenti, quindi copre /users/{uid} stesso.
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", UID), { role: "administrator" }),
    );
  });

  it("l'utente può ancora aggiornare il proprio profilo", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertSucceeds(
      updateDoc(doc(db, "users", UID), { displayName: "Giuseppe" }),
    );
  });

  it("l'utente NON può regalarsi il Pro", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(updateDoc(doc(db, "users", UID), { isPro: true }));
  });

  it("l'utente NON può spostarsi la scadenza in avanti", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", UID), {
        proExpiresAt: "2099-01-01T00:00:00.000Z",
      }),
    );
  });

  it("l'utente NON può falsificare proSource o proEventAtMs", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", UID), { proSource: "manual" }),
    );
    await assertFails(
      updateDoc(doc(db, "users", UID), { proEventAtMs: 9999999999999 }),
    );
  });

  it("l'utente NON può nascondere il Pro dentro un update legittimo", async () => {
    // Il tentativo realistico: cambiare il nome e infilarci isPro nello stesso
    // documento, sperando che la regola guardi solo il campo dichiarato.
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", UID), {
        displayName: "Giuseppe",
        isPro: true,
      }),
    );
  });

  it("un nuovo profilo non può nascere già Pro", async () => {
    const db = env.authenticatedContext("nuovo-utente").firestore();
    await assertFails(
      setDoc(doc(db, "users", "nuovo-utente"), {
        ...userDoc("nuovo-utente"),
        isPro: true,
      }),
    );
  });

  it("un nuovo profilo senza campi Pro passa", async () => {
    const db = env.authenticatedContext("nuovo-utente-2").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users", "nuovo-utente-2"), userDoc("nuovo-utente-2")),
    );
  });

  it("un utente NON può toccare i campi Pro di qualcun altro", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(updateDoc(doc(db, "users", ADMIN_UID), { isPro: true }));
  });

  it("un admin con email verificata può ancora attivare il Pro a mano", async () => {
    const db = env
      .authenticatedContext(ADMIN_UID, {
        email: ADMIN_EMAIL,
        email_verified: true,
      })
      .firestore();
    await assertSucceeds(
      updateDoc(doc(db, "users", UID), { isPro: true, proSource: "manual" }),
    );
  });

  it("un finto admin senza email verificata non passa", async () => {
    const db = env
      .authenticatedContext("impostore", {
        email: ADMIN_EMAIL,
        email_verified: false,
      })
      .firestore();
    await assertFails(updateDoc(doc(db, "users", UID), { isPro: true }));
  });
});

describe("firestore.rules — sottocollezioni utente", () => {
  // Il vincolo {collection} aggiunto per chiudere il buco non deve aver
  // rotto l'accesso ai dati che l'utente possiede davvero.

  it("l'utente legge e scrive le proprie collezioni", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertSucceeds(
      setDoc(doc(db, "users", UID, "collections", "col-1"), { name: "Base" }),
    );
    await assertSucceeds(getDoc(doc(db, "users", UID, "collections", "col-1")));
  });

  it("l'utente scrive anche a profondità maggiore (carte dentro un album)", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertSucceeds(
      setDoc(doc(db, "users", UID, "albums", "alb-1", "cards", "card-1"), {
        name: "Dark Magician",
      }),
    );
  });

  it("l'utente non tocca le sottocollezioni di un altro", async () => {
    const db = env.authenticatedContext(UID).firestore();
    await assertFails(
      setDoc(doc(db, "users", ADMIN_UID, "collections", "col-1"), { name: "x" }),
    );
  });

  it("un anonimo non tocca nulla", async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "users", UID, "collections", "col-1")));
  });
});

describe("firestore.rules — signup reale dell'app", () => {
  // Riproduce esattamente il payload di UserService.createUser, che scrive il
  // documento intero con UserModel.toFirestore(): i campi Pro ci sono, ma
  // valorizzati a null. Se le regole non trattano "assente" e "null" allo
  // stesso modo, la registrazione si rompe.
  it("la registrazione passa con i campi Pro a null", async () => {
    const db = env.authenticatedContext("signup-reale").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users", "signup-reale"), {
        uid: "signup-reale",
        email: "nuovo@example.com",
        displayName: null,
        photoUrl: null,
        role: "user",
        createdAt: "2026-08-30T12:00:00.000Z",
        lastLoginAt: "2026-08-30T12:00:00.000Z",
        isActive: true,
        isPro: false,
        proSource: null,
        proExpiresAt: null,
      }),
    );
  });

  it("ma non se prova a nascere Pro", async () => {
    const db = env.authenticatedContext("signup-furbo").firestore();
    await assertFails(
      setDoc(doc(db, "users", "signup-furbo"), {
        uid: "signup-furbo",
        email: "furbo@example.com",
        role: "user",
        createdAt: "2026-08-30T12:00:00.000Z",
        isActive: true,
        isPro: true,
        proSource: "manual",
        proExpiresAt: "2099-01-01T00:00:00.000Z",
      }),
    );
  });
});
