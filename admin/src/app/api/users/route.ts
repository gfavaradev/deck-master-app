import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/guard";
import { listUsers } from "@/lib/data/users";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const admin = await requireAdmin();
  if (admin instanceof NextResponse) return admin;

  const users = await listUsers();
  return NextResponse.json({ users });
}
