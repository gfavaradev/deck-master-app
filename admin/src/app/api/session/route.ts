import { NextRequest, NextResponse } from "next/server";
import { adminAuth } from "@/lib/firebase/admin";
import { isAdminEmail, SESSION_COOKIE } from "@/lib/config";

export const runtime = "nodejs";

const EXPIRES_IN_MS = 60 * 60 * 24 * 5 * 1000; // 5 giorni

// POST: il client invia l'ID token Firebase dopo il login. Il server lo verifica,
// controlla che l'email sia in allowlist e crea un session cookie HttpOnly.
export async function POST(req: NextRequest) {
  const { idToken } = await req.json().catch(() => ({ idToken: undefined }));
  if (!idToken) {
    return NextResponse.json({ error: "missing-id-token" }, { status: 400 });
  }

  try {
    const decoded = await adminAuth().verifyIdToken(idToken);
    if (!isAdminEmail(decoded.email)) {
      return NextResponse.json({ error: "not-admin" }, { status: 403 });
    }

    const sessionCookie = await adminAuth().createSessionCookie(idToken, {
      expiresIn: EXPIRES_IN_MS,
    });

    const res = NextResponse.json({ ok: true });
    res.cookies.set(SESSION_COOKIE, sessionCookie, {
      maxAge: EXPIRES_IN_MS / 1000,
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
    });
    return res;
  } catch {
    return NextResponse.json({ error: "invalid-token" }, { status: 401 });
  }
}

// DELETE: logout — cancella il session cookie.
export async function DELETE() {
  const res = NextResponse.json({ ok: true });
  res.cookies.delete(SESSION_COOKIE);
  return res;
}
