"use client";

import { useState } from "react";
import type { CatalogInfo } from "@/lib/data/cards";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Hit = {
  chunkId: string;
  cardId: string;
  name: string;
  imageUrl: string | null;
  card: any;
};

function isScalar(v: unknown) {
  return v === null || ["string", "number", "boolean"].includes(typeof v);
}

export default function CardsManager({ catalogs }: { catalogs: CatalogInfo[] }) {
  const [catalog, setCatalog] = useState(catalogs[0]?.catalog ?? "");
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<Hit[]>([]);
  const [loading, setLoading] = useState(false);
  const [editing, setEditing] = useState<Hit | null>(null);
  const [form, setForm] = useState<Record<string, any>>({});
  const [busy, setBusy] = useState(false);

  async function search() {
    if (q.trim().length < 2) return;
    setLoading(true);
    const res = await fetch(
      `/api/cards?catalog=${encodeURIComponent(catalog)}&q=${encodeURIComponent(q)}`,
    );
    const data = await res.json();
    setHits(data.hits ?? []);
    setLoading(false);
  }

  function openEdit(hit: Hit) {
    setEditing(hit);
    const scalars: Record<string, any> = {};
    for (const [k, v] of Object.entries(hit.card)) if (isScalar(v)) scalars[k] = v;
    setForm(scalars);
  }

  async function save() {
    if (!editing) return;
    setBusy(true);
    // Solo i campi cambiati.
    const patch: Record<string, any> = {};
    for (const [k, v] of Object.entries(form)) {
      if (v !== editing.card[k]) patch[k] = v;
    }
    if (Object.keys(patch).length === 0) {
      setBusy(false);
      setEditing(null);
      return;
    }
    const res = await fetch("/api/cards", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        catalog,
        chunkId: editing.chunkId,
        cardId: editing.cardId,
        patch,
      }),
    });
    setBusy(false);
    if (res.ok) {
      setEditing(null);
      search();
    } else {
      alert("Salvataggio non riuscito.");
    }
  }

  async function del(hit: Hit) {
    if (!confirm(`Eliminare "${hit.name}" dal catalogo ${catalog}?`)) return;
    setBusy(true);
    const res = await fetch("/api/cards", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ catalog, chunkId: hit.chunkId, cardId: hit.cardId }),
    });
    setBusy(false);
    if (res.ok) setHits((h) => h.filter((x) => x.cardId !== hit.cardId));
  }

  const nested = editing
    ? Object.entries(editing.card).filter(([, v]) => !isScalar(v))
    : [];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={catalog}
          onChange={(e) => {
            setCatalog(e.target.value);
            setHits([]);
          }}
          className="rounded-lg border border-line-strong bg-app px-3 py-2 text-sm"
        >
          {catalogs.map((c) => (
            <option key={c.catalog} value={c.catalog}>
              {c.catalog} ({c.totalCards})
            </option>
          ))}
        </select>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && search()}
          placeholder="Cerca per nome (min 2 caratteri)…"
          className="min-w-[220px] flex-1 rounded-lg border border-line-strong bg-app px-3 py-2 text-sm outline-none focus:border-accent"
        />
        <button
          onClick={search}
          disabled={loading}
          className="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-app hover:bg-accent-2 disabled:opacity-50"
        >
          {loading ? "…" : "Cerca"}
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {hits.map((h) => (
          <div
            key={h.chunkId + h.cardId}
            className="flex flex-col rounded-xl border border-line bg-panel p-3"
          >
            {h.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={h.imageUrl}
                alt={h.name}
                className="mb-2 h-40 w-full rounded object-contain"
              />
            ) : (
              <div className="mb-2 flex h-40 items-center justify-center rounded bg-panel-2 text-xs text-ink-3">
                nessuna immagine
              </div>
            )}
            <div className="truncate text-sm font-medium" title={h.name}>
              {h.name}
            </div>
            <div className="mb-2 truncate text-xs text-ink-3">
              {h.cardId} · {h.chunkId}
            </div>
            <div className="mt-auto flex gap-2">
              <button
                onClick={() => openEdit(h)}
                className="flex-1 rounded bg-panel-2 px-2 py-1 text-xs hover:bg-elevated"
              >
                Modifica
              </button>
              <button
                onClick={() => del(h)}
                disabled={busy}
                className="rounded bg-bad/15 px-2 py-1 text-xs text-bad hover:bg-bad/25"
              >
                Elimina
              </button>
            </div>
          </div>
        ))}
      </div>
      {!loading && hits.length === 0 && (
        <p className="text-sm text-ink-3">Nessun risultato. Cerca una carta.</p>
      )}

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-line bg-panel p-6">
            <h2 className="mb-1 text-lg font-semibold">Modifica carta</h2>
            <p className="mb-4 text-xs text-ink-3">
              {catalog} · {editing.cardId} · {editing.chunkId}
            </p>
            <div className="space-y-2">
              {Object.entries(form).map(([k, v]) => (
                <label key={k} className="block">
                  <span className="text-xs text-ink-2">{k}</span>
                  <input
                    value={v == null ? "" : String(v)}
                    onChange={(e) =>
                      setForm((f) => ({
                        ...f,
                        [k]:
                          typeof editing.card[k] === "number"
                            ? e.target.value === ""
                              ? null
                              : Number(e.target.value)
                            : e.target.value,
                      }))
                    }
                    className="w-full rounded-lg border border-line-strong bg-app px-3 py-1.5 text-sm outline-none focus:border-accent"
                  />
                </label>
              ))}
            </div>
            {nested.length > 0 && (
              <details className="mt-4">
                <summary className="cursor-pointer text-xs text-ink-3">
                  Campi strutturati (read-only): {nested.map(([k]) => k).join(", ")}
                </summary>
                <pre className="mt-2 max-h-48 overflow-auto rounded bg-app p-2 text-[10px] text-ink-2">
                  {JSON.stringify(Object.fromEntries(nested), null, 2)}
                </pre>
              </details>
            )}
            <div className="mt-5 flex justify-end gap-2">
              <button
                onClick={() => setEditing(null)}
                className="rounded-lg border border-line-strong px-3 py-1.5 text-sm text-ink-2"
              >
                Annulla
              </button>
              <button
                onClick={save}
                disabled={busy}
                className="rounded-lg bg-accent px-3 py-1.5 text-sm font-semibold text-app hover:bg-accent-2 disabled:opacity-50"
              >
                Salva
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
