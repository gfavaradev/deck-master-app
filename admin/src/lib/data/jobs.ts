import "server-only";

import { adminDb } from "@/lib/firebase/admin";
import { Timestamp } from "firebase-admin/firestore";

// Cataloghi con game ID CardTrader (price sync) — allineato a scripts/price_sync.
export const PRICE_CATALOGS = [
  "yugioh",
  "onepiece",
  "pokemon",
  "magic",
  "digimon",
  "lorcana",
  "flesh-and-blood",
  "vanguard",
  "dragon-ball-super",
  "star-wars",
  "riftbound",
  "gundam",
  "union-arena",
];

export type PriceStatus = {
  catalog: string;
  count: number | null;
  syncedAt: string | null; // da cardtrader_prices/{catalog}.syncedAt
  chunkPricesSyncedAt: string | null; // da {catalog}_catalog/metadata.pricesSyncedAt (embed)
};

function tsToIso(v: unknown): string | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (typeof v === "string") return v;
  if (typeof v === "object" && v !== null && "_seconds" in v) {
    return new Date((v as { _seconds: number })._seconds * 1000).toISOString();
  }
  return null;
}

export async function getPriceStatuses(): Promise<PriceStatus[]> {
  const db = adminDb();
  return Promise.all(
    PRICE_CATALOGS.map(async (catalog) => {
      const [priceDoc, metaDoc] = await Promise.all([
        db.collection("cardtrader_prices").doc(catalog).get(),
        db.collection(`${catalog}_catalog`).doc("metadata").get(),
      ]);
      const p = priceDoc.data() ?? {};
      const m = metaDoc.data() ?? {};
      return {
        catalog,
        count: (p.count as number) ?? null,
        syncedAt: tsToIso(p.syncedAt),
        chunkPricesSyncedAt: tsToIso(m.pricesSyncedAt),
      } satisfies PriceStatus;
    }),
  );
}
