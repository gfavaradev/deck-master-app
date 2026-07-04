import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { searchCards, updateCardScalars, deleteCard } from "@/lib/data/cards";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

// GET /api/cards?catalog=yugioh&q=dark  → cerca carte
export async function GET(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const catalog = req.nextUrl.searchParams.get("catalog") ?? "";
  const q = req.nextUrl.searchParams.get("q") ?? "";
  if (!catalog) return NextResponse.json({ error: "catalog-required" }, { status: 400 });
  if (q.trim().length < 2) return NextResponse.json({ hits: [] });
  const hits = await searchCards(catalog, q);
  return NextResponse.json({ hits });
}

// PATCH /api/cards  body { catalog, chunkId, cardId, patch }
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const { catalog, chunkId, cardId, patch } = await req.json().catch(() => ({}));
  if (!catalog || !chunkId || !cardId || typeof patch !== "object") {
    return NextResponse.json({ error: "invalid-body" }, { status: 400 });
  }
  try {
    await updateCardScalars(catalog, chunkId, cardId, patch);
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}

// DELETE /api/cards  body { catalog, chunkId, cardId }
export async function DELETE(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const { catalog, chunkId, cardId } = await req.json().catch(() => ({}));
  if (!catalog || !chunkId || !cardId) {
    return NextResponse.json({ error: "invalid-body" }, { status: 400 });
  }
  try {
    await deleteCard(catalog, chunkId, cardId);
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
