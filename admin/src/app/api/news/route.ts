import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { listNews, listDrafts, createNews } from "@/lib/data/news";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const [published, drafts] = await Promise.all([listNews(), listDrafts()]);
  return NextResponse.json({ published, drafts });
}

export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const body = await req.json().catch(() => null);
  if (!body?.title || !Array.isArray(body?.collections) || body.collections.length === 0) {
    return NextResponse.json({ error: "title-and-collections-required" }, { status: 400 });
  }
  await createNews(body);
  return NextResponse.json({ ok: true });
}
