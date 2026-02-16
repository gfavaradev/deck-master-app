/**
 * Script per popolare il catalogo Yu-Gi-Oh su Firestore (multilingue).
 *
 * Replica il comportamento del backend Node.js/Prisma:
 * 1. Scarica carte EN (base) con prints e prezzi
 * 2. Scarica IT/FR/DE/PT per traduzioni name/description
 * 3. Genera traduzioni print: set_code localizzato + rarity tradotta
 * 4. Prezzi salvati per lingua (stessi valori EN)
 *
 * Uso:
 *   1. Scaricare la service account key da Firebase Console
 *   2. Salvare come serviceAccountKey.json in questa cartella
 *   3. npm install
 *   4. npm start
 */

import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { readFileSync } from "fs";

// Config
const YGOPRODECK_API = "https://db.ygoprodeck.com/api/v7/cardinfo.php";
const MAX_CHUNK_BYTES = 900_000;
const PAGE_SIZE = 500;
const LANGUAGES = ["it", "fr", "de", "pt"];
const SUPPORTED_LANGS = ["EN", "IT", "FR", "DE", "PT"];

// Prefissi lingua a 2 lettere noti nei set code
const KNOWN_LANG_PREFIXES = [
  "EN", "IT", "FR", "DE", "PT", "ES", "SP", "JP", "JA", "KR", "KO",
];

// Prefissi lingua a 1 lettera (es. SDY-E006 → SDY-I006)
const LANG_PREFIX_1 = { EN: "E", IT: "I", FR: "F", DE: "D", PT: "P" };

