"use client";

import { useEffect, useState } from "react";

type Check = { ok: boolean; detail?: string };
type Health = { ok: boolean; checks: Record<string, Check> };

const LABELS: Record<string, string> = {
  firestore: "Firestore",
  cardtrader: "CardTrader",
  backblaze: "Backblaze B2",
};

export default function HealthCard() {
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/health")
      .then((r) => r.json())
      .then(setHealth)
      .catch((e) => setError(String(e)));
  }, []);

  return (
    <div className="panel p-5">
      <h2 className="mb-4 text-sm font-semibold text-ink-2">Stato backend</h2>
      {error && <p className="text-sm text-bad">{error}</p>}
      {!health && !error && (
        <p className="text-sm text-ink-3">Verifica in corso…</p>
      )}
      {health && (
        <ul className="space-y-2">
          {Object.entries(health.checks).map(([key, check]) => (
            <li key={key} className="flex items-center gap-3 text-sm">
              <span
                className={`inline-block h-2.5 w-2.5 rounded-full ${
                  check.ok ? "bg-ok" : "bg-bad"
                }`}
              />
              <span className="w-28 text-ink-2">{LABELS[key] ?? key}</span>
              <span className="text-ink-3">{check.detail ?? (check.ok ? "OK" : "errore")}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
