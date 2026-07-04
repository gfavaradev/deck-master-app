"use client";

import { useState } from "react";
import type { CatalogInfo } from "@/lib/data/cards";

/* eslint-disable @typescript-eslint/no-explicit-any */

type CardChange = {
  id: string;
  name: string;
  chunkId: string;
  changes: Record<string, { from: any; to: any }>;
};

export default function ExcelManager({ catalogs }: { catalogs: CatalogInfo[] }) {
  const [catalog, setCatalog] = useState(catalogs[0]?.catalog ?? "");
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<{
    changes: CardChange[];
    unmatched: number;
    totalRows: number;
  } | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  function exportXlsx() {
    window.open(`/api/excel/export?catalog=${encodeURIComponent(catalog)}`, "_blank");
  }

  async function doPreview() {
    if (!file) return;
    setBusy(true);
    setMsg(null);
    setPreview(null);
    const fd = new FormData();
    fd.append("catalog", catalog);
    fd.append("file", file);
    const res = await fetch("/api/excel/preview", { method: "POST", body: fd });
    const data = await res.json();
    setBusy(false);
    if (res.ok) setPreview(data);
    else setMsg(`Errore: ${data.error ?? "preview fallita"}`);
  }

  async function apply() {
    if (!preview) return;
    setBusy(true);
    const patches = preview.changes.map((c) => ({
      id: c.id,
      chunkId: c.chunkId,
      patch: Object.fromEntries(
        Object.entries(c.changes).map(([k, v]) => [k, v.to]),
      ),
    }));
    const res = await fetch("/api/excel/apply", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ catalog, patches }),
    });
    const data = await res.json();
    setBusy(false);
    if (res.ok) {
      setMsg(`✓ Applicate ${data.applied} modifiche.`);
      setPreview(null);
      setFile(null);
    } else {
      setMsg(`Errore: ${data.error ?? "apply fallita"}`);
    }
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={catalog}
          onChange={(e) => {
            setCatalog(e.target.value);
            setPreview(null);
          }}
          className="rounded-lg border border-line-strong bg-app px-3 py-2 text-sm"
        >
          {catalogs.map((c) => (
            <option key={c.catalog} value={c.catalog}>
              {c.catalog} ({c.totalCards})
            </option>
          ))}
        </select>
        <button
          onClick={exportXlsx}
          className="rounded-lg bg-ok px-4 py-2 text-sm font-semibold text-white hover:bg-ok"
        >
          ⬇ Esporta XLSX
        </button>
      </div>

      <div className="rounded-xl border border-line bg-panel p-4">
        <h2 className="mb-2 text-sm font-semibold text-ink-2">Importa</h2>
        <p className="mb-3 text-xs text-ink-3">
          Carica un .xlsx (stesso formato dell&apos;export). Le modifiche vengono
          confrontate carta per carta (match su <code>id</code>/<code>api_id</code>);
          solo i campi scalari cambiati verranno aggiornati.
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <input
            type="file"
            accept=".xlsx,.xls"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            className="text-sm text-ink-2 file:mr-3 file:rounded file:border-0 file:bg-panel-2 file:px-3 file:py-1.5 file:text-ink"
          />
          <button
            onClick={doPreview}
            disabled={!file || busy}
            className="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-app hover:bg-accent-2 disabled:opacity-50"
          >
            {busy ? "…" : "Anteprima"}
          </button>
        </div>
      </div>

      {msg && (
        <p className="rounded-lg bg-panel-2 px-3 py-2 text-sm text-ink">{msg}</p>
      )}

      {preview && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-ink-2">
              {preview.changes.length} carte con modifiche · {preview.unmatched} righe senza
              corrispondenza · {preview.totalRows} righe totali
            </p>
            {preview.changes.length > 0 && (
              <button
                onClick={apply}
                disabled={busy}
                className="rounded-lg bg-ok px-4 py-2 text-sm font-semibold text-white hover:bg-ok disabled:opacity-50"
              >
                Applica {preview.changes.length} modifiche
              </button>
            )}
          </div>
          <div className="max-h-[50vh] overflow-auto rounded-xl border border-line">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-panel text-left text-ink-2">
                <tr>
                  <th className="px-4 py-2 font-medium">Carta</th>
                  <th className="px-4 py-2 font-medium">Modifiche</th>
                </tr>
              </thead>
              <tbody>
                {preview.changes.slice(0, 500).map((c) => (
                  <tr key={c.id} className="border-t border-line align-top">
                    <td className="px-4 py-2">
                      <div className="font-medium">{c.name}</div>
                      <div className="text-xs text-ink-3">{c.id}</div>
                    </td>
                    <td className="px-4 py-2">
                      {Object.entries(c.changes).map(([field, v]) => (
                        <div key={field} className="text-xs">
                          <span className="text-ink-2">{field}:</span>{" "}
                          <span className="text-bad line-through">
                            {String(v.from ?? "∅")}
                          </span>{" "}
                          →{" "}
                          <span className="text-ok">{String(v.to ?? "∅")}</span>
                        </div>
                      ))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
