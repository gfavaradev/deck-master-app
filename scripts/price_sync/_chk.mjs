import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json","utf8"))) });
const db = getFirestore();
for (const c of process.argv.slice(2)) {
  const meta = (await db.doc(`${c}_catalog/metadata`).get()).data() ?? {};
  const cards = (await db.doc(`${c}_catalog/chunks/items/chunk_001`).get()).data()?.cards ?? [];
  let num=0, rar=0, abs=0, bp=0;
  for (const x of cards) {
    if (x.card_number) num++;
    if (x.rarity) rar++;
    if (x.blueprint_id) bp++;
    const u = x.image_url ?? x.imageUrl ?? "";
    if (/^https?:\/\//.test(u)) abs++;
  }
  console.log(`${c}: agg ${meta.lastUpdated?.toDate?.()?.toISOString?.().slice(0,16) ?? meta.lastUpdated} da ${meta.updatedBy} | v${meta.version} | ${meta.totalCards} carte`);
  console.log(`   chunk1 ${cards.length}: card_number ${num} | rarità ${rar} | blueprint_id ${bp} | img assolute ${abs}`);
  if (cards[0]) console.log("   ", JSON.stringify(cards[0]).slice(0,260));
}
process.exit(0);
