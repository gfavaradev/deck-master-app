import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { applyImport } from "@/lib/data/excel";

export const runtime = "nodejs";
export const maxDuration = 120;

// POST JSON { catalog, patches: [{ id, chunkId, patch }] } → applica le modifiche
export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;

  const { catalog, patches } = await req.json().catch(() => ({}));
  if (!catalog || !Array.isArray(patches)) {
    return NextResponse.json({ error: "invalid-body" }, { status: 400 });
  }
  try {
    const applied = await applyImport(catalog, patches);
    return NextResponse.json({ ok: true, applied });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
