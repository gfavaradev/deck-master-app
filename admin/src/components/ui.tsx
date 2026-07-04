import type { ReactNode } from "react";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="mb-6 flex items-end justify-between gap-4">
      <div>
        <h1 className="text-xl font-semibold tracking-tight text-ink">{title}</h1>
        {description && <p className="mt-0.5 text-sm text-ink-3">{description}</p>}
      </div>
      {actions}
    </div>
  );
}

export function StatTile({
  label,
  value,
  hint,
  accent,
}: {
  label: string;
  value: string | number;
  hint?: string;
  accent?: boolean;
}) {
  return (
    <div className="panel panel-hover p-4">
      <div className="text-[11px] font-medium uppercase tracking-wide text-ink-3">
        {label}
      </div>
      <div
        className={`num mt-1 text-2xl font-semibold ${accent ? "text-accent-2" : "text-ink"}`}
      >
        {value}
      </div>
      {hint && <div className="mt-0.5 text-xs text-ink-3">{hint}</div>}
    </div>
  );
}

export function SectionTitle({ children }: { children: ReactNode }) {
  return (
    <h2 className="text-[13px] font-semibold uppercase tracking-wide text-ink-3">
      {children}
    </h2>
  );
}
