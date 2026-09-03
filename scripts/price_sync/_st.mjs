import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json","utf8"))) });
const db = getFirestore();
for (const id of process.argv.slice(2)) {
  const x = (await db.doc(`admin_jobs/${id}`).get()).data() ?? {};
  console.log(id, "|", x.status, "|", x.processed ?? "?", "/", x.total ?? "?", "|", (x.message ?? x.error ?? "").toString().slice(0,140));
}
process.exit(0);
