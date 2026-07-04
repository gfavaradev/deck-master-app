import { getCatalogStatuses } from "@/lib/data/catalog";
import { PageHeader } from "@/components/ui";
import CatalogManager from "./catalog-manager";

export const dynamic = "force-dynamic";

export default async function CatalogPage() {
  const statuses = await getCatalogStatuses();

  return (
    <div>
      <PageHeader
        title="Catalogo"
        description="Stato di ogni catalogo. Espandi per vedere le carte per set."
      />

      <CatalogManager statuses={statuses} />

      <div className="panel mt-6 border-accent/20 bg-accent-soft/40 p-4 text-sm text-accent-2/80">
        <p className="mb-2 font-semibold text-accent-2">Rebuild / download catalogo</p>
        <p className="mb-2 text-ink-2">
          Ricostruire un catalogo scarica migliaia di carte dalle API sorgente e riscrive
          tutti i chunk: è un job lungo, non va eseguito in una funzione serverless (rischio
          catalogo corrotto se va in timeout a metà scrittura). Si esegue con gli script Node:
        </p>
        <pre className="mt-2 overflow-x-auto rounded-lg bg-app p-3 text-xs text-ink-2">
{`# YuGiOh (YGOProDeck, multilingua)
cd scripts/populate_firestore && npm start

# Prezzi CardTrader
cd scripts/price_sync && node index.js --catalogs yugioh`}
        </pre>
      </div>
    </div>
  );
}
