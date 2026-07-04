import { getPriceStatuses } from "@/lib/data/jobs";
import { PageHeader } from "@/components/ui";
import PricesManager from "./prices-manager";

export const dynamic = "force-dynamic";

export default async function PricesPage() {
  const statuses = await getPriceStatuses();
  return (
    <div>
      <PageHeader title="Prezzi & Job" description="Sync prezzi CardTrader e stato dei job." />
      <PricesManager statuses={statuses} />
    </div>
  );
}
