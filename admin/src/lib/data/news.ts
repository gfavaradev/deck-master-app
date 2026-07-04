import "server-only";

import { adminDb } from "@/lib/firebase/admin";
import { Timestamp } from "firebase-admin/firestore";
import type {
  DocumentData,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";

export type NewsItem = {
  id: string;
  title: string;
  subtitle?: string | null;
  body?: string;
  imageUrl?: string | null;
  externalUrl?: string | null;
  collections: string[];
  pinned: boolean;
  publishedAt?: string | null;
  status?: string;
};

export type NewsInput = {
  title: string;
  subtitle?: string | null;
  body?: string;
  imageUrl?: string | null;
  externalUrl?: string | null;
  collections: string[];
  pinned?: boolean;
  publishedAt?: string | null;
};

function toIso(v: unknown): string | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (typeof v === "string") return v;
  if (typeof v === "object" && v !== null && "_seconds" in v) {
    return new Date((v as { _seconds: number })._seconds * 1000).toISOString();
  }
  return null;
}

function mapDoc(d: QueryDocumentSnapshot<DocumentData>): NewsItem {
  const x = d.data();
  return {
    id: d.id,
    title: (x.title as string) ?? "",
    subtitle: (x.subtitle as string | null) ?? null,
    body: (x.body as string) ?? "",
    imageUrl: (x.imageUrl as string | null) ?? null,
    externalUrl: (x.externalUrl as string | null) ?? null,
    collections: (x.collections as string[]) ?? [],
    pinned: x.pinned === true,
    publishedAt: toIso(x.publishedAt),
    status: x.status as string | undefined,
  };
}

function toDocData(input: NewsInput) {
  return {
    title: input.title,
    subtitle: input.subtitle ?? null,
    body: input.body ?? "",
    imageUrl: input.imageUrl ?? null,
    externalUrl: input.externalUrl ?? null,
    collections: input.collections ?? [],
    pinned: input.pinned === true,
    publishedAt: input.publishedAt
      ? Timestamp.fromDate(new Date(input.publishedAt))
      : Timestamp.now(),
  };
}

export async function listNews(): Promise<NewsItem[]> {
  const snap = await adminDb().collection("news").get();
  const rows = snap.docs.map(mapDoc);
  rows.sort((a, b) => (b.publishedAt ?? "").localeCompare(a.publishedAt ?? ""));
  return rows;
}

export async function listDrafts(): Promise<NewsItem[]> {
  const snap = await adminDb().collection("news_drafts").get();
  return snap.docs.map(mapDoc);
}

export async function createNews(input: NewsInput): Promise<void> {
  await adminDb()
    .collection("news")
    .add({ ...toDocData(input), status: "published" });
}

export async function updateNews(id: string, input: NewsInput): Promise<void> {
  await adminDb().collection("news").doc(id).update({ ...toDocData(input) });
}

export async function deleteNews(id: string): Promise<void> {
  await adminDb().collection("news").doc(id).delete();
}

export async function setPinned(id: string, pinned: boolean): Promise<void> {
  await adminDb().collection("news").doc(id).update({ pinned });
}

// Approva un draft (da news_sync): lo copia in `news` come pubblicato e rimuove il draft.
export async function approveDraft(id: string): Promise<void> {
  const ref = adminDb().collection("news_drafts").doc(id);
  const snap = await ref.get();
  if (!snap.exists) return;
  const data = { ...(snap.data() as DocumentData) };
  delete data.status;
  delete data.fetchedAt;
  await adminDb()
    .collection("news")
    .add({ ...data, status: "published" });
  await ref.delete();
}

export async function rejectDraft(id: string): Promise<void> {
  await adminDb().collection("news_drafts").doc(id).delete();
}
