import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { runPriceSyncForCatalog } from "@/lib/jobs/price-sync";
import { PRICE_CATALOGS } from "@/lib/data/jobs";

export const runtime = "nodejs";
// I sync possono durare a lungo: chiediamo il massimo consentito dal piano.
// Vercel applica il cap del piano (es. 60s Hobby, fino a 300s+ con Fluid/Pro).
export const maxDuration = 300;

// POST { catalog }  → esegue il price sync di UN catalogo.
export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;

  const { catalog } = await req.json().catch(() => ({}));
  if (!catalog || !PRICE_CATALOGS.includes(catalog)) {
    return NextResponse.json({ error: "invalid-catalog" }, { status: 400 });
  }

  try {
    const result = await runPriceSyncForCatalog(catalog);
    return NextResponse.json({ ok: true, result });
  } catch (e) {
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
