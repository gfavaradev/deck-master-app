import { listCatalogs } from "@/lib/data/cards";
import { PageHeader } from "@/components/ui";
import CardsManager from "./cards-manager";

export const dynamic = "force-dynamic";

export default async function CardsPage() {
  const catalogs = await listCatalogs();
  return (
    <div>
      <PageHeader title="Carte" description="Cerca, modifica o elimina carte dai cataloghi." />
      <CardsManager catalogs={catalogs} />
    </div>
  );
}
