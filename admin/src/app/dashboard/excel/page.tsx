import { listCatalogs } from "@/lib/data/cards";
import { PageHeader } from "@/components/ui";
import ExcelManager from "./excel-manager";

export const dynamic = "force-dynamic";

export default async function ExcelPage() {
  const catalogs = await listCatalogs();
  return (
    <div>
      <PageHeader title="Excel" description="Export e import bulk del catalogo." />
      <ExcelManager catalogs={catalogs} />
    </div>
  );
}