// Traduzione rarità per lingua (dal backend originale)
const RARITY_TRANSLATIONS = {
  IT: {
    Common: "Comune", Rare: "Rara", "Super Rare": "Super Rara",
    "Ultra Rare": "Ultra Rara", "Secret Rare": "Rara Segreta",
    "Ultimate Rare": "Rara Ultimate", "Ghost Rare": "Rara Fantasma",
    "Ghost/Gold Rare": "Rara Fantasma/Oro", "Gold Rare": "Rara Oro",
    "Gold Secret Rare": "Rara Segreta Oro", "Platinum Rare": "Rara Platino",
    "Platinum Secret Rare": "Rara Segreta Platino",
    "Premium Gold Rare": "Rara Oro Premium",
    "Prismatic Secret Rare": "Rara Segreta Prismatica",
    "Starfoil Rare": "Rara Starfoil", "Starlight Rare": "Rara Starlight",
    "Shatterfoil Rare": "Rara Shatterfoil", "Mosaic Rare": "Rara Mosaico",
    "Collector's Rare": "Rara da Collezione",
    "Normal Parallel Rare": "Rara Parallela Normale",
    "Super Parallel Rare": "Super Rara Parallela",
    "Ultra Parallel Rare": "Ultra Rara Parallela",
    "Quarter Century Secret Rare": "Rara Segreta Quarto di Secolo",
    "Extra Secret Rare": "Rara Segreta Extra", "Extra Secret": "Segreta Extra",
    "Ultra Secret Rare": "Ultra Rara Segreta",
    "Ultra Rare (Pharaoh's Rare)": "Ultra Rara (Rarità del Faraone)",
    "Duel Terminal Normal Parallel Rare": "Rara Parallela Normale Duel Terminal",
    "Duel Terminal Normal Rare Parallel Rare": "Rara Parallela Rara Duel Terminal",
    "Duel Terminal Rare Parallel Rare": "Rara Parallela Duel Terminal",
    "Duel Terminal Super Parallel Rare": "Super Rara Parallela Duel Terminal",
    "Duel Terminal Ultra Parallel Rare": "Ultra Rara Parallela Duel Terminal",
    "10000 Secret Rare": "Rara Segreta 10000",
    "Short Print": "Tiratura Limitata", "Super Short Print": "Tiratura Molto Limitata",
    Starfoil: "Starfoil", Reprint: "Ristampa", New: "Novità",
    "New artwork": "Nuova illustrazione",
    "European & Oceanian debut": "Debutto Europeo e Oceaniano",
    "European debut": "Debutto Europeo", "Oceanian debut": "Debutto Oceaniano",
  },
  FR: {
    Common: "Commune", Rare: "Rare", "Super Rare": "Super Rare",
    "Ultra Rare": "Ultra Rare", "Secret Rare": "Rare Secrète",
    "Ultimate Rare": "Rare Ultime", "Ghost Rare": "Rare Fantôme",
    "Ghost/Gold Rare": "Rare Fantôme/Or", "Gold Rare": "Rare Or",
    "Gold Secret Rare": "Rare Secrète Or", "Platinum Rare": "Rare Platine",
    "Platinum Secret Rare": "Rare Secrète Platine",
    "Premium Gold Rare": "Rare Or Premium",
    "Prismatic Secret Rare": "Rare Secrète Prismatique",
    "Starfoil Rare": "Rare Starfoil", "Starlight Rare": "Rare Starlight",
    "Shatterfoil Rare": "Rare Shatterfoil", "Mosaic Rare": "Rare Mosaïque",
    "Collector's Rare": "Rare de Collection",
    "Normal Parallel Rare": "Rare Parallèle Normale",
    "Super Parallel Rare": "Super Rare Parallèle",
    "Ultra Parallel Rare": "Ultra Rare Parallèle",
    "Quarter Century Secret Rare": "Rare Secrète Quart de Siècle",
    "Extra Secret Rare": "Rare Secrète Extra", "Extra Secret": "Secrète Extra",
    "Ultra Secret Rare": "Ultra Rare Secrète",
    "Ultra Rare (Pharaoh's Rare)": "Ultra Rare (Rare du Pharaon)",
    "Duel Terminal Normal Parallel Rare": "Rare Parallèle Normale Duel Terminal",
    "Duel Terminal Normal Rare Parallel Rare": "Rare Parallèle Duel Terminal",
    "Duel Terminal Rare Parallel Rare": "Rare Parallèle Duel Terminal",
    "Duel Terminal Super Parallel Rare": "Super Rare Parallèle Duel Terminal",
    "Duel Terminal Ultra Parallel Rare": "Ultra Rare Parallèle Duel Terminal",
    "10000 Secret Rare": "Rare Secrète 10000",
    "Short Print": "Tirage Limité", "Super Short Print": "Tirage Très Limité",
    Starfoil: "Starfoil", Reprint: "Réimpression", New: "Nouveau",
    "New artwork": "Nouvelle illustration",
    "European & Oceanian debut": "Début Européen et Océanien",
    "European debut": "Début Européen", "Oceanian debut": "Début Océanien",
  },
  DE: {
    Common: "Häufig", Rare: "Selten", "Super Rare": "Super Selten",
    "Ultra Rare": "Ultra Selten", "Secret Rare": "Geheim Selten",
    "Ultimate Rare": "Ultimativ Selten", "Ghost Rare": "Geist Selten",
    "Ghost/Gold Rare": "Geist/Gold Selten", "Gold Rare": "Gold Selten",
    "Gold Secret Rare": "Gold Geheim Selten", "Platinum Rare": "Platin Selten",
    "Platinum Secret Rare": "Platin Geheim Selten",
    "Premium Gold Rare": "Premium Gold Selten",
    "Prismatic Secret Rare": "Prismatisch Geheim Selten",
    "Starfoil Rare": "Starfoil Selten", "Starlight Rare": "Starlight Selten",
    "Shatterfoil Rare": "Shatterfoil Selten", "Mosaic Rare": "Mosaik Selten",
    "Collector's Rare": "Sammler Selten",
    "Normal Parallel Rare": "Normal Parallel Selten",
    "Super Parallel Rare": "Super Parallel Selten",
    "Ultra Parallel Rare": "Ultra Parallel Selten",
    "Quarter Century Secret Rare": "Vierteljahrhundert Geheim Selten",
    "Extra Secret Rare": "Extra Geheim Selten", "Extra Secret": "Extra Geheim",
    "Ultra Secret Rare": "Ultra Geheim Selten",
    "Ultra Rare (Pharaoh's Rare)": "Ultra Selten (Pharao Selten)",
    "Duel Terminal Normal Parallel Rare": "Duel Terminal Normal Parallel Selten",
    "Duel Terminal Normal Rare Parallel Rare": "Duel Terminal Parallel Selten",
    "Duel Terminal Rare Parallel Rare": "Duel Terminal Parallel Selten",
    "Duel Terminal Super Parallel Rare": "Duel Terminal Super Parallel Selten",
    "Duel Terminal Ultra Parallel Rare": "Duel Terminal Ultra Parallel Selten",
    "10000 Secret Rare": "10000 Geheim Selten",
    "Short Print": "Kurzauflage", "Super Short Print": "Sehr Kurzauflage",
    Starfoil: "Starfoil", Reprint: "Nachdruck", New: "Neu",
    "New artwork": "Neues Artwork",
    "European & Oceanian debut": "Europäisches & Ozeanisches Debüt",
    "European debut": "Europäisches Debüt", "Oceanian debut": "Ozeanisches Debüt",
  },
  PT: {
    Common: "Comum", Rare: "Rara", "Super Rare": "Super Rara",
    "Ultra Rare": "Ultra Rara", "Secret Rare": "Rara Secreta",
    "Ultimate Rare": "Rara Ultimate", "Ghost Rare": "Rara Fantasma",
    "Ghost/Gold Rare": "Rara Fantasma/Ouro", "Gold Rare": "Rara Ouro",
    "Gold Secret Rare": "Rara Secreta Ouro", "Platinum Rare": "Rara Platina",
    "Platinum Secret Rare": "Rara Secreta Platina",
    "Premium Gold Rare": "Rara Ouro Premium",
    "Prismatic Secret Rare": "Rara Secreta Prismática",
    "Starfoil Rare": "Rara Starfoil", "Starlight Rare": "Rara Starlight",
    "Shatterfoil Rare": "Rara Shatterfoil", "Mosaic Rare": "Rara Mosaico",
    "Collector's Rare": "Rara de Coleção",
    "Normal Parallel Rare": "Rara Paralela Normal",
    "Super Parallel Rare": "Super Rara Paralela",
    "Ultra Parallel Rare": "Ultra Rara Paralela",
    "Quarter Century Secret Rare": "Rara Secreta Quarto de Século",
    "Extra Secret Rare": "Rara Secreta Extra", "Extra Secret": "Secreta Extra",
    "Ultra Secret Rare": "Ultra Rara Secreta",
    "Ultra Rare (Pharaoh's Rare)": "Ultra Rara (Raridade do Faraó)",
    "Duel Terminal Normal Parallel Rare": "Rara Paralela Normal Duel Terminal",
    "Duel Terminal Normal Rare Parallel Rare": "Rara Paralela Duel Terminal",
    "Duel Terminal Rare Parallel Rare": "Rara Paralela Duel Terminal",
    "Duel Terminal Super Parallel Rare": "Super Rara Paralela Duel Terminal",
    "Duel Terminal Ultra Parallel Rare": "Ultra Rara Paralela Duel Terminal",
    "10000 Secret Rare": "Rara Secreta 10000",
    "Short Print": "Tiragem Limitada", "Super Short Print": "Tiragem Muito Limitada",
    Starfoil: "Starfoil", Reprint: "Reimpressão", New: "Novo",
    "New artwork": "Nova ilustração",
    "European & Oceanian debut": "Estreia Europeia e Oceânica",
    "European debut": "Estreia Europeia", "Oceanian debut": "Estreia Oceânica",
  },
};

