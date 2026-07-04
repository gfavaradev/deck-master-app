import { NextResponse } from "next/server";
import { adminDb } from "@/lib/firebase/admin";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Check = { ok: boolean; detail?: string };

// Health check backend: verifica raggiungibilità/configurazione delle integrazioni
// che la dashboard userà (Firestore, CardTrader, Backblaze). Serve alla pagina
// Panoramica per capire a colpo d'occhio se tutto è collegato.
export async function GET() {
  const checks: Record<string, Check> = {};

  // Firestore (via Admin SDK → nessun App Check)
  try {
    await adminDb().collection("app_config").limit(1).get();
    checks.firestore = { ok: true };
  } catch (e) {
    checks.firestore = {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }

  // CardTrader — per ora solo presenza del JWT (chiamata reale in milestone prezzi)
  checks.cardtrader = process.env.CARDTRADER_JWT
    ? { ok: true, detail: "JWT presente" }
    : { ok: false, detail: "CARDTRADER_JWT mancante" };

  // Backblaze B2 — presenza credenziali
  const b2ok = !!(process.env.B2_KEY_ID && process.env.B2_APP_KEY);
  checks.backblaze = b2ok
    ? { ok: true, detail: "credenziali presenti" }
    : { ok: false, detail: "credenziali B2 mancanti (B2_KEY_ID/B2_APP_KEY)" };

  const ok = Object.values(checks).every((c) => c.ok);
  return NextResponse.json({ ok, checks }, { status: ok ? 200 : 503 });
}
