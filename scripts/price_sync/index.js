/**
 * Daily CardTrader price sync — Deck Master
 *
 * Per ogni catalogo con supporto CT:
 *   1. Scarica espansioni CT + match con set locali
 *   2. Per ogni espansione abbinata: fetch blueprints + marketplace products
 *   3. Salva i prezzi grezzi in `cardtrader_prices/{catalog}` (TUTTI i cataloghi)
 *   4. Per yugioh/pokemon/onepiece: embeds prezzi anche nei chunk `{catalog}_catalog`
 *   5. Scrive pricesSyncedAt + priceModifiedChunks nei metadati
 *
 * Setup:
 *   1. Metti serviceAccountKey.json in questa cartella
 *   2. Copia .env dal root del progetto (deve avere CARDTRADER_JWT=...)
 *   3. npm install
 *   4. node index.js
 *
 * Cron (esecuzione giornaliera alle 03:00):
 *   0 3 * * * cd /path/to/scripts/price_sync && node index.js >> price_sync.log 2>&1
 *
 * Cataloghi specifici:
 *   node index.js --catalogs yugioh,onepiece
 */

import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// ─── Config ───────────────────────────────────────────────────────────────────

const __dir = dirname(fileURLToPath(import.meta.url));

function loadEnv() {
  const envPath = resolve(__dir, "../../.env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx < 0) continue;
    const key = trimmed.slice(0, idx).trim();
    const val = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
    if (key && !process.env[key]) process.env[key] = val;
  }
}
loadEnv();

const CT_BASE_URL = "https://api.cardtrader.com/api/v2";
const CT_JWT = process.env.CARDTRADER_JWT ?? "";
const DELAY_MS = 200;
const CT_PRICE_CHUNK_SIZE = 400; // identico a FirestoreService._ctChunkSize

// CT game ID per catalogo (stessa mappa di CardtraderService.gameIds in Dart)
const GAME_IDS = {
  yugioh:             4,
  pokemon:            5,
  "flesh-and-blood":  6,
  digimon:            8,
  "dragon-ball-super":9,
  vanguard:           10,
  onepiece:           15,
  lorcana:            18,
  "star-wars":        20,
  "union-arena":      21,
  riftbound:          22,
  gundam:             23,
};

// Tutti i cataloghi dell'app (ordine uguale all'UI admin)
const ALL_CATALOGS = [
  "yugioh", "onepiece", "pokemon",
  "magic",  // nessun CT game ID → saltato
  "digimon", "lorcana", "flesh-and-blood", "vanguard",
  "dragon-ball-super", "star-wars", "riftbound", "gundam", "union-arena",
];

// Cataloghi che supportano il price embedding nei catalog chunks
const CHUNK_EMBED_CATALOGS = new Set(["yugioh", "pokemon", "onepiece"]);

const LANG_KEYS = {
  yugioh:   "yugioh_language",
  pokemon:  "pokemon_language",
  onepiece: "onepiece_language",
};
const RARITY_KEYS = {
  yugioh:   "yugioh_rarity",
  pokemon:  "pokemon_rarity",
  onepiece: "onepiece_rarity",
};

// ─── Init ─────────────────────────────────────────────────────────────────────

const keyPath = resolve(__dir, "serviceAccountKey.json");
if (!CT_JWT) {
  console.error("❌ CARDTRADER_JWT non configurato (env o .env)");
  process.exit(1);
}

// Locale: usa serviceAccountKey.json. Cloud Run / ambienti gestiti: nessun key
// file → Application Default Credentials (il service account del runtime).
if (existsSync(keyPath)) {
  initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, "utf8"))) });
} else {
  initializeApp();
}
const db = getFirestore();

// ─── CT API helpers ───────────────────────────────────────────────────────────

const CT_HEADERS = {
  Authorization: `Bearer ${CT_JWT}`,
  Accept: "application/json",
  "Accept-Encoding": "identity",
};

