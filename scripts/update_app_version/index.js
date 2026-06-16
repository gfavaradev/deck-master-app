/**
 * Aggiorna il documento Firestore app_config/version — Deck Master
 *
 * L'app legge questo documento all'avvio (lib/services/update_service.dart)
 * per mostrare il popup di aggiornamento. Va lanciato ad ogni nuova release.
 *
 * Setup:
 *   1. Metti serviceAccountKey.json in questa cartella
 *   2. npm install
 *
 * Uso:
 *   node index.js --version 1.3.8 --android-url https://play.google.com/store/apps/details?id=com.giuseppe.deckmaster
 *
 * Opzioni:
 *   --version       <x.y.z>   latestVersion (obbligatorio)
 *   --android-url   <url>     androidUrl (obbligatorio)
 *   --windows-url   <url>     windowsUrl (opzionale)
 *   --min-version   <x.y.z>   minVersion, sotto la quale l'update è forzato (opzionale)
 *   --force                   forza l'update anche se latestVersion non supera minVersion
 *   --notes         <testo>   releaseNotes mostrate nel dialog (opzionale)
 */

import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const __dir = dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const out = { force: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--version") out.version = argv[++i];
    else if (a === "--android-url") out.androidUrl = argv[++i];
    else if (a === "--windows-url") out.windowsUrl = argv[++i];
    else if (a === "--min-version") out.minVersion = argv[++i];
    else if (a === "--notes") out.notes = argv[++i];
    else if (a === "--force") out.force = true;
  }
  return out;
}

const SEMVER_RE = /^\d+\.\d+\.\d+$/;

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.version || !SEMVER_RE.test(args.version)) {
    console.error("❌ --version obbligatorio nel formato x.y.z (es. 1.3.8)");
    process.exit(1);
  }
  if (!args.androidUrl) {
    console.error("❌ --android-url obbligatorio");
    process.exit(1);
  }
  if (args.minVersion && !SEMVER_RE.test(args.minVersion)) {
    console.error("❌ --min-version deve essere nel formato x.y.z");
    process.exit(1);
  }

  const keyPath = resolve(__dir, "serviceAccountKey.json");
  if (!existsSync(keyPath)) {
    console.error("❌ serviceAccountKey.json non trovato in scripts/update_app_version/");
    process.exit(1);
  }
  initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, "utf8"))) });
  const db = getFirestore();

  const data = {
    latestVersion: args.version,
    androidUrl: args.androidUrl,
  };
  if (args.windowsUrl) data.windowsUrl = args.windowsUrl;
  if (args.minVersion) data.minVersion = args.minVersion;
  if (args.notes) data.releaseNotes = args.notes;
  if (args.force) data.forceUpdate = true;

  await db.doc("app_config/version").set(data, { merge: true });

  console.log("✅ app_config/version aggiornato:");
  console.log(JSON.stringify(data, null, 2));
}

main().catch((err) => {
  console.error("❌ Errore:", err);
  process.exit(1);
});
