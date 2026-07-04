"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminUserRow } from "@/lib/data/users";

function fmtDate(s?: string) {
  if (!s) return "—";
  const d = new Date(s);
  return isNaN(d.getTime()) ? s : d.toLocaleDateString("it-IT");
}

export default function UsersTable({ users }: { users: AdminUserRow[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [query, setQuery] = useState("");

  async function patch(uid: string, action: string, value: unknown) {
    setBusy(uid + action);
    try {
      const res = await fetch(`/api/users/${uid}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, value }),
      });
      if (res.ok) router.refresh();
    } finally {
      setBusy(null);
    }
  }

  const filtered = users.filter(
    (u) =>
      !query ||
      u.email.toLowerCase().includes(query.toLowerCase()) ||
      (u.displayName ?? "").toLowerCase().includes(query.toLowerCase()),
  );

  return (
    <div>
      <input
        placeholder={`Cerca tra ${users.length} utenti…`}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="mb-4 w-full max-w-sm rounded-lg border border-line-strong bg-app px-3 py-2 text-sm outline-none focus:border-accent"
      />
      <div className="overflow-x-auto rounded-xl border border-line">
        <table className="w-full text-sm">
          <thead className="bg-panel text-left text-ink-2">
            <tr>
              <th className="px-4 py-2 font-medium">Utente</th>
              <th className="px-4 py-2 font-medium">Ruolo</th>
              <th className="px-4 py-2 font-medium">Pro</th>
              <th className="px-4 py-2 font-medium">Attivo</th>
              <th className="px-4 py-2 font-medium">Ultimo accesso</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((u) => (
              <tr key={u.uid} className="border-t border-line">
                <td className="px-4 py-2">
                  <div className="text-ink">{u.displayName ?? "—"}</div>
                  <div className="text-xs text-ink-3">{u.email}</div>
                </td>
                <td className="px-4 py-2">
                  <button
                    disabled={busy === u.uid + "role"}
                    onClick={() =>
                      patch(
                        u.uid,
                        "role",
                        u.role === "administrator" ? "user" : "administrator",
                      )
                    }
                    className={`rounded px-2 py-1 text-xs ${
                      u.role === "administrator"
                        ? "bg-accent/15 text-accent"
                        : "bg-panel-2 text-ink-2"
                    }`}
                  >
                    {u.role === "administrator" ? "admin" : "user"}
                  </button>
                </td>
                <td className="px-4 py-2">
                  <button
                    disabled={busy === u.uid + "pro"}
                    onClick={() => patch(u.uid, "pro", !u.isPro)}
                    className={`rounded px-2 py-1 text-xs ${
                      u.isPro
                        ? "bg-ok/15 text-ok"
                        : "bg-panel-2 text-ink-2"
                    }`}
                  >
                    {u.isPro ? `Pro${u.proSource ? ` (${u.proSource})` : ""}` : "no"}
                  </button>
                </td>
                <td className="px-4 py-2">
                  <button
                    disabled={busy === u.uid + "active"}
                    onClick={() => patch(u.uid, "active", !u.isActive)}
                    className={`rounded px-2 py-1 text-xs ${
                      u.isActive
                        ? "bg-ok/15 text-ok"
                        : "bg-bad/15 text-bad"
                    }`}
                  >
                    {u.isActive ? "attivo" : "disattivo"}
                  </button>
                </td>
                <td className="px-4 py-2 text-ink-3">{fmtDate(u.lastLoginAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
