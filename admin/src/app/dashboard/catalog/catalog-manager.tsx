"use client";

import { useState } from "react";
import type { CatalogStatus } from "@/lib/data/catalog";

type SetCount = { set: string; count: number };

function fmt(s: string | null) {
  if (!s) return "—";
  const d = new Date(s);
  return isNaN(d.getTime()) ? s : d.toLocaleString("it-IT");
}

export default function CatalogManager({ statuses }: { statuses: CatalogStatus[] }) {
  const [open, setOpen] = useState<string | null>(null);
  const [data, setData] = useState<Record<string, { total: number; sets: SetCount[] }>>({});
  const [loading, setLoading] = useState<string | null>(null);

  async function toggle(catalog: string) {
    if (open === catalog) {
      setOpen(null);
      return;
    }
    setOpen(catalog);
    if (!data[catalog]) {
      setLoading(catalog);
      const res = await fetch(`/api/catalog/sets?catalog=${encodeURIComponent(catalog)}`);
      const d = await res.json();
      if (res.ok) setData((m) => ({ ...m, [catalog]: d }));
      setLoading(null);
    }
  }

  const active = statuses.filter((s) => s.totalCards > 0);

  return (
    <div className="space-y-2">
      {active.map((s) => {
        const isOpen = open === s.catalog;
        const bd = data[s.catalog];
        const maxCount = bd ? Math.max(1, ...bd.sets.map((x) => x.count)) : 1;
        return (
          <div key={s.catalog} className="panel overflow-hidden">
            <button
              onClick={() => toggle(s.catalog)}
              className="flex w-full items-center gap-4 px-4 py-3 text-left transition hover:bg-panel-2"
            >
              <svg
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                className={`shrink-0 text-ink-3 transition ${isOpen ? "rotate-90" : ""}`}
              >
                <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <span className="w-40 shrink-0 font-medium text-ink">{s.catalog}</span>
              <span className="num w-24 shrink-0 text-sm text-ink-2">
                {s.totalCards.toLocaleString("it-IT")} carte
              </span>
              <span className="hidden flex-1 truncate text-xs text-ink-3 sm:block">
                v{s.version ?? "—"} · {fmt(s.lastUpdated)} · {s.source}
              </span>
              <span className="chip bg-accent-soft text-accent-2">
                {isOpen ? "chiudi" : "vedi set"}
              </span>
            </button>

            {isOpen && (
              <div className="border-t border-line px-4 py-3">
                {loading === s.catalog && (
                  <p className="text-sm text-ink-3">Conteggio carte per set…</p>
                )}
                {bd && (
                  <div>
                    <p className="mb-2 text-xs text-ink-3">
                      {bd.sets.length} set · {bd.total.toLocaleString("it-IT")} carte totali
                    </p>
                    <div className="max-h-80 space-y-1 overflow-y-auto pr-1">
                      {bd.sets.map((x) => (
                        <div key={x.set} className="flex items-center gap-3 text-xs">
                          <span className="w-48 shrink-0 truncate text-ink-2" title={x.set}>
                            {x.set}
                          </span>
                          <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-panel-2">
                            <span
                              className="block h-full rounded-full bg-accent/70"
                              style={{ width: `${(x.count / maxCount) * 100}%` }}
                            />
                          </span>
                          <span className="num w-12 shrink-0 text-right text-ink-3">
                            {x.count}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