// Init Firebase Admin
const serviceAccount = JSON.parse(
  readFileSync(new URL("./serviceAccountKey.json", import.meta.url), "utf-8")
);

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

// ─── Utility functions ───

function convertSetCodeLang(setCode, targetLang) {
  setCode = setCode.trim().toUpperCase();
  const match = setCode.match(/^([A-Z0-9]+)-([A-Z]*)(\d+.*)$/);
  if (!match) return setCode;
  const [_, prefix, letters, numSuffix] = match;
  if (letters.length === 2 && KNOWN_LANG_PREFIXES.includes(letters)) {
    return `${prefix}-${targetLang}${numSuffix}`;
  }
  if (letters.length === 1) {
    return `${prefix}-${LANG_PREFIX_1[targetLang] || letters}${numSuffix}`;
  }
  return setCode;
}

function extractRarityCode(rarity) {
  return rarity.split(" ").map((w) => w[0]).join("").toUpperCase();
}

function stripNulls(obj) {
  const result = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value != null) result[key] = value;
  }
  return result;
}

// ─── Main ───

async function main() {
  console.log("=== Populate Yu-Gi-Oh Catalog on Firestore (Multilingual) ===\n");

  // Step 1: Fetch EN cards (base)
  console.log("Step 1: Fetching EN cards (base)...");
  const enCards = await fetchAllCards();
  console.log(`  EN total: ${enCards.length} cards\n`);

  if (enCards.length === 0) {
    console.log("No cards found. Exiting.");
    process.exit(1);
  }

  // Step 2: Fetch translations
  console.log("Step 2: Fetching translations...");
  const translations = {};
  for (const lang of LANGUAGES) {
    console.log(`  Fetching ${lang.toUpperCase()}...`);
    const langCards = await fetchAllCards(lang);
    console.log(`  ${lang.toUpperCase()} total: ${langCards.length} cards`);
    translations[lang.toUpperCase()] = new Map();
    for (const card of langCards) {
      translations[lang.toUpperCase()].set(card.id, {
        name: card.name || "",
        desc: card.desc || "",
      });
    }
  }
  console.log();

  // Step 3: Transform with full backend logic
  console.log("Step 3: Transforming cards...");
  const transformedCards = enCards.map((c) => transformCard(c, translations));

  let withTranslations = 0;
  for (const card of transformedCards) {
    if (card.name_it || card.name_fr || card.name_de || card.name_pt) withTranslations++;
  }
  console.log(`  Transformed: ${transformedCards.length} cards`);
  console.log(`  With translations: ${withTranslations} cards\n`);

  // Step 4: Split into chunks based on byte size
  const chunks = [];
  let currentChunk = [];
  let currentSize = 0;
  for (const card of transformedCards) {
    const cardSize = Buffer.byteLength(JSON.stringify(card), "utf-8");
    if (currentChunk.length > 0 && currentSize + cardSize > MAX_CHUNK_BYTES) {
      chunks.push(currentChunk);
      currentChunk = [];
      currentSize = 0;
    }
    currentChunk.push(card);
    currentSize += cardSize;
  }
  if (currentChunk.length > 0) chunks.push(currentChunk);
  console.log(`Step 4: Split into ${chunks.length} chunks (size-based, max ~${Math.round(MAX_CHUNK_BYTES / 1024)}KB)\n`);

  // Step 5: Upload to Firestore
  console.log("Step 5: Uploading to Firestore...");
  for (let i = 0; i < chunks.length; i++) {
    const chunkId = `chunk_${String(i + 1).padStart(3, "0")}`;
    await db.collection("yugioh_catalog").doc("chunks").collection("items").doc(chunkId).set({ cards: chunks[i] });
    console.log(`  Uploaded ${chunkId} (${chunks[i].length} cards) [${i + 1}/${chunks.length}]`);
  }

  // Step 6: Write metadata
  console.log("\nStep 6: Writing metadata...");
  await db.collection("yugioh_catalog").doc("metadata").set({
    totalCards: transformedCards.length,
    totalChunks: chunks.length,
    languages: SUPPORTED_LANGS,
    lastUpdated: FieldValue.serverTimestamp(),
    version: 3,
  });

  console.log(`\n=== Done! ${transformedCards.length} cards in ${chunks.length} chunks (5 languages) ===`);
  process.exit(0);
}

