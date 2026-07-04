"use client";

import { useRouter } from "next/navigation";
import { signOut } from "firebase/auth";
import { auth } from "@/lib/firebase/client";

export default function LogoutButton() {
  const router = useRouter();

  async function handleLogout() {
    await fetch("/api/session", { method: "DELETE" });
    try {
      await signOut(auth);
    } catch {
      // sessione server già invalidata
    }
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      onClick={handleLogout}
      className="rounded-lg border border-line px-3 py-1.5 text-xs text-ink-2 transition hover:border-line-strong hover:text-ink"
    >
      Esci
    </button>
  );
}
