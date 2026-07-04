import { redirect } from "next/navigation";
import { getCurrentAdmin } from "@/lib/auth/session";
import Nav from "./nav";
import LogoutButton from "./logout-button";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const admin = await getCurrentAdmin();
  if (!admin) redirect("/login");

  const initials = (admin.name ?? admin.email ?? "?")
    .split(/[\s@.]/)
    .filter(Boolean)
    .slice(0, 2)
    .map((s) => s[0]?.toUpperCase())
    .join("");

  return (
    <div className="flex min-h-screen">
      {/* Sidebar */}
      <aside className="sticky top-0 flex h-screen w-64 flex-col border-r border-line bg-panel/70 backdrop-blur">
        <div className="flex items-center gap-2.5 px-5 py-5">
          <div className="grid h-8 w-8 place-items-center rounded-lg bg-gradient-to-br from-accent to-accent-2 text-sm font-bold text-app">
            D
          </div>
          <div className="leading-tight">
            <p className="text-sm font-semibold text-ink">Deck Master</p>
            <p className="text-[11px] text-ink-3">Admin dashboard</p>
          </div>
        </div>

        <div className="mt-2 flex-1 overflow-y-auto">
          <Nav />
        </div>

        <div className="border-t border-line p-3">
          <div className="flex items-center gap-2.5 rounded-lg px-2 py-1.5">
            {admin.picture ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={admin.picture} alt="" className="h-8 w-8 rounded-full" />
            ) : (
              <div className="grid h-8 w-8 place-items-center rounded-full bg-elevated text-xs font-semibold text-ink-2">
                {initials}
              </div>
            )}
            <div className="min-w-0 flex-1 leading-tight">
              <p className="truncate text-xs font-medium text-ink">{admin.name ?? "Admin"}</p>
              <p className="truncate text-[11px] text-ink-3">{admin.email}</p>
            </div>
          </div>
        </div>
      </aside>

      {/* Main */}
      <div className="flex flex-1 flex-col">
        <header className="sticky top-0 z-10 flex items-center justify-between border-b border-line bg-app/70 px-6 py-3 backdrop-blur">
          <div className="flex items-center gap-2 text-xs text-ink-3">
            <span className="h-1.5 w-1.5 rounded-full bg-ok" />
            Connesso a Firestore · deck-master-1a35a
          </div>
          <LogoutButton />
        </header>
        <main className="flex-1 px-6 py-7">
          <div className="mx-auto max-w-6xl">{children}</div>
        </main>
      </div>
    </div>
  );
}
