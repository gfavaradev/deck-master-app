import "server-only";

import { cookies } from "next/headers";
import { adminAuth } from "@/lib/firebase/admin";
import { isAdminEmail, SESSION_COOKIE } from "@/lib/config";

export type AdminUser = {
  uid: string;
  email: string;
  name?: string;
  picture?: string;
};

// Legge il session cookie, lo verifica col Admin SDK e controlla l'allowlist.
// Ritorna null se: cookie assente, cookie non valido/revocato, o email non admin.
// Usato dai server component protetti (dashboard/layout.tsx).
export async function getCurrentAdmin(): Promise<AdminUser | null> {
  const cookie = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!cookie) return null;

  try {
    // checkRevoked = true → invalida sessioni dopo logout/disabilitazione account.
    const decoded = await adminAuth().verifySessionCookie(cookie, true);
    if (!isAdminEmail(decoded.email)) return null;
    return {
      uid: decoded.uid,
      email: decoded.email!,
      name: decoded.name as string | undefined,
      picture: decoded.picture as string | undefined,
    };
  } catch {
    return null;
  }
}
