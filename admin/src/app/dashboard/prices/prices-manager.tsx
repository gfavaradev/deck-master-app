"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { PriceStatus } from "@/lib/data/jobs";

const EMBED = new Set(["yugioh", "pokemon", "onepiece"]);

function fmt(s: string | null) {
  if (!s) return "mai";
  const d = new Date(s);
  return isNaN(d.getTime()) ? s : d.toLocaleString("it-IT");
}

export default function PricesManager({ statuses }: { statuses: PriceStatus[] }) {
  const router = useRouter();
  const [running, setRunning] = useState<string | null>(null);
  const [msg, setMsg] = useState<Record<string, string>>({});

  async function sync(catalog: string) {
    setRunning(catalog);
    setMsg((m) => ({ ...m, [catalog]: "sync in corso… (può richiedere minuti)" }));
    try {
      const res = await fetch("/api/jobs/price-sync", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ catalog }),
      });
      const data = await res.json();
      setMsg((m) => ({
        ...m,
        [catalog]: res.ok ? `✓ ${data.result?.message ?? "fatto"}` : `✗ ${data.error ?? "errore"}`,
      }));
      router.refresh();
    } catch (e) {
      setMsg((m) => ({ ...m, [catalog]: `✗ ${e instanceof Error ? e.message : "errore"}` }));
    } finally {
      setRunning(null);
    }
  }

  return (
    <div className="space-y-4">
      <p className="rounded-lg border border-accent/30 bg-accent/5 px-3 py-2 text-xs text-accent-2/80">
        I sync CardTrader sono lunghi. Su Vercel una singola esecuzione è limitata dal
        piano: i cataloghi grandi (Yu-Gi-Oh/Pokémon/One Piece, con embed nei chunk) è
        meglio eseguirli via cron dedicato. Qui puoi lanciarli manualmente per catalogo.
      </p>
      <div className="overflow-x-auto rounded-xl border border-line">
        <table className="w-full text-sm">
          <thead className="bg-panel text-left text-ink-2">
            <tr>
              <th className="px-4 py-2 font-medium">Catalogo</th>
              <th className="px-4 py-2 font-medium">Prezzi</th>
              <th className="px-4 py-2 font-medium">Ultimo sync</th>
              <th className="px-4 py-2 font-medium">Embed chunk</th>
              <th className="px-4 py-2 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {statuses.map((s) => (
              <tr key={s.catalog} className="border-t border-line">
                <td className="px-4 py-2 font-medium">{s.catalog}</td>
                <td className="px-4 py-2 text-ink-2">{s.count ?? "—"}</td>
                <td className="px-4 py-2 text-ink-3">{fmt(s.syncedAt)}</td>
                <td className="px-4 py-2 text-ink-3">
                  {EMBED.has(s.catalog) ? fmt(s.chunkPricesSyncedAt) : "—"}
                </td>
                <td className="px-4 py-2 text-right">
                  <button
                    disabled={running !== null}
                    onClick={() => sync(s.catalog)}
                    className="rounded bg-panel-2 px-2 py-1 text-xs text-ink hover:bg-elevated disabled:opacity-40"
                  >
                    {running === s.catalog ? "…" : "Sync"}
                  </button>
                  {msg[s.catalog] && (
                    <div className="mt-1 text-xs text-ink-3">{msg[s.catalog]}</div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
