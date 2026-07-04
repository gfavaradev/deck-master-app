import "server-only";

import { adminDb } from "@/lib/firebase/admin";
import { FieldValue } from "firebase-admin/firestore";

/* eslint-disable @typescript-eslint/no-explicit-any */

// I cataloghi usano `{catalog}_catalog/chunks/items/chunk_NNN` con { cards: [...] }.
// Identità carta: `id` (yugioh) oppure `api_id` (pokemon/onepiece/magic/generici).

export function cardId(card: any): string {
  return String(card?.id ?? card?.api_id ?? "");
}

function chunkDocId(i: number) {
  return `chunk_${String(i + 1).padStart(3, "0")}`;
}

export type CatalogInfo = { catalog: string; totalCards: number; totalChunks: number };

const CATALOG_KEYS = [
  "yugioh", "pokemon", "onepiece", "magic", "digimon", "lorcana",
  "flesh-and-blood", "vanguard", "dragon-ball-super", "star-wars",
  "riftbound", "gundam", "union-arena",
];

export async function listCatalogs(): Promise<CatalogInfo[]> {
  const db = adminDb();
  const out = await Promise.all(
    CATALOG_KEYS.map(async (catalog) => {
      const meta = await db.collection(`${catalog}_catalog`).doc("metadata").get();
      const d = meta.data() ?? {};
      return {
        catalog,
        totalCards: Number(d.totalCards ?? 0),
        totalChunks: Number(d.totalChunks ?? 0),
      } satisfies CatalogInfo;
    }),
  );
  return out.filter((c) => c.totalChunks > 0);
}

export type CardHit = {
  chunkId: string;
  cardId: string;
  name: string;
  imageUrl: string | null;
  card: any;
};

function nameMatches(card: any, q: string): boolean {
  const fields = [
    card.name, card.name_it, card.name_fr, card.name_de, card.name_es,
    card.name_pt, card.name_en,
  ];
  return fields.some((f) => typeof f === "string" && f.toLowerCase().includes(q));
}

// Cerca per nome scandendo i chunk (uso admin, non per-keystroke). Ritorna fino a `limit`.
export async function searchCards(
  catalog: string,
  query: string,
  limit = 60,
): Promise<CardHit[]> {
  const db = adminDb();
  const col = db.collection(`${catalog}_catalog`);
  const meta = await col.doc("metadata").get();
  const totalChunks = Number(meta.data()?.totalChunks ?? 0);
  const q = query.trim().toLowerCase();
  const hits: CardHit[] = [];

  for (let i = 0; i < totalChunks && hits.length < limit; i++) {
    const chunkId = chunkDocId(i);
    const snap = await col.doc("chunks").collection("items").doc(chunkId).get();
    if (!snap.exists) continue;
    const cards: any[] = snap.data()?.cards ?? [];
    for (const card of cards) {
      if (q && !nameMatches(card, q)) continue;
      hits.push({
        chunkId,
        cardId: cardId(card),
        name: card.name ?? card.name_en ?? "(senza nome)",
        imageUrl: card.image_url ?? card.imageUrl ?? null,
        card,
      });
      if (hits.length >= limit) break;
    }
  }
  return hits;
}

async function chunkRef(catalog: string, chunkId: string) {
  return adminDb()
    .collection(`${catalog}_catalog`)
    .doc("chunks")
    .collection("items")
    .doc(chunkId);
}

async function touchMeta(catalog: string) {
  await adminDb()
    .collection(`${catalog}_catalog`)
    .doc("metadata")
    .set(
      { lastUpdated: FieldValue.serverTimestamp(), updatedBy: "admin-dashboard" },
      { merge: true },
    );
}

// Applica un patch di soli campi scalari (string/number/bool/null) alla carta nel chunk.
export async function updateCardScalars(
  catalog: string,
  chunkId: string,
  id: string,
  patch: Record<string, string | number | boolean | null>,
): Promise<void> {
  const ref = await chunkRef(catalog, chunkId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("chunk non trovato");
  const cards: any[] = snap.data()?.cards ?? [];
  const idx = cards.findIndex((c) => cardId(c) === id);
  if (idx < 0) throw new Error("carta non trovata nel chunk");

  const safe: Record<string, any> = {};
  for (const [k, v] of Object.entries(patch)) {
    // Solo scalari: mai sovrascrivere strutture annidate (sets/prints) da qui.
    if (v === null || ["string", "number", "boolean"].includes(typeof v)) safe[k] = v;
  }
  cards[idx] = { ...cards[idx], ...safe };
  await ref.set({ cards });
  await touchMeta(catalog);
}

export async function deleteCard(
  catalog: string,
  chunkId: string,
  id: string,
): Promise<void> {
  const ref = await chunkRef(catalog, chunkId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("chunk non trovato");
  const cards: any[] = snap.data()?.cards ?? [];
  const next = cards.filter((c) => cardId(c) !== id);
  if (next.length === cards.length) throw new Error("carta non trovata");
  await ref.set({ cards: next });
  await touchMeta(catalog);
}
