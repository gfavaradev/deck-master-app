// Lancia un job sul worker e ne segue lo stato, tenendo sveglia l'istanza free
// di Render con un ping a /health (senza traffico in ingresso va in sleep dopo
// ~15 min e uccide il job in corso).
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json", "utf8"))) });
const db = getFirestore();

const WORKER = "https://deck-master-worker-9jcq.onrender.com";
const SECRET = readFileSync("/Users/mr.codekiller/Project/deck-master-web/.env", "utf8")
  .split("\n").find(l => l.startsWith("WORKER_SECRET")).split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "");

const sleep = ms => new Promise(r => setTimeout(r, ms));
const ping = () => fetch(`${WORKER}/health`, { signal: AbortSignal.timeout(30000) }).catch(() => {});

const [op, ...catalogs] = process.argv.slice(2);

async function run(catalog) {
  const res = await fetch(`${WORKER}/jobs/${op}`, {
    method: "POST",
    headers: { "x-worker-secret": SECRET, "Content-Type": "application/json" },
    body: JSON.stringify({ catalog }),
    signal: AbortSignal.timeout(120000),
  });
  const body = await res.json().catch(() => ({}));
  if (res.status !== 202) { console.log(`${op}/${catalog}: AVVIO FALLITO ${res.status} ${JSON.stringify(body)}`); return false; }
  console.log(`${op}/${catalog}: avviato`);

  const ref = db.collection("admin_jobs").doc(`catalog_${op}_${catalog}`);
  for (let i = 0; i < 240; i++) {
    await sleep(30000);
    await ping();
    const d = (await ref.get()).data() ?? {};
    if (d.status !== "running") {
      console.log(`${op}/${catalog}: ${d.status} — ${(d.message ?? d.error ?? "").toString().slice(0, 200)}`);
      return d.status === "ok";
    }
    if (i % 4 === 0) console.log(`  ${catalog}: ${d.processed ?? "?"}/${d.total ?? "?"} — ${(d.message ?? "").slice(0, 90)}`);
  }
  console.log(`${op}/${catalog}: TIMEOUT dopo 120 min`);
  return false;
}

for (const c of catalogs) await run(c);
console.log("SEQUENZA COMPLETATA");
process.exit(0);
