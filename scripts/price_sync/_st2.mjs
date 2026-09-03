import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";
initializeApp({ credential: cert(JSON.parse(readFileSync("./serviceAccountKey.json","utf8"))) });
const db = getFirestore();
const x = (await db.doc("admin_jobs/catalog_rebuild_lorcana").get()).data() ?? {};
console.log(JSON.stringify({status:x.status, processed:x.processed, total:x.total, message:x.message, error:x.error,
  startedAt:x.startedAt?.toDate?.()?.toISOString?.(), finishedAt:x.finishedAt?.toDate?.()?.toISOString?.(),
  heartbeatAt:x.heartbeatAt?.toDate?.()?.toISOString?.()}, null, 1));
console.log("adesso:", new Date().toISOString());
process.exit(0);
