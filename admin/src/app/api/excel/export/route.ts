import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { exportCatalogXlsx } from "@/lib/data/excel";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

// GET /api/excel/export?catalog=yugioh → scarica il file .xlsx
export async function GET(req: NextRequest) {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;
  const catalog = req.nextUrl.searchParams.get("catalog") ?? "";
  if (!catalog) return NextResponse.json({ error: "catalog-required" }, { status: 400 });

  try {
    const buffer = await exportCatalogXlsx(catalog);
    return new NextResponse(new Uint8Array(buffer), {
      headers: {
        "Content-Type":
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="${catalog}_carte.xlsx"`,
      },
    });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
