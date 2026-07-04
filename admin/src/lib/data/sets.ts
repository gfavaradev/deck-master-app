import "server-only";

import { adminDb } from "@/lib/firebase/admin";

/* eslint-disable @typescript-eslint/no-explicit-any */

// Conteggio carte per SET (espansione) di un catalogo.
// Una carta può appartenere a più set: viene contata una volta per ciascun set.
// Chiave del set: `set_name` se presente, altrimenti il prefisso del codice.

function normLabel(code?: string, name?: string): string | null {
  const n = (name ?? "").trim();
  if (n) return n;
  const c = (code ?? "").trim();
  if (!c) return null;
  // Prefisso espansione (es. "LOB-EN001" → "LOB", "op01-001" → "OP01")
  return (c.includes("-") ? c.split("-")[0] : c).toUpperCase();
}

function cardSetLabels(card: any): Set<string> {
  const labels = new Set<string>();
  const add = (code?: string, name?: string) => {
    const l = normLabel(code, name);
    if (l) labels.add(l);
  };
  add(card.set_code ?? card.set_id, card.set_name);
  if (Array.isArray(card.prints))
    for (const p of card.prints) add(p.set_code ?? p.set_id ?? p.card_set_id, p.set_name);
  if (card.sets && typeof card.sets === "object" && !Array.isArray(card.sets)) {
    for (const arr of Object.values(card.sets) as any[]) {
      if (!Array.isArray(arr)) continue;
      for (const s of arr) add(s.set_code ?? s.set_id, s.set_name);
    }
  }
  return labels;
}

export type SetCount = { set: string; count: number };
export type SetBreakdown = { total: number; sets: SetCount[] };

export async function getSetBreakdown(catalog: string): Promise<SetBreakdown> {
  const db = adminDb();
  const col = db.collection(`${catalog}_catalog`);
  const meta = await col.doc("metadata").get();
  const totalChunks = Number(meta.data()?.totalChunks ?? 0);

  const counts = new Map<string, number>();
  let total = 0;

  for (let i = 0; i < totalChunks; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    const snap = await col.doc("chunks").collection("items").doc(chunkId).get();
    if (!snap.exists) continue;
    const cards: any[] = snap.data()?.cards ?? [];
    for (const card of cards) {
      total++;
      for (const label of cardSetLabels(card)) {
        counts.set(label, (counts.get(label) ?? 0) + 1);
      }
    }
  }

  const sets = [...counts.entries()]
    .map(([set, count]) => ({ set, count }))
    .sort((a, b) => b.count - a.count);
  return { total, sets };
}
