import { listNews, listDrafts } from "@/lib/data/news";
import { PageHeader } from "@/components/ui";
import NewsManager from "./news-manager";

export const dynamic = "force-dynamic";

export default async function NewsPage() {
  const [published, drafts] = await Promise.all([listNews(), listDrafts()]);
  return (
    <div>
      <PageHeader title="News" description="Pubblicazione e revisione delle news." />
      <NewsManager published={published} drafts={drafts} />
    </div>
  );
}
