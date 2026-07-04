import { getAppStats } from "@/lib/data/stats";
import { getCatalogStatuses } from "@/lib/data/catalog";
import { getPriceStatuses } from "@/lib/data/jobs";
import { getGa4Usage } from "@/lib/data/ga4";
import { PageHeader, StatTile, SectionTitle } from "@/components/ui";

export const dynamic = "force-dynamic";

function fmt(s: string | null) {
  if (!s) return "mai";
  const d = new Date(s);
  return isNaN(d.getTime()) ? s : d.toLocaleDateString("it-IT");
}

export default async function StatsPage() {
  const [stats, catalogs, prices, ga4] = await Promise.all([
    getAppStats(),
    getCatalogStatuses(),
    getPriceStatuses(),
    getGa4Usage(),
  ]);
  const ga4Data = ga4 && !("error" in ga4) ? ga4 : null;
  const maxUsers = ga4Data ? Math.max(1, ...ga4Data.series.map((s) => s.users)) : 1;

  const totalCards = catalogs.reduce((a, c) => a + c.totalCards, 0);
  const activeCatalogs = catalogs.filter((c) => c.totalCards > 0);
  const maxCards = Math.max(1, ...activeCatalogs.map((c) => c.totalCards));

  return (
    <div className="space-y-8">
      <PageHeader title="Statistiche" description="Panoramica dati app, catalogo e uso." />

      <section className="space-y-3">
        <SectionTitle>Utenti</SectionTitle>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <StatTile label="Totali" value={stats.users.total} />
          <StatTile label="Pro" value={stats.users.pro} accent />
          <StatTile label="Admin" value={stats.users.admin} />
          <StatTile label="Nuovi 7gg" value={stats.users.new7} />
          <StatTile label="Nuovi 30gg" value={stats.users.new30} />
          <StatTile label="Attivi 7gg" value={stats.users.active7} />
        </div>
      </section>

      <section className="space-y-3">
        <SectionTitle>Catalogo</SectionTitle>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <StatTile label="Carte totali" value={totalCards.toLocaleString("it-IT")} accent />
          <StatTile label="Cataloghi attivi" value={activeCatalogs.length} />
          <StatTile label="News pubblicate" value={stats.news.published} />
          <StatTile label="News in revisione" value={stats.news.drafts} />
        </div>
        <div className="panel space-y-1.5 p-4">
          {activeCatalogs
            .sort((a, b) => b.totalCards - a.totalCards)
            .map((c) => (
              <div key={c.catalog} className="flex items-center gap-3 text-xs">
                <span className="w-32 shrink-0 text-ink-2">{c.catalog}</span>
                <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-panel-2">
                  <span
                    className="block h-full rounded-full bg-accent/70"
                    style={{ width: `${(c.totalCards / maxCards) * 100}%` }}
                  />
                </span>
                <span className="num w-16 shrink-0 text-right text-ink-3">
                  {c.totalCards.toLocaleString("it-IT")}
                </span>
              </div>
            ))}
        </div>
      </section>

      <section className="space-y-3">
        <SectionTitle>Salute prezzi</SectionTitle>
        <div className="panel overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-ink-3">
              <tr className="border-b border-line">
                <th className="px-4 py-2.5 font-medium">Catalogo</th>
                <th className="px-4 py-2.5 font-medium">Prezzi</th>
                <th className="px-4 py-2.5 font-medium">Ultimo sync</th>
              </tr>
            </thead>
            <tbody>
              {prices.map((p) => (
                <tr key={p.catalog} className="border-b border-line last:border-0">
                  <td className="px-4 py-2">{p.catalog}</td>
                  <td className="num px-4 py-2 text-ink-2">{p.count ?? "—"}</td>
                  <td className="px-4 py-2 text-ink-3">{fmt(p.syncedAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="space-y-3">
        <SectionTitle>Uso app (GA4)</SectionTitle>
        {ga4 === null && (
          <div className="panel border-dashed p-4 text-xs text-ink-3">
            Da configurare: variabile <code>GA4_PROPERTY_ID</code>.
          </div>
        )}
        {ga4 && "error" in ga4 && (
          <div className="panel border-accent/20 bg-accent-soft/40 p-4 text-xs text-accent-2/80">
            <p className="font-medium text-accent-2">GA4 non ancora raggiungibile</p>
            <p className="mt-1 text-ink-2">{ga4.error}</p>
            <p className="mt-2 text-ink-3">
              Abilita la Analytics Data API nel progetto GCP e concedi al service account
              l&apos;accesso (Viewer) alla proprietà GA4.
            </p>
          </div>
        )}
        {ga4Data && (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <StatTile label="Attivi 7gg" value={ga4Data.activeUsers7} accent />
              <StatTile label="Attivi 28gg" value={ga4Data.activeUsers28} />
              <StatTile label="Nuovi 7gg" value={ga4Data.newUsers7} />
            </div>
            <div className="panel p-4">
              <p className="mb-3 text-xs text-ink-3">Utenti attivi · ultimi 14 giorni</p>
              <div className="flex h-28 items-end gap-1.5">
                {ga4Data.series.map((s) => (
                  <div key={s.date} className="flex flex-1 flex-col items-center gap-1">
                    <div
                      className="w-full rounded-t bg-accent/70"
                      style={{ height: `${(s.users / maxUsers) * 100}%` }}
                      title={`${s.date}: ${s.users}`}
                    />
                    <span className="text-[9px] text-ink-3">{s.date}</span>
                  </div>
                ))}
              </div>
            </div>
            {ga4Data.topScreens.length > 0 && (
              <div className="panel p-4">
                <p className="mb-2 text-xs text-ink-3">Schermate più viste (28gg)</p>
                <ul className="space-y-1">
                  {ga4Data.topScreens.map((s) => (
                    <li key={s.name} className="flex justify-between text-xs">
                      <span className="truncate text-ink-2">{s.name}</span>
                      <span className="num text-ink-3">{s.views.toLocaleString("it-IT")}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </section>

      <section className="space-y-3">
        <SectionTitle>Download store</SectionTitle>
        <div className="panel border-dashed p-4 text-xs text-ink-3">
          Installazioni Google Play + App Store. Da configurare: Play Developer Reporting
          API e App Store Connect API (credenziali dedicate).
        </div>
      </section>
    </div>
  );
}
