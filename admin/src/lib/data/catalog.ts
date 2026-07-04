import "server-only";

import { adminDb } from "@/lib/firebase/admin";
import { Timestamp } from "firebase-admin/firestore";

const CATALOG_KEYS = [
  "yugioh", "pokemon", "onepiece", "magic", "digimon", "lorcana",
  "flesh-and-blood", "vanguard", "dragon-ball-super", "star-wars",
  "riftbound", "gundam", "union-arena",
];

// Fonte dati sorgente di ogni catalogo (per il rebuild — vedi scripts/ e admin_catalog_service).
export const CATALOG_SOURCE: Record<string, string> = {
  yugioh: "YGOProDeck (scripts/populate_firestore)",
  pokemon: "TCGdex",
  onepiece: "OPTCG / apitcg",
  magic: "Scryfall bulk (~100MB)",
  digimon: "CardTrader (generic)",
  lorcana: "CardTrader (generic)",
  "flesh-and-blood": "CardTrader (generic)",
  vanguard: "CardTrader (generic)",
  "dragon-ball-super": "CardTrader (generic)",
  "star-wars": "CardTrader (generic)",
  riftbound: "CardTrader (generic)",
  gundam: "CardTrader (generic)",
  "union-arena": "CardTrader (generic)",
};

export type CatalogStatus = {
  catalog: string;
  totalCards: number;
  totalChunks: number;
  version: number | null;
  lastUpdated: string | null;
  updatedBy: string | null;
  source: string;
};

function tsToIso(v: unknown): string | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (typeof v === "string") return v;
  if (typeof v === "object" && v !== null && "_seconds" in v)
    return new Date((v as { _seconds: number })._seconds * 1000).toISOString();
  return null;
}

export async function getCatalogStatuses(): Promise<CatalogStatus[]> {
  const db = adminDb();
  return Promise.all(
    CATALOG_KEYS.map(async (catalog) => {
      const meta = await db.collection(`${catalog}_catalog`).doc("metadata").get();
      const d = meta.data() ?? {};
      return {
        catalog,
        totalCards: Number(d.totalCards ?? 0),
        totalChunks: Number(d.totalChunks ?? 0),
        version: d.version != null ? Number(d.version) : null,
        lastUpdated: tsToIso(d.lastUpdated),
        updatedBy: (d.updatedBy as string) ?? null,
        source: CATALOG_SOURCE[catalog] ?? "—",
      } satisfies CatalogStatus;
    }),
  );
}
