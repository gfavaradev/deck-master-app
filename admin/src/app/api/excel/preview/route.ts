import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { previewImport } from "@/lib/data/excel";

export const runtime = "nodejs";
export const maxDuration = 120;

// POST multipart: file (.xlsx) + catalog → anteprima delle modifiche
export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;

  const form = await req.formData().catch(() => null);
  const catalog = form?.get("catalog");
  const file = form?.get("file");
  if (typeof catalog !== "string" || !(file instanceof Blob)) {
    return NextResponse.json({ error: "file-and-catalog-required" }, { status: 400 });
  }

  try {
    const buffer = Buffer.from(await file.arrayBuffer());
    const preview = await previewImport(catalog, buffer);
    return NextResponse.json(preview);
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
