import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { getSetBreakdown } from "@/lib/data/sets";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

// GET /api/catalog/sets?catalog=yugioh → { total, sets: [{set, count}] }
export async function GET(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const catalog = req.nextUrl.searchParams.get("catalog") ?? "";
  if (!catalog) return NextResponse.json({ error: "catalog-required" }, { status: 400 });
  const breakdown = await getSetBreakdown(catalog);
  return NextResponse.json(breakdown);
}
