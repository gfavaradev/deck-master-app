import "server-only";

import { adminDb } from "@/lib/firebase/admin";

function daysAgoIso(days: number): string {
  return new Date(Date.now() - days * 86400000).toISOString();
}

async function count(query: FirebaseFirestore.Query): Promise<number> {
  const snap = await query.count().get();
  return snap.data().count;
}

export type AppStats = {
  users: {
    total: number;
    pro: number;
    admin: number;
    new7: number;
    new30: number;
    active7: number;
  };
  news: { published: number; drafts: number };
};

export async function getAppStats(): Promise<AppStats> {
  const db = adminDb();
  const users = db.collection("users");
  const cutoff7 = daysAgoIso(7);
  const cutoff30 = daysAgoIso(30);

  const [
    total, pro, admin, new7, new30, active7, newsPublished, newsDrafts,
  ] = await Promise.all([
    count(users),
    count(users.where("isPro", "==", true)),
    count(users.where("role", "==", "administrator")),
    count(users.where("createdAt", ">=", cutoff7)),
    count(users.where("createdAt", ">=", cutoff30)),
    count(users.where("lastLoginAt", ">=", cutoff7)),
    count(db.collection("news")),
    count(db.collection("news_drafts")),
  ]);

  return {
    users: { total, pro, admin, new7, new30, active7 },
    news: { published: newsPublished, drafts: newsDrafts },
  };
}
