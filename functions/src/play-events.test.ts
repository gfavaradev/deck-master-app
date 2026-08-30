import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  actionForNotification,
  concernsPro,
  decodeDeveloperNotification,
  proExpiryMsOf,
  proStateFromSubscription,
  type DeveloperNotification,
  type SubscriptionPurchase,
} from "./play-events";

const NOW = Date.parse("2026-08-30T12:00:00.000Z");
const FUTURE = "2026-09-30T12:00:00.000Z";
const PAST = "2026-08-01T12:00:00.000Z";

function purchase(
  state: string,
  items: Array<{ productId: string; expiryTime: string }> = [
    { productId: "deck_master_pro_annual", expiryTime: FUTURE },
  ],
): SubscriptionPurchase {
  return { subscriptionState: state, lineItems: items };
}

describe("proStateFromSubscription", () => {
  it("dà accesso a un abbonamento attivo", () => {
    const state = proStateFromSubscription(
      purchase("SUBSCRIPTION_STATE_ACTIVE"),
      NOW,
    );
    assert.equal(state.isPro, true);
    assert.equal(state.proExpiresAt, new Date(Date.parse(FUTURE)).toISOString());
  });

  it("tiene il Pro fino a scadenza dopo una disdetta", () => {
    // CANCELED significa solo che il rinnovo automatico è spento: i giorni
    // già pagati restano dell'utente.
    assert.equal(
      proStateFromSubscription(purchase("SUBSCRIPTION_STATE_CANCELED"), NOW)
        .isPro,
      true,
    );
  });

  it("non interrompe il servizio durante il periodo di tolleranza", () => {
    assert.equal(
      proStateFromSubscription(
        purchase("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"),
        NOW,
      ).isPro,
      true,
    );
  });

  it("toglie l'accesso in account hold, in pausa e da scaduto", () => {
    for (const state of [
      "SUBSCRIPTION_STATE_ON_HOLD",
      "SUBSCRIPTION_STATE_PAUSED",
      "SUBSCRIPTION_STATE_EXPIRED",
      "SUBSCRIPTION_STATE_PENDING",
      "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
    ]) {
      assert.equal(
        proStateFromSubscription(purchase(state), NOW).isPro,
        false,
        state,
      );
    }
  });

  it("nega davanti a uno stato che non conosce invece di tirare a indovinare", () => {
    assert.equal(
      proStateFromSubscription(purchase("SUBSCRIPTION_STATE_UNSPECIFIED"), NOW)
        .isPro,
      false,
    );
    assert.equal(
      proStateFromSubscription(purchase("QUALCOSA_DI_NUOVO"), NOW).isPro,
      false,
    );
  });

  it("la scadenza passata vince sullo stato ancora attivo", () => {
    // Capita quando leggiamo dopo la scadenza ma prima che Play aggiorni lo
    // stato: senza questo controllo l'utente resterebbe Pro a tempo indeterminato.
    const state = proStateFromSubscription(
      purchase("SUBSCRIPTION_STATE_ACTIVE", [
        { productId: "deck_master_pro_monthly", expiryTime: PAST },
      ]),
      NOW,
    );
    assert.equal(state.isPro, false);
    assert.equal(state.proExpiresAt, new Date(Date.parse(PAST)).toISOString());
  });

  it("non dà accesso se l'abbonamento attivo non contiene prodotti Pro", () => {
    const state = proStateFromSubscription(
      purchase("SUBSCRIPTION_STATE_ACTIVE", [
        { productId: "un_altro_prodotto", expiryTime: FUTURE },
      ]),
      NOW,
    );
    assert.equal(state.isPro, false);
    assert.equal(state.proExpiresAt, null);
  });

  it("regge un acquisto senza lineItems", () => {
    const state = proStateFromSubscription(
      { subscriptionState: "SUBSCRIPTION_STATE_ACTIVE" },
      NOW,
    );
    assert.equal(state.isPro, false);
  });
});

