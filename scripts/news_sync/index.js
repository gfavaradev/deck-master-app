/**
 * Daily news sync — Deck Master
 *
 * Per ogni sorgente configurata in sources.js (RSS o HTML):
 *   1. Scarica gli ultimi item
 *   2. Normalizza in {title, body, externalUrl, imageUrl, publishedAt, collections, source, kind}
 *   3. Salta gli item già presenti (dedup su externalUrl, sia in `news` che in `news_drafts`)
 *   4. Scrive i nuovi item in `news_drafts` con status "pending" — la pubblicazione
 *      verso `news` (visibile agli utenti) richiede approvazione admin dalla pagina
 *      "Gestione News" (lib/pages/admin_news_page.dart)
 *
 * Setup:
 *   1. Metti serviceAccountKey.json in questa cartella
 *   2. npm install
 *   3. node index.js
 *
 * Cron (esecuzione giornaliera alle 04:00, sfalsato dopo price_sync):
 *   0 4 * * * cd /path/to/scripts/news_sync && node index.js >> news_sync.log 2>&1
 *
 * Cataloghi specifici:
 *   node index.js --catalogs yugioh
 */

import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import Parser from "rss-parser";
import { SOURCES } from "./sources.js";

// ─── Config ───────────────────────────────────────────────────────────────────

const __dir = dirname(fileURLToPath(import.meta.url));
const DELAY_MS = 300;

const keyPath = resolve(__dir, "serviceAccountKey.json");
if (!existsSync(keyPath)) {
  console.error("❌ serviceAccountKey.json non trovato in scripts/news_sync/");
  process.exit(1);
}

initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, "utf8"))) });
const db = getFirestore();
const rssParser = new Parser({
  requestOptions: {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; DeckMasterNewsBot/1.0)" },
  },
});

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ─── Arg parsing ──────────────────────────────────────────────────────────────

function parseArgs() {
  const arg = process.argv.find((a) => a.startsWith("--catalogs"));
  if (!arg) return null;
  const val = arg.includes("=") ? arg.split("=")[1] : process.argv[process.argv.indexOf(arg) + 1];
  return val ? val.split(",").map((s) => s.trim()) : null;
}

// ─── Normalizzazione ──────────────────────────────────────────────────────────

function extractImageFromHtml(html) {
  if (!html) return null;
  const match = html.match(/<img[^>]+src="([^"]+)"/i);
  return match ? match[1] : null;
}

function normalizeRssItem(item, source) {
  const externalUrl = item.link?.trim();
  if (!externalUrl || !item.title) return null;
  const body = item.contentSnippet || item.content || item.summary || "";
  return {
    title: item.title.trim(),
    body: body.trim(),
    externalUrl,
    imageUrl: item.enclosure?.url ?? extractImageFromHtml(item.content),
    publishedAt: item.pubDate ? Timestamp.fromDate(new Date(item.pubDate)) : Timestamp.now(),
    collections: [source.catalog],
    source: source.sourceName,
    kind: source.kind,
    status: "pending",
  };
}

// ─── Dedup ────────────────────────────────────────────────────────────────────

async function existsByExternalUrl(collectionName, externalUrl) {
  const snap = await db
    .collection(collectionName)
    .where("externalUrl", "==", externalUrl)
    .limit(1)
    .get();
  return !snap.empty;
}

async function alreadyKnown(externalUrl) {
  return (
    (await existsByExternalUrl("news", externalUrl)) ||
    (await existsByExternalUrl("news_drafts", externalUrl))
  );
}

// ─── Fetch per tipo di sorgente ──────────────────────────────────────────────

async function fetchRssSource(source) {
  const feed = await rssParser.parseURL(source.url);
  return (feed.items ?? [])
    .map((item) => normalizeRssItem(item, source))
    .filter(Boolean);
}

async function fetchSource(source) {
  if (source.type === "rss") return fetchRssSource(source);
  console.log(`  ⏩ tipo sorgente "${source.type}" non ancora implementato, salto.`);
  return [];
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function syncCatalog(catalog, sources) {
  console.log(`\n${"─".repeat(60)}`);
  console.log(`📰  ${catalog.toUpperCase()}`);
  console.log(`${"─".repeat(60)}`);

  if (sources.length === 0) {
    console.log("  ⏩ nessuna fonte configurata, salto.");
    return { fetched: 0, written: 0 };
  }

  let fetched = 0;
  let written = 0;

  for (const source of sources) {
    process.stdout.write(`  ↳ ${source.sourceName} (${source.kind})… `);
    let items;
    try {
      items = await fetchSource(source);
    } catch (err) {
      console.log(`errore: ${err.message}`);
      continue;
    }
    fetched += items.length;
    console.log(`${items.length} item`);

    for (const item of items) {
      if (await alreadyKnown(item.externalUrl)) continue;
      await db.collection("news_drafts").add(item);
      written++;
      await sleep(DELAY_MS);
    }
  }

  console.log(`  ✅ ${written} nuovi draft su ${fetched} item totali`);
  return { fetched, written };
}

async function main() {
  const requested = parseArgs();
  const catalogs = requested ?? [...new Set(SOURCES.map((s) => s.catalog))];

  console.log(`🚀 News sync — cataloghi: ${catalogs.join(", ")}`);
  const start = Date.now();
  let totalWritten = 0;

  for (const catalog of catalogs) {
    const sources = SOURCES.filter((s) => s.catalog === catalog);
    const { written } = await syncCatalog(catalog, sources);
    totalWritten += written;
  }

  const seconds = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`\n🏁 Completato in ${seconds}s — ${totalWritten} nuovi draft creati.`);
}

main().catch((err) => {
  console.error("❌ Errore fatale:", err);
  process.exit(1);
});
