"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

function Icon({ d }: { d: string }) {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="shrink-0"
    >
      <path d={d} />
    </svg>
  );
}

const ICONS = {
  overview: "M3 12h7V3H3v9Zm0 9h7v-6H3v6Zm11 0h7V12h-7v9Zm0-18v6h7V3h-7Z",
  cards: "M3 7a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Zm6 2h13v10a2 2 0 0 1-2 2H9",
  catalog: "M4 5a2 2 0 0 1 2-2h9l5 5v11a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5Zm11-2v5h5",
  news: "M4 5a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v14l-3-2-3 2-3-2-3 2V5Zm3 3h7M7 12h7",
  prices: "M12 1v22M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6",
  excel: "M4 4h16v16H4V4Zm0 6h16M10 4v16M8 13l3 3m0-3l-3 3",
  users: "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm14 10v-2a4 4 0 0 0-3-3.87M16 3.13A4 4 0 0 1 16 11",
  stats: "M3 3v18h18M7 15l4-4 3 3 5-6",
};

const NAV = [
  { href: "/dashboard", label: "Panoramica", icon: ICONS.overview },
  { href: "/dashboard/cards", label: "Carte", icon: ICONS.cards },
  { href: "/dashboard/catalog", label: "Catalogo", icon: ICONS.catalog },
  { href: "/dashboard/news", label: "News", icon: ICONS.news },
  { href: "/dashboard/prices", label: "Prezzi & Job", icon: ICONS.prices },
  { href: "/dashboard/excel", label: "Excel", icon: ICONS.excel },
  { href: "/dashboard/users", label: "Utenti", icon: ICONS.users },
  { href: "/dashboard/stats", label: "Statistiche", icon: ICONS.stats },
];

export default function Nav() {
  const pathname = usePathname();
  return (
    <nav className="flex flex-col gap-0.5 px-3">
      {NAV.map((item) => {
        const active =
          item.href === "/dashboard"
            ? pathname === "/dashboard"
            : pathname.startsWith(item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`group relative flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition ${
              active
                ? "bg-accent-soft text-accent-2 font-medium"
                : "text-ink-2 hover:bg-panel-2 hover:text-ink"
            }`}
          >
            {active && (
              <span className="absolute left-0 top-1/2 h-4 w-0.5 -translate-y-1/2 rounded-full bg-accent" />
            )}
            <span className={active ? "text-accent" : "text-ink-3 group-hover:text-ink-2"}>
              <Icon d={item.icon} />
            </span>
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
