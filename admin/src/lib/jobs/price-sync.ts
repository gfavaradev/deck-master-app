import "server-only";

import { adminDb } from "@/lib/firebase/admin";
import { FieldValue } from "firebase-admin/firestore";

// Porting fedele di scripts/price_sync/index.js, adattato a: singolo catalogo per
// invocazione, credenziali/JWT da env, log via callback. Vedi quel file per il
// razionale completo. NB: catalogo/prezzi/immagini sono accoppiati — mantenere
// allineate le due implementazioni.

const CT_BASE_URL = "https://api.cardtrader.com/api/v2";
const DELAY_MS = 200;
const CT_PRICE_CHUNK_SIZE = 400;

const GAME_IDS: Record<string, number> = {
  yugioh: 4, pokemon: 5, "flesh-and-blood": 6, digimon: 8,
  "dragon-ball-super": 9, vanguard: 10, onepiece: 15, lorcana: 18,
  "star-wars": 20, "union-arena": 21, riftbound: 22, gundam: 23,
};
const CHUNK_EMBED_CATALOGS = new Set(["yugioh", "pokemon", "onepiece"]);
const LANG_KEYS: Record<string, string> = { yugioh: "yugioh_language", pokemon: "pokemon_language", onepiece: "onepiece_language" };
const RARITY_KEYS: Record<string, string> = { yugioh: "yugioh_rarity", pokemon: "pokemon_rarity", onepiece: "onepiece_rarity" };

type Log = (msg: string) => void;
/* eslint-disable @typescript-eslint/no-explicit-any */

function jwt() {
  const j = process.env.CARDTRADER_JWT ?? "";
  if (!j) throw new Error("CARDTRADER_JWT non configurato");
  return j;
}
const ctHeaders = () => ({ Authorization: `Bearer ${jwt()}`, Accept: "application/json", "Accept-Encoding": "identity" });