async function fetchAllCards(lang = null) {
  const allCards = [];
  let offset = 0;
  let hasMore = true;
  while (hasMore) {
    let url = `${YGOPRODECK_API}?misc=yes&num=${PAGE_SIZE}&offset=${offset}`;
    if (lang) url += `&language=${lang}`;
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status} fetching ${lang || "en"} at offset ${offset}`);
    const data = await response.json();
    const cards = data.data || [];
    allCards.push(...cards);
    const remaining = (data.meta?.total_rows || 0) - (offset + cards.length);
    if (cards.length < PAGE_SIZE || remaining <= 0) hasMore = false;
    else offset += cards.length;
  }
  return allCards;
}

/**
 * Transform card replicating backend behavior:
 * - Card: EN base + name/desc translations
 * - Prints: EN + localized set_code + translated rarity per lang
 * - Prices: per print, per language (same EN values replicated)
 */
function transformCard(apiCard, translations) {
  const itData = translations.IT?.get(apiCard.id);
  const frData = translations.FR?.get(apiCard.id);
  const deData = translations.DE?.get(apiCard.id);
  const ptData = translations.PT?.get(apiCard.id);

  const card = stripNulls({
    id: apiCard.id,
    type: apiCard.type || "",
    human_readable_type: apiCard.humanReadableCardType || apiCard.type || "",
    frame_type: apiCard.frameType || "",
    race: apiCard.race || "",
    archetype: apiCard.archetype || null,
    ygoprodeck_url: apiCard.ygoprodeck_url || null,
    atk: apiCard.atk ?? null,
    def: apiCard.def ?? null,
    level: apiCard.level ?? null,
    attribute: apiCard.attribute || null,
    scale: apiCard.scale ?? null,
    linkval: apiCard.linkval ?? null,
    linkmarkers: apiCard.linkmarkers ? apiCard.linkmarkers.join(",") : null,
    name: apiCard.name || "",
    description: apiCard.desc || "",
    name_it: itData?.name || null,
    description_it: itData?.desc || null,
    name_fr: frData?.name || null,
    description_fr: frData?.desc || null,
    name_de: deData?.name || null,
    description_de: deData?.desc || null,
    name_pt: ptData?.name || null,
    description_pt: ptData?.desc || null,
  });

  // Process prints with full localization (replicating backend)
  const prints = [];
  const enSets = apiCard.card_sets || [];
  const enImages = apiCard.card_images || [];
  const enPrices = apiCard.card_prices?.[0] || {};
  const artwork = enImages.length > 0 ? enImages[0].image_url_cropped : null;

  for (const set of enSets) {
    const enSetCode = set.set_code || "";
    const enRarity = set.set_rarity || "";
    const enRarityCode = set.set_rarity_code?.replace(/[()]/g, "").trim() || extractRarityCode(enRarity);
    const enSetPrice = parseFloat(set.set_price) || null;

    // Prices: same values for all languages (as backend did)
    const priceData = stripNulls({
      cardmarket_price: parseFloat(enPrices.cardmarket_price) || null,
      tcgplayer_price: parseFloat(enPrices.tcgplayer_price) || null,
      ebay_price: parseFloat(enPrices.ebay_price) || null,
      amazon_price: parseFloat(enPrices.amazon_price) || null,
      coolstuffinc_price: parseFloat(enPrices.coolstuffinc_price) || null,
    });

    const prices = {};
    if (Object.keys(priceData).length > 0) {
      for (const lang of SUPPORTED_LANGS) {
        prices[lang] = priceData;
      }
    }

    const printData = stripNulls({
      // EN base
      set_code: enSetCode,
      set_name: set.set_name || "",
      rarity: enRarity,
      rarity_code: enRarityCode,
      set_price: enSetPrice,
      artwork,
      // IT translations
      set_code_it: convertSetCodeLang(enSetCode, "IT"),
      set_name_it: set.set_name || "",
      rarity_it: (RARITY_TRANSLATIONS.IT[enRarity]) || enRarity,
      rarity_code_it: enRarityCode,
      set_price_it: enSetPrice,
      // FR translations
      set_code_fr: convertSetCodeLang(enSetCode, "FR"),
      set_name_fr: set.set_name || "",
      rarity_fr: (RARITY_TRANSLATIONS.FR[enRarity]) || enRarity,
      rarity_code_fr: enRarityCode,
      set_price_fr: enSetPrice,
      // DE translations
      set_code_de: convertSetCodeLang(enSetCode, "DE"),
      set_name_de: set.set_name || "",
      rarity_de: (RARITY_TRANSLATIONS.DE[enRarity]) || enRarity,
      rarity_code_de: enRarityCode,
      set_price_de: enSetPrice,
      // PT translations
      set_code_pt: convertSetCodeLang(enSetCode, "PT"),
      set_name_pt: set.set_name || "",
      rarity_pt: (RARITY_TRANSLATIONS.PT[enRarity]) || enRarity,
      rarity_code_pt: enRarityCode,
      set_price_pt: enSetPrice,
      // Prices per language
      prices: Object.keys(prices).length > 0 ? prices : null,
    });

    prints.push(printData);
  }

  card.prints = prints;
  return card;
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
