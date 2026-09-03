import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json","utf8"))) });
const db = getFirestore();
const cards = (await db.doc("yugioh_catalog/chunks/items/chunk_001").get()).data()?.cards ?? [];
const langCount = {}; let tr = 0;
for (const c of cards) {
  for (const [k, arr] of Object.entries(c.sets ?? {})) langCount[k] = (langCount[k] ?? 0) + arr.length;
  if (c.name_it) tr++;
}
console.log(`yugioh chunk1: ${cards.length} carte | con nome IT: ${tr}`);
console.log("stampe per lingua:", JSON.stringify(langCount));
const ex = cards.find(c => c.sets?.it?.length);
console.log("esempio IT:", JSON.stringify(ex?.sets?.it?.[0]));
console.log("esempio EN:", JSON.stringify(ex?.sets?.en?.[0]));
console.log("nome:", ex?.name, "| name_it:", ex?.name_it, "| name_de:", ex?.name_de);
process.exit(0);
