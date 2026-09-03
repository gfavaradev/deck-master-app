// Rilancia in SEQUENZA i job uccisi dal deploy, tenendo sveglio il worker.
// Due motivi per non lanciarli in parallelo: il piano free ha 512 MB (piu' job
// insieme = piu' picchi di memoria) e Render mette in sleep il servizio dopo
// ~15 min senza richieste HTTP in ingresso, uccidendo i job in corso. Il ping
// a /health mentre si aspetta risolve il secondo problema.
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";

const KEY = "/Users/mr.codekiller/Project/deck-master-app/scripts/price_sync/serviceAccountKey.json";
initializeApp({ credential: cert(JSON.parse(readFileSync(KEY, "utf8"))) });
const db = getFirestore();

const WORKER = "https://deck-master-worker-9jcq.onrender.com";
const SECRET = readFileSync("/Users/mr.codekiller/Project/deck-master-web/.env", "utf8")
  .split("\n").find(l => l.startsWith("WORKER_SECRET")).split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "");

const sleep = ms => new Promise(r => setTimeout(r, ms));
const ping = () => fetch(`${WORKER}/health`, { signal: AbortSignal.timeout(30000) }).catch(() => {});

async function run(catalog) {
  const res = await fetch(`${WORKER}/jobs/price-sync`, {
    method: "POST",
    headers: { "x-worker-secret": SECRET, "Content-Type": "application/json" },
    body: JSON.stringify({ catalog }),
    signal: AbortSignal.timeout(120000),
  });
  const body = await res.json().catch(() => ({}));
  if (res.status !== 202) { console.log(`${catalog}: AVVIO FALLITO ${res.status} ${JSON.stringify(body)}`); return false; }
  console.log(`${catalog}: avviato`);

  const ref = db.collection("admin_jobs").doc(`catalog_price-sync_${catalog}`);
  for (let i = 0; i < 200; i++) {   // max 100 min
    await sleep(30000);
    await ping();                    // keep-alive: impedisce lo sleep di Render
    const d = (await ref.get()).data() ?? {};
    if (d.status !== "running") {
      console.log(`${catalog}: ${d.status} — ${(d.message ?? d.error ?? "").toString().slice(0, 110)}`);
      return d.status === "ok";
    }
    if (i % 4 === 0) console.log(`  ${catalog}: ${d.processed ?? "?"}/${d.total ?? "?"} — ${(d.message ?? "").slice(0, 60)}`);
  }
  console.log(`${catalog}: TIMEOUT dopo 60 min`);
  return false;
}

for (const c of ["yugioh"]) {
  await run(c);
}
console.log("SEQUENZA COMPLETATA");
process.exit(0);
