import "server-only";

import { GoogleAuth } from "google-auth-library";
import { readFileSync } from "node:fs";

/* eslint-disable @typescript-eslint/no-explicit-any */

// Integrazione GA4 Data API (uso app). Richiede:
//   - env GA4_PROPERTY_ID (numerico, es. 493820156)
//   - Google Analytics Data API abilitata nel progetto GCP
//   - service account con accesso (Viewer) alla proprietà GA4
// Se non configurato ritorna null; su errore ritorna { error } così la UI guida il setup.

function serviceAccount(): { client_email: string; private_key: string } | null {
  const json = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (json) {
    const p = JSON.parse(json);
    return { client_email: p.client_email, private_key: p.private_key };
  }
  const path = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (path) {
    const p = JSON.parse(readFileSync(path, "utf8"));
    return { client_email: p.client_email, private_key: p.private_key };
  }
  return null;
}

async function accessToken(): Promise<string> {
  const creds = serviceAccount();
  if (!creds) throw new Error("service account non configurato");
  const auth = new GoogleAuth({
    credentials: creds,
    scopes: ["https://www.googleapis.com/auth/analytics.readonly"],
  });
  const token = (await (await auth.getClient()).getAccessToken()).token;
  if (!token) throw new Error("access token non ottenuto");
  return token;
}

async function runReport(body: any): Promise<any> {
  const prop = process.env.GA4_PROPERTY_ID;
  const token = await accessToken();
  const res = await fetch(
    `https://analyticsdata.googleapis.com/v1beta/properties/${prop}:runReport`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    const msg = json?.error?.message ?? `HTTP ${res.status}`;
    throw new Error(msg);
  }
  return json;
}

export type Ga4Usage =
  | null
  | { error: string }
  | {
      activeUsers7: number;
      activeUsers28: number;
      newUsers7: number;
      series: { date: string; users: number }[];
      topScreens: { name: string; views: number }[];
    };

function num(v: any): number {
  return Number(v ?? 0) || 0;
}

export async function getGa4Usage(): Promise<Ga4Usage> {
  if (!process.env.GA4_PROPERTY_ID) return null;
  try {
    // Report 1: totali attivi/nuovi su due finestre.
    const totals = await runReport({
      dateRanges: [
        { startDate: "7daysAgo", endDate: "today" },
        { startDate: "28daysAgo", endDate: "today" },
      ],
      metrics: [{ name: "activeUsers" }, { name: "newUsers" }],
    });
    // Con più dateRanges, GA4 aggiunge la dimensione "dateRange" alle righe.
    let activeUsers7 = 0, activeUsers28 = 0, newUsers7 = 0;
    for (const row of totals.rows ?? []) {
      const rangeIdx = row.dimensionValues?.[0]?.value; // "date_range_0" | "date_range_1"
      const active = num(row.metricValues?.[0]?.value);
      const newU = num(row.metricValues?.[1]?.value);
      if (rangeIdx === "date_range_0") { activeUsers7 = active; newUsers7 = newU; }
      else if (rangeIdx === "date_range_1") activeUsers28 = active;
    }

    // Report 2: serie attivi per giorno (ultimi 14).
    const timeseries = await runReport({
      dateRanges: [{ startDate: "14daysAgo", endDate: "today" }],
      dimensions: [{ name: "date" }],
      metrics: [{ name: "activeUsers" }],
      orderBys: [{ dimension: { dimensionName: "date" } }],
    });
    const series = (timeseries.rows ?? []).map((r: any) => {
      const d = r.dimensionValues?.[0]?.value ?? ""; // YYYYMMDD
      return {
        date: d.length === 8 ? `${d.slice(6, 8)}/${d.slice(4, 6)}` : d,
        users: num(r.metricValues?.[0]?.value),
      };
    });

    // Report 3: schermate più viste (ultimi 28gg).
    const screens = await runReport({
      dateRanges: [{ startDate: "28daysAgo", endDate: "today" }],
      dimensions: [{ name: "unifiedScreenName" }],
      metrics: [{ name: "screenPageViews" }],
      orderBys: [{ metric: { metricName: "screenPageViews" }, desc: true }],
      limit: 8,
    });
    const topScreens = (screens.rows ?? []).map((r: any) => ({
      name: r.dimensionValues?.[0]?.value ?? "(n/d)",
      views: num(r.metricValues?.[0]?.value),
    }));

    return { activeUsers7, activeUsers28, newUsers7, series, topScreens };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}
