import "server-only";

import { adminDb } from "@/lib/firebase/admin";

export type AdminUserRow = {
  uid: string;
  email: string;
  displayName?: string;
  photoUrl?: string;
  role: string;
  isActive: boolean;
  isPro: boolean;
  proSource?: string | null;
  createdAt?: string;
  lastLoginAt?: string;
};

export async function listUsers(max = 1000): Promise<AdminUserRow[]> {
  const snap = await adminDb().collection("users").limit(max).get();
  const rows = snap.docs.map((d) => {
    const x = d.data();
    return {
      uid: d.id,
      email: (x.email as string) ?? "",
      displayName: x.displayName as string | undefined,
      photoUrl: x.photoUrl as string | undefined,
      role: (x.role as string) ?? "user",
      isActive: (x.isActive as boolean) ?? true,
      isPro: (x.isPro as boolean) ?? false,
      proSource: (x.proSource as string | null) ?? null,
      createdAt: x.createdAt as string | undefined,
      lastLoginAt: x.lastLoginAt as string | undefined,
    } satisfies AdminUserRow;
  });
  // Più recenti per ultimo accesso in cima.
  rows.sort((a, b) => (b.lastLoginAt ?? "").localeCompare(a.lastLoginAt ?? ""));
  return rows;
}

// Attiva/disattiva Pro manuale — stessi campi di SubscriptionService nell'app.
export async function setUserPro(uid: string, isPro: boolean): Promise<void> {
  await adminDb()
    .collection("users")
    .doc(uid)
    .set(
      isPro
        ? { isPro: true, proSource: "manual", proExpiresAt: null }
        : { isPro: false, proSource: null, proExpiresAt: null },
      { merge: true },
    );
}

export async function setUserActive(uid: string, isActive: boolean): Promise<void> {
  await adminDb().collection("users").doc(uid).set({ isActive }, { merge: true });
}

export async function setUserRole(
  uid: string,
  role: "administrator" | "user",
): Promise<void> {
  await adminDb().collection("users").doc(uid).set({ role }, { merge: true });
}
