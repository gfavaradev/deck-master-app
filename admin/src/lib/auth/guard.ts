import "server-only";

import { NextResponse } from "next/server";
import { getCurrentAdmin, type AdminUser } from "@/lib/auth/session";

// Guardia per le route API: ritorna l'admin autenticato, oppure una risposta 401
// da restituire subito. Uso:
//   const admin = await requireAdmin();
//   if (admin instanceof NextResponse) return admin;
export async function requireAdmin(): Promise<AdminUser | NextResponse> {
  const admin = await getCurrentAdmin();
  if (!admin) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  return admin;
}
