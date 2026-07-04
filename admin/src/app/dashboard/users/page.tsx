import { listUsers } from "@/lib/data/users";
import { PageHeader } from "@/components/ui";
import UsersTable from "./users-table";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const users = await listUsers();
  return (
    <div>
      <PageHeader title="Utenti" description="Gestione ruoli, Pro e stato account." />
      <UsersTable users={users} />
    </div>
  );
}
