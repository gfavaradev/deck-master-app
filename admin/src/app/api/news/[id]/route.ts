import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { updateNews, deleteNews, setPinned } from "@/lib/data/news";

export const runtime = "nodejs";

export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const { id } = await params;
  const body = await req.json().catch(() => ({}));

  // Toggle rapido del pin: { pin: boolean }
  if (typeof body.pin === "boolean") {
    await setPinned(id, body.pin);
    return NextResponse.json({ ok: true });
  }
  // Update completo
  if (!body?.title || !Array.isArray(body?.collections) || body.collections.length === 0) {
    return NextResponse.json({ error: "title-and-collections-required" }, { status: 400 });
  }
  await updateNews(id, body);
  return NextResponse.json({ ok: true });
}

export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const { id } = await params;
  await deleteNews(id);
  return NextResponse.json({ ok: true });
}
