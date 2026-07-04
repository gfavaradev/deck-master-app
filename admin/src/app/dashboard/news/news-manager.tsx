"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { TCG_COLLECTIONS } from "@/lib/collections";
import type { NewsItem } from "@/lib/data/news";

type Draft = {
  title: string;
  subtitle: string;
  body: string;
  imageUrl: string;
  externalUrl: string;
  collections: string[];
  pinned: boolean;
  publishedAt: string; // yyyy-mm-dd
};

function emptyDraft(): Draft {
  return {
    title: "",
    subtitle: "",
    body: "",
    imageUrl: "",
    externalUrl: "",
    collections: [],
    pinned: false,
    publishedAt: new Date().toISOString().slice(0, 10),
  };
}

function itemToDraft(n: NewsItem): Draft {
  return {
    title: n.title,
    subtitle: n.subtitle ?? "",
    body: n.body ?? "",
    imageUrl: n.imageUrl ?? "",
    externalUrl: n.externalUrl ?? "",
    collections: n.collections ?? [],
    pinned: n.pinned,
    publishedAt: (n.publishedAt ?? new Date().toISOString()).slice(0, 10),
  };
}

export default function NewsManager({
  published,
  drafts,
}: {
  published: NewsItem[];
  drafts: NewsItem[];
}) {
  const router = useRouter();
  const [tab, setTab] = useState<"published" | "drafts">("published");
  const [editing, setEditing] = useState<{ id: string | null; draft: Draft } | null>(
    null,
  );
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!editing) return;
    if (!editing.draft.title.trim() || editing.draft.collections.length === 0) {
      alert("Titolo e almeno una collezione sono obbligatori.");
      return;
    }
    setBusy(true);
    const payload = {
      ...editing.draft,
      publishedAt: new Date(editing.draft.publishedAt).toISOString(),
    };
    const res = await fetch(
      editing.id ? `/api/news/${editing.id}` : "/api/news",
      {
        method: editing.id ? "PATCH" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      },
    );
    setBusy(false);
    if (res.ok) {
      setEditing(null);
      router.refresh();
    } else {
      alert("Salvataggio non riuscito.");
    }
  }

  async function act(url: string, method: string) {
    setBusy(true);
    await fetch(url, { method });
    setBusy(false);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex gap-2">
          <button
            onClick={() => setTab("published")}
            className={`rounded-lg px-3 py-1.5 text-sm ${tab === "published" ? "bg-accent/15 text-accent" : "text-ink-2 hover:bg-panel-2"}`}
          >
            Pubblicate ({published.length})
          </button>
          <button
            onClick={() => setTab("drafts")}
            className={`rounded-lg px-3 py-1.5 text-sm ${tab === "drafts" ? "bg-accent/15 text-accent" : "text-ink-2 hover:bg-panel-2"}`}
          >
            In revisione ({drafts.length})
          </button>
        </div>
        <button
          onClick={() => setEditing({ id: null, draft: emptyDraft() })}
          className="rounded-lg bg-accent px-3 py-1.5 text-sm font-semibold text-app hover:bg-accent-2"
        >
          + Nuova news
        </button>
      </div>

      {tab === "published" && (
        <ul className="space-y-2">
          {published.map((n) => (
            <li
              key={n.id}
              className="flex items-center justify-between gap-3 rounded-xl border border-line bg-panel px-4 py-3"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  {n.pinned && <span className="text-accent">📌</span>}
                  <span className="truncate font-medium">{n.title}</span>
                </div>
                <div className="truncate text-xs text-ink-3">
                  {n.collections.join(", ")} ·{" "}
                  {n.publishedAt ? new Date(n.publishedAt).toLocaleDateString("it-IT") : "—"}
                </div>
              </div>
              <div className="flex shrink-0 gap-2 text-xs">
                <button
                  disabled={busy}
                  onClick={async () => {
                    setBusy(true);
                    await fetch(`/api/news/${n.id}`, {
                      method: "PATCH",
                      headers: { "Content-Type": "application/json" },
                      body: JSON.stringify({ pin: !n.pinned }),
                    });
                    setBusy(false);
                    router.refresh();
                  }}
                  className="rounded bg-panel-2 px-2 py-1 text-ink-2 hover:bg-elevated"
                >
                  {n.pinned ? "Rimuovi pin" : "Pin"}
                </button>
                <button
                  disabled={busy}
                  onClick={() => setEditing({ id: n.id, draft: itemToDraft(n) })}
                  className="rounded bg-panel-2 px-2 py-1 text-ink-2 hover:bg-elevated"
                >
                  Modifica
                </button>
                <button
                  disabled={busy}
                  onClick={() => {
                    if (confirm("Eliminare questa news?")) act(`/api/news/${n.id}`, "DELETE");
                  }}
                  className="rounded bg-bad/15 px-2 py-1 text-bad hover:bg-bad/25"
                >
                  Elimina
                </button>
              </div>
            </li>
          ))}
          {published.length === 0 && (
            <p className="text-sm text-ink-3">Nessuna news pubblicata.</p>
          )}
        </ul>
      )}

      {tab === "drafts" && (
        <ul className="space-y-2">
          {drafts.map((n) => (
            <li
              key={n.id}
              className="flex items-center justify-between gap-3 rounded-xl border border-line bg-panel px-4 py-3"
            >
              <div className="min-w-0">
                <div className="truncate font-medium">{n.title}</div>
                <div className="truncate text-xs text-ink-3">
                  {n.collections.join(", ")}
                  {n.externalUrl ? ` · ${n.externalUrl}` : ""}
                </div>
              </div>
              <div className="flex shrink-0 gap-2 text-xs">
                <button
                  disabled={busy}
                  onClick={() => act(`/api/news/drafts/${n.id}`, "POST")}
                  className="rounded bg-ok/15 px-2 py-1 text-ok hover:bg-ok/25"
                >
                  Approva
                </button>
                <button
                  disabled={busy}
                  onClick={() => act(`/api/news/drafts/${n.id}`, "DELETE")}
                  className="rounded bg-bad/15 px-2 py-1 text-bad hover:bg-bad/25"
                >
                  Rifiuta
                </button>
              </div>
            </li>
          ))}
          {drafts.length === 0 && (
            <p className="text-sm text-ink-3">Nessun draft in revisione.</p>
          )}
        </ul>
      )}

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-line bg-panel p-6">
            <h2 className="mb-4 text-lg font-semibold">
              {editing.id ? "Modifica news" : "Nuova news"}
            </h2>
            <div className="space-y-3">
              {(
                [
                  ["title", "Titolo"],
                  ["subtitle", "Sottotitolo (opzionale)"],
                  ["imageUrl", "URL immagine (opzionale)"],
                  ["externalUrl", "Link esterno (opzionale)"],
                ] as const
              ).map(([field, label]) => (
                <input
                  key={field}
                  placeholder={label}
                  value={editing.draft[field] as string}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      draft: { ...editing.draft, [field]: e.target.value },
                    })
                  }
                  className="w-full rounded-lg border border-line-strong bg-app px-3 py-2 text-sm outline-none focus:border-accent"
                />
              ))}
              <textarea
                placeholder="Testo"
                rows={4}
                value={editing.draft.body}
                onChange={(e) =>
                  setEditing({ ...editing, draft: { ...editing.draft, body: e.target.value } })
                }
                className="w-full rounded-lg border border-line-strong bg-app px-3 py-2 text-sm outline-none focus:border-accent"
              />
              <div>
                <p className="mb-1 text-xs text-ink-2">Collezioni</p>
                <div className="flex flex-wrap gap-1.5">
                  {TCG_COLLECTIONS.map((c) => {
                    const sel = editing.draft.collections.includes(c.key);
                    return (
                      <button
                        key={c.key}
                        onClick={() =>
                          setEditing({
                            ...editing,
                            draft: {
                              ...editing.draft,
                              collections: sel
                                ? editing.draft.collections.filter((k) => k !== c.key)
                                : [...editing.draft.collections, c.key],
                            },
                          })
                        }
                        className={`rounded-full px-2.5 py-1 text-xs ${sel ? "bg-accent/20 text-accent-2" : "bg-panel-2 text-ink-2"}`}
                      >
                        {c.name}
                      </button>
                    );
                  })}
                </div>
              </div>
              <div className="flex items-center gap-4">
                <label className="flex items-center gap-2 text-sm text-ink-2">
                  Data
                  <input
                    type="date"
                    value={editing.draft.publishedAt}
                    onChange={(e) =>
                      setEditing({
                        ...editing,
                        draft: { ...editing.draft, publishedAt: e.target.value },
                      })
                    }
                    className="rounded-lg border border-line-strong bg-app px-2 py-1 text-sm"
                  />
                </label>
                <label className="flex items-center gap-2 text-sm text-ink-2">
                  <input
                    type="checkbox"
                    checked={editing.draft.pinned}
                    onChange={(e) =>
                      setEditing({
                        ...editing,
                        draft: { ...editing.draft, pinned: e.target.checked },
                      })
                    }
                  />
                  In evidenza
                </label>
              </div>
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <button
                onClick={() => setEditing(null)}
                className="rounded-lg border border-line-strong px-3 py-1.5 text-sm text-ink-2"
              >
                Annulla
              </button>
              <button
                disabled={busy}
                onClick={save}
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