async function ctGet(path) {
  const res = await fetch(`${CT_BASE_URL}${path}`, { headers: CT_HEADERS });
  if (!res.ok) throw new Error(`CT API ${path} → HTTP ${res.status}`);
  const text = await res.text();
  if (text.trimStart().startsWith("<"))
    throw new Error("CardTrader in manutenzione (risposta HTML)");
  return JSON.parse(text);
}

function normalizeLang(ctLang) {
  switch ((ctLang ?? "").toLowerCase()) {
    case "jp":    return "ja";
    case "kr":    return "ko";
    case "zh-cn": return "zh";
    default:      return (ctLang ?? "en").toLowerCase();
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function fetchExpansions(gameId) {
  const all = await ctGet("/expansions");
  if (!Array.isArray(all)) throw new Error("Risposta espansioni non valida");
  return all.filter((e) => e.game_id === gameId);
}

async function fetchBlueprints(expansionId) {
  let raw = await ctGet(`/blueprints?expansion_id=${expansionId}`);
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    raw = raw.blueprints ?? raw.cards ?? raw.data ?? raw.items ?? [];
  }
  return Array.isArray(raw) ? raw : [];
}

async function fetchMarketplaceProducts(expansionId) {
  const raw = await ctGet(`/marketplace/products?expansion_id=${expansionId}`);
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  return raw;
}

// ─── Set code matching ────────────────────────────────────────────────────────

function stripAlphanumeric(s) {
  return s.replace(/[^a-z0-9]/g, "");
}

function buildExpansionMap(ctExpansions, localCodes) {
  const localSet = new Set(localCodes);
  const strippedToLocal = new Map();
  for (const lc of localCodes) {
    const stripped = stripAlphanumeric(lc);
    if (!strippedToLocal.has(stripped)) strippedToLocal.set(stripped, lc);
    const noPt = stripped.replace(/pt/g, "");
    if (!strippedToLocal.has(noPt)) strippedToLocal.set(noPt, lc);
  }

  const ctToLocal = new Map();
  for (const exp of ctExpansions) {
    const ctCode = (exp.code ?? "").toLowerCase();
    if (localSet.has(ctCode)) {
      ctToLocal.set(ctCode, ctCode);
    } else {
      const noDash = ctCode.replace(/-/g, "");
      if (localSet.has(noDash)) {
        ctToLocal.set(ctCode, noDash);
      } else {
        const stripped = stripAlphanumeric(ctCode);
        const fuzzy =
          strippedToLocal.get(stripped) ??
          strippedToLocal.get(stripped.replace(/pt/g, ""));
        if (fuzzy) ctToLocal.set(ctCode, fuzzy);
      }
    }
  }
  return ctToLocal;
}

// ─── Set code extraction from Firestore chunks ───────────────────────────────

function extractSetCodesFromCards(cards, catalog) {
  const codes = new Set();
  for (const card of cards) {
    switch (catalog) {
      case "yugioh": {
        const sets = card.sets;
        if (sets && typeof sets === "object") {
          for (const langArr of Object.values(sets)) {
            if (!Array.isArray(langArr)) continue;
            for (const s of langArr) {
              const sc = (s.set_code ?? "").toLowerCase();
              if (!sc) continue;
              const expCode = sc.includes("-") ? sc.split("-")[0] : sc;
              if (expCode) codes.add(expCode);
            }
          }
        }
        break;
      }
      case "pokemon": {
        const sets = card.sets;
        if (sets && typeof sets === "object" && !Array.isArray(sets)) {
          for (const langArr of Object.values(sets)) {
            if (!Array.isArray(langArr)) continue;
            for (const s of langArr) {
              const sc = (s.set_code ?? "").toLowerCase();
              if (!sc) continue;
              const lastDash = sc.lastIndexOf("-");
              const expCode = lastDash > 0 ? sc.slice(0, lastDash) : sc;
              if (expCode) codes.add(expCode);
            }
          }
        }
        if (card.prints && Array.isArray(card.prints)) {
          for (const p of card.prints) {
            const sc = (p.set_code ?? "").toLowerCase();
            if (sc) codes.add(sc);
          }
        }
        break;
      }
      case "onepiece": {
        if (Array.isArray(card.prints)) {
          for (const p of card.prints) {
            const sc = (p.set_id ?? "").toLowerCase();
            if (sc) codes.add(sc);
          }
        }
        break;
      }
      default: {
        // Cataloghi senza chunk embedding: estrai da set_id / prints
        const topSetId = (card.set_id ?? "").toLowerCase();
        if (topSetId) codes.add(topSetId);
        if (Array.isArray(card.prints)) {
          for (const p of card.prints) {
            const sc = (p.set_id ?? p.set_code ?? "").toLowerCase();
            if (sc) codes.add(sc);
          }
        }
        if (card.sets && typeof card.sets === "object") {
          for (const langArr of Object.values(card.sets)) {
            if (!Array.isArray(langArr)) continue;
            for (const s of langArr) {
              const sc = (s.set_id ?? s.set_code ?? "").toLowerCase();
              if (!sc) continue;
              // Prova a estrarre il prefisso espansione
              const expCode = sc.includes("-")
                ? sc.split("-")[0]
                : sc;
              if (expCode) codes.add(expCode);
            }
          }
        }
        break;
      }
    }
  }
  return codes;
}

// ─── Price collection ─────────────────────────────────────────────────────────

/**
 * Costruisce:
 *   - priceByNameLang / priceByCNLang  → mappe per chunk embedding
 *   - priceRows                        → array per saveCardtraderPrices
 */
function buildPriceData(catalog, expansionCode, blueprints, products) {
  const langKey   = LANG_KEYS[catalog]   ?? "yugioh_language";
  const rarityKey = RARITY_KEYS[catalog] ?? "yugioh_rarity";

  const priceByNameLang = new Map();
  const priceByCNLang   = new Map();
  const priceRows       = [];
  const now             = new Date().toISOString();

  const cnByBpId = new Map();
  for (const bp of blueprints) {
    if (!bp.id) continue;
    const props = bp.fixed_properties ?? bp.properties_hash ?? {};
    const cn = ((bp.collector_number ?? props.collector_number ?? props.number) ?? "")
      .toString().trim();
    cnByBpId.set(bp.id, cn);
  }

  for (const [bpIdStr, listings] of Object.entries(products)) {
    const bpId = parseInt(bpIdStr, 10);
    if (!bpId || !Array.isArray(listings) || listings.length === 0) continue;

    const cardNameEn = (listings[0].name_en ?? "").trim().toLowerCase();
    if (!cardNameEn) continue;

    const firstPh = listings[0].properties_hash ?? {};
    const collectorNumber = (
      listings[0].collector_number ?? firstPh.collector_number ??
      firstPh.number ?? cnByBpId.get(bpId) ?? ""
    ).toString().trim().toLowerCase();

    const nmPrices  = new Map();
    const anyPrices = new Map();
    const rarityMap = new Map();

    for (const listing of listings) {
      const ph = listing.properties_hash ?? {};
      const lang     = normalizeLang(ph[langKey] ?? "en");
      const isFirst  = ph.first_edition === true ? 1 : 0;
      const rarity   = (ph[rarityKey] ?? "").toLowerCase();
      const condition = ph.condition ?? "";
      const priceCents = listing.price_cents;
      if (!priceCents || priceCents <= 0) continue;

      const key = `${lang}|${isFirst}|${rarity}`;
      rarityMap.set(key, rarity);

      const any = anyPrices.get(key) ?? [];
      any.push(priceCents);
      anyPrices.set(key, any);

      const isNm =
        condition.includes("Near Mint") ||
        (condition.includes("Mint") && !condition.includes("Moderately"));
      if (isNm) {
        const nm = nmPrices.get(key) ?? [];
        nm.push(priceCents);
        nmPrices.set(key, nm);
      }
    }

    for (const [key, any] of anyPrices) {
      const parts   = key.split("|");
      const lang    = parts[0];
      const isFirst = parts[1] === "1";
      const rarity  = rarityMap.get(key) ?? "";
      const nm      = nmPrices.get(key);

      const minNmCents  = nm?.length ? Math.min(...nm) : null;
      const minAnyCents = Math.min(...any);
      const bestCents   = minNmCents ?? minAnyCents;
      const price       = Math.round(bestCents) / 100;

      // Mappe per chunk embedding
      const nameKey = `${expansionCode}|${cardNameEn}|${lang}`;
      if (!priceByNameLang.has(nameKey) || price < priceByNameLang.get(nameKey)) {
        priceByNameLang.set(nameKey, price);
      }
      if (collectorNumber) {
        const cnKey = `${expansionCode}|${collectorNumber}|${lang}`;
        if (!priceByCNLang.has(cnKey) || price < priceByCNLang.get(cnKey)) {
          priceByCNLang.set(cnKey, price);
        }
      }

      // Riga per cardtrader_prices collection
      priceRows.push({
        blueprint_id:       bpId,
        catalog:            catalog,
        expansion_code:     expansionCode,
        card_name_en:       cardNameEn,
        language:           lang,
        first_edition:      isFirst ? 1 : 0,
        rarity:             rarity,
        collector_number:   collectorNumber,
        min_price_nm_cents: minNmCents,
        min_price_any_cents:minAnyCents,
        listing_count:      any.length,
        synced_at:          now,
      });
    }
  }

  return { priceByNameLang, priceByCNLang, priceRows };
}

// ─── Firestore: salva prezzi grezzi (tutti i cataloghi) ───────────────────────

/**
 * Replica FirestoreService.saveCardtraderPrices() in Dart.
 * Salva i prezzi in `cardtrader_prices/{catalog}/chunks/{start}`.
 */
async function saveCardtraderPrices(catalog, priceRows) {
  if (priceRows.length === 0) return;
  const ref = db.collection("cardtrader_prices").doc(catalog);

  // Elimina chunk esistenti in batch da 400
  const oldChunks = await ref.collection("chunks").listDocuments();
  const MAX_BATCH = 400;
  for (let i = 0; i < oldChunks.length; i += MAX_BATCH) {
    const batch = db.batch();
    for (const doc of oldChunks.slice(i, i + MAX_BATCH)) batch.delete(doc);
    await batch.commit();
  }

  // Scrivi nuovi chunk
  for (let i = 0; i < priceRows.length; i += CT_PRICE_CHUNK_SIZE * MAX_BATCH) {
    const batch = db.batch();
    for (
      let start = i;
      start < Math.min(i + CT_PRICE_CHUNK_SIZE * MAX_BATCH, priceRows.length);
      start += CT_PRICE_CHUNK_SIZE
    ) {
      const slice = priceRows.slice(start, start + CT_PRICE_CHUNK_SIZE);
      batch.set(ref.collection("chunks").doc(`${start}`), { rows: slice });
    }
    await batch.commit();
  }

  await ref.set({
    catalog,
    count: priceRows.length,
    syncedAt: FieldValue.serverTimestamp(),
  });
}

// ─── Firestore: embeds prezzi nei catalog chunks (yugioh/pokemon/onepiece) ────

async function syncPricesToCatalogChunks(catalog, priceByNameLang, priceByCNLang) {
  const catalogCollection = `${catalog}_catalog`;

  const metaDoc = await db.collection(catalogCollection).doc("metadata").get();
  if (!metaDoc.exists) throw new Error(`Metadati ${catalog}_catalog non trovati`);
  const totalChunks = metaDoc.data()?.totalChunks ?? 0;
  if (totalChunks === 0) throw new Error(`Catalogo ${catalog} vuoto su Firestore`);

  console.log(`  📦 ${totalChunks} chunk da aggiornare…`);

  let updatedPrices = 0;
  let modifiedChunks = 0;
  const modifiedChunkIds = [];

  for (let i = 0; i < totalChunks; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    const chunkRef = db
      .collection(catalogCollection)
      .doc("chunks")
      .collection("items")
      .doc(chunkId);

    const snap = await chunkRef.get();
    if (!snap.exists) continue;

    const rawCards = snap.data()?.cards ?? [];
    let chunkModified = false;

    const updatedCards = rawCards.map((card) => {
      const c = { ...card };
      let cardModified = false;

      switch (catalog) {
        // ── Yu-Gi-Oh! ──────────────────────────────────────────────────────
        case "yugioh": {
          const nameEn = (c.name ?? "").toLowerCase();
          if (!c.sets || typeof c.sets !== "object") break;
          const newSets = {};
          for (const [langKey, arr] of Object.entries(c.sets)) {
            const lang   = langKey.toLowerCase();
            const ctLang = lang === "sp" ? "es" : lang;
            if (!Array.isArray(arr)) { newSets[langKey] = arr; continue; }
            newSets[langKey] = arr.map((s) => {
              const rawCode = (s.set_code ?? "").toUpperCase();
              const expCode = rawCode.includes("-")
                ? rawCode.split("-")[0].toLowerCase()
                : rawCode.toLowerCase();
              let price = priceByNameLang.get(`${expCode}|${nameEn}|${ctLang}`);
              if (price == null) {
                const cn = rawCode.includes("-")
                  ? rawCode.split("-").pop().toLowerCase() : "";
                if (cn) price = priceByCNLang.get(`${expCode}|${cn}|${ctLang}`);
              }
              if (price != null) { cardModified = true; updatedPrices++; return { ...s, set_price: price }; }
              return s;
            });
          }
          if (cardModified) c.sets = newSets;
          break;
        }

        // ── Pokémon ────────────────────────────────────────────────────────
        case "pokemon": {
          const nameEn = (c.name ?? "").toLowerCase();
          if (c.sets && typeof c.sets === "object" && !Array.isArray(c.sets)) {
            const newSets = {};
            for (const [langKey, arr] of Object.entries(c.sets)) {
              const lang = langKey.toLowerCase();
              if (!Array.isArray(arr)) { newSets[langKey] = arr; continue; }
              newSets[langKey] = arr.map((s) => {
                const rawCode  = (s.set_code ?? "").toLowerCase();
                const lastDash = rawCode.lastIndexOf("-");
                const expCode  = lastDash > 0 ? rawCode.slice(0, lastDash) : rawCode;
                if (!expCode) return s;
                const price = priceByNameLang.get(`${expCode}|${nameEn}|${lang}`);
                if (price != null) { cardModified = true; updatedPrices++; return { ...s, set_price: price }; }
                return s;
              });
            }
            if (cardModified) c.sets = newSets;
          } else if (Array.isArray(c.prints)) {
            const pokeLangCols = {
              en: "set_price", it: "set_price_it", fr: "set_price_fr",
              de: "set_price_de", es: "set_price_es", pt: "set_price_pt",
            };
            c.prints = c.prints.map((p) => {
              const expCode = (p.set_code ?? "").toLowerCase();
              if (!expCode) return p;
              const updated = { ...p };
              let printModified = false;
              for (const [lang, field] of Object.entries(pokeLangCols)) {
                const price = priceByNameLang.get(`${expCode}|${nameEn}|${lang}`);
                if (price != null) { updated[field] = price; printModified = true; updatedPrices++; }
              }
              if (printModified) cardModified = true;
              return updated;
            });
          }
          break;
        }

        // ── One Piece ──────────────────────────────────────────────────────
        case "onepiece": {
          const nameEn = (c.name ?? "").toLowerCase();
          if (!Array.isArray(c.prints)) break;
          const opLangFields = {
            ja: "market_price", en: "market_price_en",
            fr: "market_price_fr", ko: "market_price_ko", zh: "market_price_zh",
          };
          c.prints = c.prints.map((p) => {
            const expCode = (p.set_id ?? "").toLowerCase();
            if (!expCode) return p;
            const updated = { ...p };
            let printModified = false;
            for (const [lang, field] of Object.entries(opLangFields)) {
              const price = priceByNameLang.get(`${expCode}|${nameEn}|${lang}`);
              if (price != null) { updated[field] = price; printModified = true; updatedPrices++; }
            }
            if (printModified) { cardModified = true; return updated; }
            return p;
          });
          break;
        }
      }

      if (cardModified) chunkModified = true;
      return c;
    });

    if (chunkModified) {
      await chunkRef.set({ cards: updatedCards });
      modifiedChunkIds.push(chunkId);
      modifiedChunks++;
      process.stdout.write(
        `\r  ✏️  Chunk ${modifiedChunks}/${totalChunks} modificati (prezzi: ${updatedPrices})`
      );
    }
  }

  console.log();

  if (modifiedChunks > 0) {
    await db.collection(catalogCollection).doc("metadata").set(
      {
        lastUpdated:          FieldValue.serverTimestamp(),
        updatedBy:            "price-sync-script",
        pricesSyncedAt:       FieldValue.serverTimestamp(),
        priceModifiedChunks:  modifiedChunkIds,
      },
      { merge: true }
    );
  }

  return { modifiedChunks, totalChunks, updatedPrices };
}

// ─── Set code da Firestore (per cataloghi senza chunk embedding) ──────────────

async function getSetCodesFromFirestore(catalog) {
  const catalogCollection = `${catalog}_catalog`;
  const metaSnap = await db.collection(catalogCollection).doc("metadata").get();
  const totalChunks = metaSnap.exists ? (metaSnap.data()?.totalChunks ?? 0) : 0;
  const codes = new Set();
  for (let i = 0; i < totalChunks; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    const snap = await db
      .collection(catalogCollection).doc("chunks").collection("items").doc(chunkId)
      .get();
    if (!snap.exists) continue;
    for (const code of extractSetCodesFromCards(snap.data()?.cards ?? [], catalog))
      codes.add(code);
  }
  return { codes, totalChunks };
}

// ─── Sync singolo catalogo ────────────────────────────────────────────────────

async function syncCatalog(catalog) {
  const gameId = GAME_IDS[catalog];
  if (!gameId) {
    console.log(`\n⏩ ${catalog.toUpperCase()} — nessun game ID CardTrader, salto.`);
    return;
  }

  console.log(`\n${"─".repeat(60)}`);
  console.log(`🎴  ${catalog.toUpperCase()}  (game_id=${gameId})`);
  console.log(`${"─".repeat(60)}`);

  // 1. Espansioni CT
  process.stdout.write("  ↳ Carico espansioni CT… ");
  const ctExpansions = await fetchExpansions(gameId);
  console.log(`${ctExpansions.length} trovate`);

  // 2. Set code dal catalogo Firestore
  process.stdout.write("  ↳ Leggo set code da Firestore… ");
  const { codes: localCodes, totalChunks } = await getSetCodesFromFirestore(catalog);
  console.log(`${localCodes.size} set, ${totalChunks} chunk`);

  if (localCodes.size === 0) {
    console.log("  ⚠️  Catalogo non trovato su Firestore. Salto.");
    return;
  }

  // 3. Match CT ↔ locale
  const ctToLocal  = buildExpansionMap(ctExpansions, localCodes);
  const matched    = ctExpansions.filter((e) => ctToLocal.has((e.code ?? "").toLowerCase()));
  console.log(`  ↳ Corrispondenze: ${matched.length}/${ctExpansions.length}`);

  if (matched.length === 0) {
    console.log("  ⚠️  Nessuna corrispondenza. Salto.");
    return;
  }

  // 4. Scarica prezzi CT per ogni espansione abbinata
  const globalNameMap = new Map();
  const globalCnMap   = new Map();
  const allPriceRows  = [];
  let errors  = 0;
  let skipped = 0;

  for (let i = 0; i < matched.length; i++) {
    const exp       = matched[i];
    const ctCode    = (exp.code ?? "").toLowerCase();
    const localCode = ctToLocal.get(ctCode);
    const expName   = exp.name ?? ctCode;

    process.stdout.write(
      `\r  ↳ [${i + 1}/${matched.length}] ${expName.slice(0, 35).padEnd(35)} `
    );

    try {
      const [blueprints, products] = await Promise.all([
        fetchBlueprints(exp.id),
        fetchMarketplaceProducts(exp.id),
      ]);

      if (Object.keys(products).length === 0) {
        skipped++;
      } else {
        const { priceByNameLang, priceByCNLang, priceRows } =
          buildPriceData(catalog, localCode, blueprints, products);

        for (const [k, v] of priceByNameLang)
          if (!globalNameMap.has(k) || v < globalNameMap.get(k)) globalNameMap.set(k, v);
        for (const [k, v] of priceByCNLang)
          if (!globalCnMap.has(k) || v < globalCnMap.get(k)) globalCnMap.set(k, v);
        allPriceRows.push(...priceRows);
      }
    } catch (e) {
      errors++;
    }

    await sleep(DELAY_MS);
  }

  console.log(
    `\n  ↳ Prezzi: ${allPriceRows.length} righe (${skipped} senza listing, ${errors} errori)`
  );

  if (allPriceRows.length === 0) {
    console.log("  ⚠️  Nessun prezzo raccolto. Salto salvataggio.");
    return;
  }

  // 5. Salva prezzi grezzi in cardtrader_prices/{catalog} (tutti i cataloghi)
  process.stdout.write("  ↳ Salvo prezzi grezzi su Firestore… ");
  await saveCardtraderPrices(catalog, allPriceRows);
  console.log("✓");

  // 6. Per yugioh/pokemon/onepiece: embeds prezzi nei catalog chunks
  if (CHUNK_EMBED_CATALOGS.has(catalog)) {
    console.log("  ↳ Aggiorno chunk catalogo…");
    const result = await syncPricesToCatalogChunks(catalog, globalNameMap, globalCnMap);
    console.log(
      `  ✅ ${result.modifiedChunks}/${result.totalChunks} chunk · ${result.updatedPrices} prezzi embedded`
    );
  } else {
    console.log(`  ✅ Prezzi salvati in cardtrader_prices/${catalog}`);
  }
}

// ─── Magic: sync prezzi da Scryfall ──────────────────────────────────────────

const SCRYFALL_HEADERS = {
  Accept: "application/json",
  "User-Agent": "DeckMaster/1.0 (g.favara.dev@gmail.com)",
};

/**
 * Scarica i prezzi EUR da Scryfall (oracle_cards bulk data) e li salva
 * in `cardtrader_prices/magic` con schema { api_id, price_eur, price_eur_foil }.
 *
 * Usa la stessa collection/chunk structure di saveCardtraderPrices() così
 * il client li legge con getCardtraderPricesSyncedAt / fetchCardtraderPriceRows.
 */
async function syncMagicPrices() {
  console.log(`\n${"─".repeat(60)}`);
  console.log(`✨  MAGIC (Scryfall oracle_cards)`);
  console.log(`${"─".repeat(60)}`);

  // 1. Recupera URL del bulk data
  process.stdout.write("  ↳ Recupero indice bulk-data Scryfall… ");
  const bulkRes = await fetch("https://api.scryfall.com/bulk-data", {
    headers: SCRYFALL_HEADERS,
  });
  if (!bulkRes.ok) throw new Error(`Scryfall bulk-data HTTP ${bulkRes.status}`);
  const bulkJson = await bulkRes.json();
  const oracleEntry = (bulkJson.data ?? []).find((e) => e.type === "oracle_cards");
  if (!oracleEntry) throw new Error("oracle_cards non trovato nell'indice Scryfall");
  console.log(`trovato (${(oracleEntry.size / 1024 / 1024).toFixed(0)} MB)`);

  // 2. Scarica il file bulk (~100 MB)
  process.stdout.write("  ↳ Download bulk data… ");
  const dataRes = await fetch(oracleEntry.download_uri, { headers: SCRYFALL_HEADERS });
  if (!dataRes.ok) throw new Error(`Download bulk data HTTP ${dataRes.status}`);
  const rawList = await dataRes.json();
  console.log(`${rawList.length} carte ricevute`);

  // 3. Estrai solo api_id + price_eur + price_eur_foil
  process.stdout.write("  ↳ Estrazione prezzi… ");
  const priceRows = [];
  for (const raw of rawList) {
    const layout = raw.layout ?? "";
    if (layout === "token" || layout === "emblem" || layout === "art_series") continue;
    if ((raw.lang ?? "en") !== "en") continue;

    const prices = raw.prices ?? {};
    const priceEur     = parseFloat(prices.eur)      || null;
    const priceEurFoil = parseFloat(prices.eur_foil) || null;
    if (priceEur === null && priceEurFoil === null) continue;

    priceRows.push({
      api_id:         raw.id,
      price_eur:      priceEur,
      price_eur_foil: priceEurFoil,
    });
  }
  console.log(`${priceRows.length} carte con prezzo`);

  if (priceRows.length === 0) {
    console.log("  ⚠️  Nessun prezzo. Salto salvataggio.");
    return;
  }

  // 4. Salva in cardtrader_prices/magic (stessa struttura degli altri cataloghi)
  process.stdout.write("  ↳ Salvo prezzi su Firestore… ");
  await saveCardtraderPrices("magic", priceRows);
  console.log("✓");
  console.log(`  ✅ ${priceRows.length} prezzi Magic salvati in cardtrader_prices/magic`);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const catalogsArg =
    args.find((a) => a.startsWith("--catalogs="))?.slice(11) ??
    (args.includes("--catalogs") ? args[args.indexOf("--catalogs") + 1] : null) ??
    process.env.CATALOGS ??
    null;
  const catalogs = catalogsArg
    ? catalogsArg.split(",").map((s) => s.trim()).filter(Boolean)
    : ALL_CATALOGS;

  const startedAt = new Date();
  console.log(`\n🚀 Deck Master — Price Sync`);
  console.log(`📅 ${startedAt.toISOString()}`);
  console.log(`📚 Cataloghi (${catalogs.length}): ${catalogs.join(", ")}`);

  let totalErrors = 0;
  for (const catalog of catalogs) {
    try {
      if (catalog === "magic") {
        await syncMagicPrices();
      } else {
        await syncCatalog(catalog);
      }
    } catch (e) {
      console.error(`\n❌ Errore ${catalog}:`, e.message);
      totalErrors++;
    }
  }

  const elapsed = ((Date.now() - startedAt) / 1000 / 60).toFixed(1);
  console.log(`\n${"═".repeat(60)}`);
  console.log(
    `🏁 Completato in ${elapsed} min${totalErrors > 0 ? ` — ⚠️ ${totalErrors} catalogo/i con errori` : " ✓"}`
  );
  console.log(`${"═".repeat(60)}\n`);

  process.exit(totalErrors > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("❌ Errore fatale:", e);
  process.exit(1);
});
