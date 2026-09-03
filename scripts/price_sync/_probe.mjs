import { initializeApp, cert } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json","utf8"))),
  databaseURL: "https://deck-master-1a35a-default-rtdb.europe-west1.firebasedatabase.app" });
const db = getDatabase();
for (const arg of process.argv.slice(2)) {
  const [cat, set] = arg.split("/");
  const node = (await db.ref(`p/${cat}/s/${set}`).get()).val() ?? {};
  const langs = Object.keys(node).map(l => `${l}:${Object.keys(node[l]).length}`).join(" ");
  console.log(`${cat}/${set} → ${langs || "(vuoto)"}`);
  const first = Object.keys(node)[0];
  if (first) console.log("   chiavi es:", JSON.stringify(Object.keys(node[first]).slice(0,3)));
}
process.exit(0);
