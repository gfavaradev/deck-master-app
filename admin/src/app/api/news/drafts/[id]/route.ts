import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { approveDraft, rejectDraft } from "@/lib/data/news";

export const runtime = "nodejs";

// POST = approva draft (pubblica), DELETE = rifiuta (elimina)
export async function POST(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const { id } = await params;
  await approveDraft(id);
  return NextResponse.json({ ok: true });
}

export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const { id } = await params;
  await rejectDraft(id);
  return NextResponse.json({ ok: true });
}
