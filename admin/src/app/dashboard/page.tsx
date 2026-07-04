import { getCurrentAdmin } from "@/lib/auth/session";
import { getAppStats } from "@/lib/data/stats";
import { getCatalogStatuses } from "@/lib/data/catalog";
import { PageHeader, StatTile } from "@/components/ui";
import HealthCard from "./health-card";

export const dynamic = "force-dynamic";

export default async function OverviewPage() {
  const [admin, stats, catalogs] = await Promise.all([
    getCurrentAdmin(),
    getAppStats(),
    getCatalogStatuses(),
  ]);
  const totalCards = catalogs.reduce((a, c) => a + c.totalCards, 0);

  return (
    <div>
      <PageHeader
        title={`Ciao, ${admin?.name?.split(" ")[0] ?? "Admin"}`}
        description="Riepilogo dello stato dell'app."
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatTile label="Utenti" value={stats.users.total} />
        <StatTile label="Pro attivi" value={stats.users.pro} accent />
        <StatTile label="Carte a catalogo" value={totalCards.toLocaleString("it-IT")} />
        <StatTile label="News pubblicate" value={stats.news.published} />
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <HealthCard />
        <div className="panel p-5">
          <h2 className="mb-3 text-sm font-semibold text-ink-2">Attività recente</h2>
          <ul className="space-y-2 text-sm text-ink-2">
            <li className="flex justify-between">
              <span>Nuovi utenti (7gg)</span>
              <span className="num text-ink">{stats.users.new7}</span>
            </li>
            <li className="flex justify-between">
              <span>Utenti attivi (7gg)</span>
              <span className="num text-ink">{stats.users.active7}</span>
            </li>
            <li className="flex justify-between">
              <span>News in revisione</span>
              <span className="num text-ink">{stats.news.drafts}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
  );
}