async function ctGet(path: string): Promise<any> {
  const res = await fetch(`${CT_BASE_URL}${path}`, { headers: ctHeaders() });
  if (!res.ok) throw new Error(`CT API ${path} → HTTP ${res.status}`);
  const text = await res.text();
  if (text.trimStart().startsWith("<")) throw new Error("CardTrader in manutenzione (HTML)");
  return JSON.parse(text);
}
function normalizeLang(l?: string) {
  switch ((l ?? "").toLowerCase()) {
    case "jp": return "ja";
    case "kr": return "ko";
    case "zh-cn": return "zh";
    default: return (l ?? "en").toLowerCase();
  }
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fetchExpansions(gameId: number) {
  const all = await ctGet("/expansions");
  if (!Array.isArray(all)) throw new Error("Risposta espansioni non valida");
  return all.filter((e: any) => e.game_id === gameId);
}
async function fetchBlueprints(expansionId: number) {
  let raw = await ctGet(`/blueprints?expansion_id=${expansionId}`);
  if (raw && typeof raw === "object" && !Array.isArray(raw)) raw = raw.blueprints ?? raw.cards ?? raw.data ?? raw.items ?? [];
  return Array.isArray(raw) ? raw : [];
}
async function fetchMarketplaceProducts(expansionId: number) {
  const raw = await ctGet(`/marketplace/products?expansion_id=${expansionId}`);
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  return raw as Record<string, any[]>;
}

const stripAlphanumeric = (s: string) => s.replace(/[^a-z0-9]/g, "");

function buildExpansionMap(ctExpansions: any[], localCodes: Set<string>) {
  const strippedToLocal = new Map<string, string>();
  for (const lc of localCodes) {
    const stripped = stripAlphanumeric(lc);
    if (!strippedToLocal.has(stripped)) strippedToLocal.set(stripped, lc);
    const noPt = stripped.replace(/pt/g, "");
    if (!strippedToLocal.has(noPt)) strippedToLocal.set(noPt, lc);
  }
  const ctToLocal = new Map<string, string>();
  for (const exp of ctExpansions) {
    const ctCode = (exp.code ?? "").toLowerCase();
    if (localCodes.has(ctCode)) { ctToLocal.set(ctCode, ctCode); continue; }
    const noDash = ctCode.replace(/-/g, "");
    if (localCodes.has(noDash)) { ctToLocal.set(ctCode, noDash); continue; }
    const stripped = stripAlphanumeric(ctCode);
    const fuzzy = strippedToLocal.get(stripped) ?? strippedToLocal.get(stripped.replace(/pt/g, ""));
    if (fuzzy) ctToLocal.set(ctCode, fuzzy);
  }
  return ctToLocal;
}

function extractSetCodesFromCards(cards: any[], catalog: string): Set<string> {
  const codes = new Set<string>();
  for (const card of cards) {
    switch (catalog) {
      case "yugioh": {
        if (card.sets && typeof card.sets === "object") {
          for (const arr of Object.values(card.sets) as any[]) {
            if (!Array.isArray(arr)) continue;
            for (const s of arr) {
              const sc = (s.set_code ?? "").toLowerCase();
              if (!sc) continue;
              codes.add(sc.includes("-") ? sc.split("-")[0] : sc);
            }
          }
        }
        break;
      }
      case "pokemon": {
        if (card.sets && typeof card.sets === "object" && !Array.isArray(card.sets)) {
          for (const arr of Object.values(card.sets) as any[]) {
            if (!Array.isArray(arr)) continue;
            for (const s of arr) {
              const sc = (s.set_code ?? "").toLowerCase();
              if (!sc) continue;
              const lastDash = sc.lastIndexOf("-");
              codes.add(lastDash > 0 ? sc.slice(0, lastDash) : sc);
            }
          }
        }
        if (Array.isArray(card.prints)) for (const p of card.prints) { const sc = (p.set_code ?? "").toLowerCase(); if (sc) codes.add(sc); }
        break;
      }
      case "onepiece": {
        if (Array.isArray(card.prints)) for (const p of card.prints) { const sc = (p.set_id ?? "").toLowerCase(); if (sc) codes.add(sc); }
        break;
      }
      default: {
        const topSetId = (card.set_id ?? "").toLowerCase();
        if (topSetId) codes.add(topSetId);
        if (Array.isArray(card.prints)) for (const p of card.prints) { const sc = (p.set_id ?? p.set_code ?? "").toLowerCase(); if (sc) codes.add(sc); }
        if (card.sets && typeof card.sets === "object") {
          for (const arr of Object.values(card.sets) as any[]) {
            if (!Array.isArray(arr)) continue;
            for (const s of arr) {
              const sc = (s.set_id ?? s.set_code ?? "").toLowerCase();
              if (!sc) continue;
              codes.add(sc.includes("-") ? sc.split("-")[0] : sc);
            }
          }
        }
      }
    }
  }
  return codes;
}

function buildPriceData(catalog: string, expansionCode: string, blueprints: any[], products: Record<string, any[]>) {
  const langKey = LANG_KEYS[catalog] ?? "yugioh_language";
  const rarityKey = RARITY_KEYS[catalog] ?? "yugioh_rarity";
  const priceByNameLang = new Map<string, number>();
  const priceByCNLang = new Map<string, number>();
  const priceRows: any[] = [];
  const now = new Date().toISOString();

  const cnByBpId = new Map<number, string>();
  for (const bp of blueprints) {
    if (!bp.id) continue;
    const props = bp.fixed_properties ?? bp.properties_hash ?? {};
    const cn = ((bp.collector_number ?? props.collector_number ?? props.number) ?? "").toString().trim();
    cnByBpId.set(bp.id, cn);
  }

  for (const [bpIdStr, listings] of Object.entries(products)) {
    const bpId = parseInt(bpIdStr, 10);
    if (!bpId || !Array.isArray(listings) || listings.length === 0) continue;
    const cardNameEn = (listings[0].name_en ?? "").trim().toLowerCase();
    if (!cardNameEn) continue;
    const firstPh = listings[0].properties_hash ?? {};
    const collectorNumber = (listings[0].collector_number ?? firstPh.collector_number ?? firstPh.number ?? cnByBpId.get(bpId) ?? "").toString().trim().toLowerCase();

    const nmPrices = new Map<string, number[]>();
    const anyPrices = new Map<string, number[]>();
    const rarityMap = new Map<string, string>();

    for (const listing of listings) {
      const ph = listing.properties_hash ?? {};
      const lang = normalizeLang(ph[langKey] ?? "en");
      const isFirst = ph.first_edition === true ? 1 : 0;
      const rarity = (ph[rarityKey] ?? "").toLowerCase();
      const condition = ph.condition ?? "";
      const priceCents = listing.price_cents;
      if (!priceCents || priceCents <= 0) continue;
      const key = `${lang}|${isFirst}|${rarity}`;
      rarityMap.set(key, rarity);
      const any = anyPrices.get(key) ?? []; any.push(priceCents); anyPrices.set(key, any);
      const isNm = condition.includes("Near Mint") || (condition.includes("Mint") && !condition.includes("Moderately"));
      if (isNm) { const nm = nmPrices.get(key) ?? []; nm.push(priceCents); nmPrices.set(key, nm); }
    }

    for (const [key, any] of anyPrices) {
      const parts = key.split("|");
      const lang = parts[0];
      const isFirst = parts[1] === "1";
      const rarity = rarityMap.get(key) ?? "";
      const nm = nmPrices.get(key);
      const minNmCents = nm?.length ? Math.min(...nm) : null;
      const minAnyCents = Math.min(...any);
      const bestCents = minNmCents ?? minAnyCents;
      const price = Math.round(bestCents) / 100;

      const nameKey = `${expansionCode}|${cardNameEn}|${lang}`;
      if (!priceByNameLang.has(nameKey) || price < priceByNameLang.get(nameKey)!) priceByNameLang.set(nameKey, price);
      if (collectorNumber) {
        const cnKey = `${expansionCode}|${collectorNumber}|${lang}`;
        if (!priceByCNLang.has(cnKey) || price < priceByCNLang.get(cnKey)!) priceByCNLang.set(cnKey, price);
      }
      priceRows.push({
        blueprint_id: bpId, catalog, expansion_code: expansionCode, card_name_en: cardNameEn,
        language: lang, first_edition: isFirst ? 1 : 0, rarity, collector_number: collectorNumber,
        min_price_nm_cents: minNmCents, min_price_any_cents: minAnyCents, listing_count: any.length, synced_at: now,
      });
    }
  }
  return { priceByNameLang, priceByCNLang, priceRows };
}

async function saveCardtraderPrices(catalog: string, priceRows: any[]) {
  const db = adminDb();
  if (priceRows.length === 0) return;
  const ref = db.collection("cardtrader_prices").doc(catalog);
  const MAX_BATCH = 400;
  const oldChunks = await ref.collection("chunks").listDocuments();
  for (let i = 0; i < oldChunks.length; i += MAX_BATCH) {
    const batch = db.batch();
    for (const doc of oldChunks.slice(i, i + MAX_BATCH)) batch.delete(doc);
    await batch.commit();
  }
  for (let i = 0; i < priceRows.length; i += CT_PRICE_CHUNK_SIZE * MAX_BATCH) {
    const batch = db.batch();
    for (let start = i; start < Math.min(i + CT_PRICE_CHUNK_SIZE * MAX_BATCH, priceRows.length); start += CT_PRICE_CHUNK_SIZE) {
      batch.set(ref.collection("chunks").doc(`${start}`), { rows: priceRows.slice(start, start + CT_PRICE_CHUNK_SIZE) });
    }
    await batch.commit();
  }
  await ref.set({ catalog, count: priceRows.length, syncedAt: FieldValue.serverTimestamp() });
}

async function syncPricesToCatalogChunks(catalog: string, priceByNameLang: Map<string, number>, priceByCNLang: Map<string, number>, log: Log) {
  const db = adminDb();
  const catalogCollection = `${catalog}_catalog`;
  const metaDoc = await db.collection(catalogCollection).doc("metadata").get();
  if (!metaDoc.exists) throw new Error(`Metadati ${catalog}_catalog non trovati`);
  const totalChunks = metaDoc.data()?.totalChunks ?? 0;
  if (totalChunks === 0) throw new Error(`Catalogo ${catalog} vuoto`);

  let updatedPrices = 0, modifiedChunks = 0;
  const modifiedChunkIds: string[] = [];

  for (let i = 0; i < totalChunks; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    const chunkRef = db.collection(catalogCollection).doc("chunks").collection("items").doc(chunkId);
    const snap = await chunkRef.get();
    if (!snap.exists) continue;
    const rawCards = snap.data()?.cards ?? [];
    let chunkModified = false;

    const updatedCards = rawCards.map((card: any) => {
      const c = { ...card };
      let cardModified = false;
      const nameEn = (c.name ?? "").toLowerCase();
      if (catalog === "yugioh") {
        if (c.sets && typeof c.sets === "object") {
          const newSets: any = {};
          for (const [langKey, arr] of Object.entries(c.sets) as any[]) {
            const lang = langKey.toLowerCase();
            const ctLang = lang === "sp" ? "es" : lang;
            if (!Array.isArray(arr)) { newSets[langKey] = arr; continue; }
            newSets[langKey] = arr.map((s: any) => {
              const rawCode = (s.set_code ?? "").toUpperCase();
              const expCode = rawCode.includes("-") ? rawCode.split("-")[0].toLowerCase() : rawCode.toLowerCase();
              let price = priceByNameLang.get(`${expCode}|${nameEn}|${ctLang}`);
              if (price == null) {
                const cn = rawCode.includes("-") ? rawCode.split("-").pop().toLowerCase() : "";
                if (cn) price = priceByCNLang.get(`${expCode}|${cn}|${ctLang}`);
              }
              if (price != null) { cardModified = true; updatedPrices++; return { ...s, set_price: price }; }
              return s;
            });
          }
          if (cardModified) c.sets = newSets;
        }
      } else if (catalog === "pokemon") {
        if (c.sets && typeof c.sets === "object" && !Array.isArray(c.sets)) {
          const newSets: any = {};
          for (const [langKey, arr] of Object.entries(c.sets) as any[]) {
            const lang = langKey.toLowerCase();
            if (!Array.isArray(arr)) { newSets[langKey] = arr; continue; }
            newSets[langKey] = arr.map((s: any) => {
              const rawCode = (s.set_code ?? "").toLowerCase();
              const lastDash = rawCode.lastIndexOf("-");
              const expCode = lastDash > 0 ? rawCode.slice(0, lastDash) : rawCode;
              if (!expCode) return s;
              const price = priceByNameLang.get(`${expCode}|${nameEn}|${lang}`);
              if (price != null) { cardModified = true; updatedPrices++; return { ...s, set_price: price }; }
              return s;
            });
          }
          if (cardModified) c.sets = newSets;
        } else if (Array.isArray(c.prints)) {
          const cols: any = { en: "set_price", it: "set_price_it", fr: "set_price_fr", de: "set_price_de", es: "set_price_es", pt: "set_price_pt" };
          c.prints = c.prints.map((p: any) => {
            const expCode = (p.set_code ?? "").toLowerCase();
            if (!expCode) return p;
            const updated = { ...p }; let printModified = false;
            for (const [lang, field] of Object.entries(cols) as any[]) {
              const price = priceByNameLang.get(`${expCode}|${nameEn}|${lang}`);
              if (price != null) { updated[field] = price; printModified = true; updatedPrices++; }
            }
            if (printModified) cardModified = true;
            return updated;
          });
        }
      } else if (catalog === "onepiece") {
        if (Array.isArray(c.prints)) {
          const fields: any = { ja: "market_price", en: "market_price_en", fr: "market_price_fr", ko: "market_price_ko", zh: "market_price_zh" };
          c.prints = c.prints.map((p: any) => {
            const expCode = (p.set_id ?? "").toLowerCase();
            if (!expCode) return p;
            const updated = { ...p }; let printModified = false;
            for (const [lang, field] of Object.entries(fields) as any[]) {
              const price = priceByNameLang.get(`${expCode}|${nameEn}|${lang}`);
              if (price != null) { updated[field] = price; printModified = true; updatedPrices++; }
            }
            if (printModified) { cardModified = true; return updated; }
            return p;
          });
        }
      }
      if (cardModified) chunkModified = true;
      return c;
    });

    if (chunkModified) {
      await chunkRef.set({ cards: updatedCards });
      modifiedChunkIds.push(chunkId);
      modifiedChunks++;
    }
  }
  if (modifiedChunks > 0) {
    await db.collection(catalogCollection).doc("metadata").set(
      { lastUpdated: FieldValue.serverTimestamp(), updatedBy: "admin-dashboard", pricesSyncedAt: FieldValue.serverTimestamp(), priceModifiedChunks: modifiedChunkIds },
      { merge: true },
    );
  }
  log(`chunk modificati: ${modifiedChunks}/${totalChunks}, prezzi: ${updatedPrices}`);
  return { modifiedChunks, totalChunks, updatedPrices };
}

async function getSetCodesFromFirestore(catalog: string) {
  const db = adminDb();
  const catalogCollection = `${catalog}_catalog`;
  const metaSnap = await db.collection(catalogCollection).doc("metadata").get();
  const totalChunks = metaSnap.exists ? metaSnap.data()?.totalChunks ?? 0 : 0;
  const codes = new Set<string>();
  for (let i = 0; i < totalChunks; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    const snap = await db.collection(catalogCollection).doc("chunks").collection("items").doc(chunkId).get();
    if (!snap.exists) continue;
    for (const code of extractSetCodesFromCards(snap.data()?.cards ?? [], catalog)) codes.add(code);
  }
  return { codes, totalChunks };
}

const SCRYFALL_HEADERS = { Accept: "application/json", "User-Agent": "DeckMaster/1.0 (g.favara.dev@gmail.com)" };

async function syncMagicPrices(log: Log) {
  const bulkRes = await fetch("https://api.scryfall.com/bulk-data", { headers: SCRYFALL_HEADERS });
  if (!bulkRes.ok) throw new Error(`Scryfall bulk-data HTTP ${bulkRes.status}`);
  const bulkJson = await bulkRes.json();
  const oracleEntry = (bulkJson.data ?? []).find((e: any) => e.type === "oracle_cards");
  if (!oracleEntry) throw new Error("oracle_cards non trovato");
  const dataRes = await fetch(oracleEntry.download_uri, { headers: SCRYFALL_HEADERS });
  if (!dataRes.ok) throw new Error(`Download bulk HTTP ${dataRes.status}`);
  const rawList = await dataRes.json();
  const priceRows: any[] = [];
  for (const raw of rawList) {
    const layout = raw.layout ?? "";
    if (layout === "token" || layout === "emblem" || layout === "art_series") continue;
    if ((raw.lang ?? "en") !== "en") continue;
    const prices = raw.prices ?? {};
    const priceEur = parseFloat(prices.eur) || null;
    const priceEurFoil = parseFloat(prices.eur_foil) || null;
    if (priceEur === null && priceEurFoil === null) continue;
    priceRows.push({ api_id: raw.id, price_eur: priceEur, price_eur_foil: priceEurFoil });
  }
  if (priceRows.length === 0) { log("nessun prezzo Magic"); return { rows: 0 }; }
  await saveCardtraderPrices("magic", priceRows);
  log(`${priceRows.length} prezzi Magic salvati`);
  return { rows: priceRows.length };
}

export type PriceSyncResult = { catalog: string; rows: number; embedded?: number; skipped?: boolean; message: string };

// Esegue il price sync di UN catalogo. Scrive lo stato in admin_jobs/price_sync_{catalog}.
export async function runPriceSyncForCatalog(catalog: string, log: Log = () => {}): Promise<PriceSyncResult> {
  const db = adminDb();
  const statusRef = db.collection("admin_jobs").doc(`price_sync_${catalog}`);
  await statusRef.set({ catalog, status: "running", startedAt: FieldValue.serverTimestamp() }, { merge: true });

  try {
    if (catalog === "magic") {
      const { rows } = await syncMagicPrices(log);
      const res = { catalog, rows, message: `${rows} prezzi Magic` };
      await statusRef.set({ status: "ok", finishedAt: FieldValue.serverTimestamp(), rows }, { merge: true });
      return res;
    }

    const gameId = GAME_IDS[catalog];
    if (!gameId) return { catalog, rows: 0, skipped: true, message: "nessun game ID CardTrader" };

    log(`carico espansioni CT (game ${gameId})`);
    const ctExpansions = await fetchExpansions(gameId);
    const { codes: localCodes } = await getSetCodesFromFirestore(catalog);
    if (localCodes.size === 0) return { catalog, rows: 0, skipped: true, message: "catalogo non presente su Firestore" };

    const ctToLocal = buildExpansionMap(ctExpansions, localCodes);
    const matched = ctExpansions.filter((e: any) => ctToLocal.has((e.code ?? "").toLowerCase()));
    log(`espansioni abbinate: ${matched.length}/${ctExpansions.length}`);
    if (matched.length === 0) return { catalog, rows: 0, skipped: true, message: "nessuna espansione abbinata" };

    const globalNameMap = new Map<string, number>();
    const globalCnMap = new Map<string, number>();
    const allPriceRows: any[] = [];

    for (let i = 0; i < matched.length; i++) {
      const exp = matched[i];
      const localCode = ctToLocal.get((exp.code ?? "").toLowerCase())!;
      try {
        const [blueprints, products] = await Promise.all([fetchBlueprints(exp.id), fetchMarketplaceProducts(exp.id)]);
        if (Object.keys(products).length > 0) {
          const { priceByNameLang, priceByCNLang, priceRows } = buildPriceData(catalog, localCode, blueprints, products);
          for (const [k, v] of priceByNameLang) if (!globalNameMap.has(k) || v < globalNameMap.get(k)!) globalNameMap.set(k, v);
          for (const [k, v] of priceByCNLang) if (!globalCnMap.has(k) || v < globalCnMap.get(k)!) globalCnMap.set(k, v);
          allPriceRows.push(...priceRows);
        }
      } catch { /* espansione saltata */ }
      await sleep(DELAY_MS);
    }

    if (allPriceRows.length === 0) return { catalog, rows: 0, skipped: true, message: "nessun prezzo raccolto" };

    await saveCardtraderPrices(catalog, allPriceRows);
    let embedded = 0;
    if (CHUNK_EMBED_CATALOGS.has(catalog)) {
      const r = await syncPricesToCatalogChunks(catalog, globalNameMap, globalCnMap, log);
      embedded = r.updatedPrices;
    }
    await statusRef.set({ status: "ok", finishedAt: FieldValue.serverTimestamp(), rows: allPriceRows.length, embedded }, { merge: true });
    return { catalog, rows: allPriceRows.length, embedded, message: `${allPriceRows.length} prezzi${embedded ? `, ${embedded} embedded` : ""}` };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await statusRef.set({ status: "error", finishedAt: FieldValue.serverTimestamp(), error: msg }, { merge: true });
    throw e;
  }
}
