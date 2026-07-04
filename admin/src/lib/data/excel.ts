import "server-only";

import * as XLSX from "xlsx";
import { adminDb } from "@/lib/firebase/admin";
import { FieldValue } from "firebase-admin/firestore";
import { cardId } from "@/lib/data/cards";

/* eslint-disable @typescript-eslint/no-explicit-any */

// Export/import generico dei CAMPI SCALARI delle carte (bulk edit via foglio).
// Non è il template SQLite-per-TCG dell'app: è un formato scalare, coerente col
// modulo Carte (solo string/number/bool; le strutture sets/prints restano intatte).
// L'identità carta (id/api_id) è la chiave di match e non è modificabile.

function isScalar(v: unknown) {
  return v === null || ["string", "number", "boolean"].includes(typeof v);
}

const ID_FIELDS = new Set(["id", "api_id"]);

type ChunkCards = { chunkId: string; cards: any[] };

async function readChunks(catalog: string): Promise<ChunkCards[]> {
  const db = adminDb();
  const col = db.collection(`${catalog}_catalog`);
  const meta = await col.doc("metadata").get();
  const totalChunks = Number(meta.data()?.totalChunks ?? 0);
  const out: ChunkCards[] = [];
  for (let i = 0; i < totalChunks; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    const snap = await col.doc("chunks").collection("items").doc(chunkId).get();
    if (snap.exists) out.push({ chunkId, cards: snap.data()?.cards ?? [] });
  }
  return out;
}

// ── Export ────────────────────────────────────────────────────────────────
export async function exportCatalogXlsx(catalog: string): Promise<Buffer> {
  const chunks = await readChunks(catalog);
  const cards = chunks.flatMap((c) => c.cards);
  if (cards.length === 0) throw new Error("Catalogo vuoto su Firestore");

  // Colonne = unione dei campi scalari presenti; `id`/`api_id` per prime.
  const cols = new Set<string>();
  for (const card of cards)
    for (const [k, v] of Object.entries(card)) if (isScalar(v)) cols.add(k);
  const ordered = [
    ...[...ID_FIELDS].filter((k) => cols.has(k)),
    ...[...cols].filter((k) => !ID_FIELDS.has(k)).sort(),
  ];

  const aoa: any[][] = [ordered];
  for (const card of cards) {
    aoa.push(ordered.map((k) => (isScalar(card[k]) ? card[k] : null)));
  }
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "Carte");
  return XLSX.write(wb, { type: "buffer", bookType: "xlsx" }) as Buffer;
}

// ── Import: preview ─────────────────────────────────────────────────────────
export type CardChange = {
  id: string;
  name: string;
  chunkId: string;
  changes: Record<string, { from: any; to: any }>;
};

function parseRows(buffer: Buffer): any[] {
  const wb = XLSX.read(buffer, { type: "buffer" });
  const ws = wb.Sheets[wb.SheetNames[0]];
  return XLSX.utils.sheet_to_json(ws, { defval: null });
}

export type ImportPreview = {
  changes: CardChange[];
  unmatched: number;
  totalRows: number;
};

export async function previewImport(
  catalog: string,
  buffer: Buffer,
): Promise<ImportPreview> {
  const rows = parseRows(buffer);
  const chunks = await readChunks(catalog);
  const index = new Map<string, { chunkId: string; card: any }>();
  for (const { chunkId, cards } of chunks)
    for (const card of cards) index.set(cardId(card), { chunkId, card });

  const changes: CardChange[] = [];
  let unmatched = 0;

  for (const row of rows) {
    const id = String(row.id ?? row.api_id ?? "");
    const found = id ? index.get(id) : undefined;
    if (!found) {
      unmatched++;
      continue;
    }
    const diff: Record<string, { from: any; to: any }> = {};
    for (const [k, v] of Object.entries(row)) {
      if (ID_FIELDS.has(k)) continue;
      if (!isScalar(v)) continue;
      // Normalizza confronto: il foglio può restituire numeri/stringhe diverse.
      const cur = found.card[k] ?? null;
      const next = v === "" ? null : v;
      if (String(cur ?? "") !== String(next ?? "")) diff[k] = { from: cur, to: next };
    }
    if (Object.keys(diff).length > 0) {
      changes.push({
        id,
        name: found.card.name ?? found.card.name_en ?? id,
        chunkId: found.chunkId,
        changes: diff,
      });
    }
  }
  return { changes, unmatched, totalRows: rows.length };
}

// ── Import: apply ───────────────────────────────────────────────────────────
export async function applyImport(
  catalog: string,
  patches: { id: string; chunkId: string; patch: Record<string, any> }[],
): Promise<number> {
  const db = adminDb();
  const col = db.collection(`${catalog}_catalog`);
  // Raggruppa per chunk: una lettura + una scrittura per chunk.
  const byChunk = new Map<string, { id: string; patch: Record<string, any> }[]>();
  for (const p of patches) {
    const arr = byChunk.get(p.chunkId) ?? [];
    arr.push({ id: p.id, patch: p.patch });
    byChunk.set(p.chunkId, arr);
  }

  let applied = 0;
  for (const [chunkId, list] of byChunk) {
    const ref = col.doc("chunks").collection("items").doc(chunkId);
    const snap = await ref.get();
    if (!snap.exists) continue;
    const cards: any[] = snap.data()?.cards ?? [];
    const patchById = new Map(list.map((l) => [l.id, l.patch]));
    let modified = false;
    const next = cards.map((c) => {
      const patch = patchById.get(cardId(c));
      if (!patch) return c;
      const safe: Record<string, any> = {};
      for (const [k, v] of Object.entries(patch))
        if (!ID_FIELDS.has(k) && isScalar(v)) safe[k] = v;
      if (Object.keys(safe).length === 0) return c;
      modified = true;
      applied++;
      return { ...c, ...safe };
    });
    if (modified) await ref.set({ cards: next });
  }

  if (applied > 0) {
    await col
      .doc("metadata")
      .set(
        { lastUpdated: FieldValue.serverTimestamp(), updatedBy: "admin-dashboard-excel" },
        { merge: true },
      );
  }
  return applied;
}
