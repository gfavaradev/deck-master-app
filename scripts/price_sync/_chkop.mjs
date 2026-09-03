import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json","utf8"))) });
const db = getFirestore();
const cards = (await db.doc("onepiece_catalog/chunks/items/chunk_001").get()).data()?.cards ?? [];
let real=0, sur=0, bp=0, art=0;
for (const c of cards) for (const p of c.prints ?? []) {
  const tail = String(p.card_set_id).split("-").pop();
  if (/^\d{5,}$/.test(tail)) sur++; else real++;
  if (p.blueprint_id) bp++;
  if (p.artwork) art++;
}
console.log(`onepiece chunk1: ${cards.length} carte | seriali veri ${real} | surrogati ${sur} | blueprint_id ${bp} | artwork ${art}`);
console.log(JSON.stringify(cards[0]).slice(0,320));
process.exit(0);