describe("proExpiryMsOf", () => {
  it("prende la scadenza più lontana fra le voci Pro", () => {
    const ms = proExpiryMsOf(
      purchase("SUBSCRIPTION_STATE_ACTIVE", [
        { productId: "deck_master_pro_monthly", expiryTime: PAST },
        { productId: "deck_master_pro_annual", expiryTime: FUTURE },
      ]),
    );
    assert.equal(ms, Date.parse(FUTURE));
  });

  it("ignora le voci di prodotti che non sono nostri", () => {
    const ms = proExpiryMsOf(
      purchase("SUBSCRIPTION_STATE_ACTIVE", [
        { productId: "altro", expiryTime: "2099-01-01T00:00:00.000Z" },
        { productId: "deck_master_pro_monthly", expiryTime: FUTURE },
      ]),
    );
    assert.equal(ms, Date.parse(FUTURE));
  });

  it("ignora le date illeggibili invece di produrre NaN", () => {
    const ms = proExpiryMsOf({
      lineItems: [{ productId: "deck_master_pro_annual", expiryTime: "domani" }],
    });
    assert.equal(ms, null);
  });
});

describe("concernsPro", () => {
  it("riconosce i tre prodotti Pro", () => {
    for (const productId of [
      "deck_master_pro_monthly",
      "deck_master_pro_semiannual",
      "deck_master_pro_annual",
    ]) {
      assert.equal(concernsPro({ lineItems: [{ productId }] }), true, productId);
    }
  });

  it("dice di no su un prodotto estraneo", () => {
    assert.equal(concernsPro({ lineItems: [{ productId: "altro" }] }), false);
  });
});

describe("decodeDeveloperNotification", () => {
  it("decodifica il payload base64 di Pub/Sub", () => {
    const payload: DeveloperNotification = {
      version: "1.0",
      packageName: "com.giuseppe.deckmaster",
      eventTimeMillis: "1756555555000",
      subscriptionNotification: {
        notificationType: 2,
        purchaseToken: "token-abc",
        subscriptionId: "deck_master_pro_annual",
      },
    };
    const encoded = Buffer.from(JSON.stringify(payload)).toString("base64");
    assert.deepEqual(decodeDeveloperNotification(encoded), payload);
  });

  it("ritorna null su base64 che non è JSON, invece di lanciare", () => {
    const junk = Buffer.from("non sono json").toString("base64");
    assert.equal(decodeDeveloperNotification(junk), null);
  });

  it("ritorna null su input mancante", () => {
    assert.equal(decodeDeveloperNotification(undefined), null);
  });
});

describe("actionForNotification", () => {
  const PKG = "com.giuseppe.deckmaster";

  it("chiede di rileggere lo stato su una notifica di abbonamento", () => {
    const action = actionForNotification(
      {
        packageName: PKG,
        eventTimeMillis: "1756555555000",
        subscriptionNotification: {
          notificationType: 2,
          purchaseToken: "token-abc",
        },
      },
      PKG,
    );
    assert.deepEqual(action, {
      kind: "refresh",
      purchaseToken: "token-abc",
      eventAtMs: 1756555555000,
    });
  });

  it("revoca subito su un rimborso, senza rileggere", () => {
    const action = actionForNotification(
      {
        packageName: PKG,
        eventTimeMillis: "1756555555000",
        voidedPurchaseNotification: {
          purchaseToken: "token-abc",
          productType: 1,
          refundType: 1,
        },
      },
      PKG,
    );
    assert.equal(action.kind, "revoke");
  });

  it("ignora le notifiche di prova del Play Console", () => {
    const action = actionForNotification(
      { packageName: PKG, testNotification: { version: "1.0" } },
      PKG,
    );
    assert.deepEqual(action, { kind: "ignore", reason: "test" });
  });

  it("ignora le notifiche di un'altra app sullo stesso topic", () => {
    const action = actionForNotification(
      {
        packageName: "com.altro.app",
        subscriptionNotification: {
          notificationType: 2,
          purchaseToken: "token-abc",
        },
      },
      PKG,
    );
    assert.deepEqual(action, { kind: "ignore", reason: "package" });
  });

  it("ripiega su adesso se eventTimeMillis è illeggibile", () => {
    const action = actionForNotification(
      {
        packageName: PKG,
        eventTimeMillis: "non-un-numero",
        subscriptionNotification: {
          notificationType: 2,
          purchaseToken: "token-abc",
        },
      },
      PKG,
    );
    assert.equal(action.kind, "refresh");
    if (action.kind === "refresh") {
      assert.ok(Number.isFinite(action.eventAtMs));
    }
  });
});
