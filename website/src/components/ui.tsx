"use client";

import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";

import type { JobStatus } from "@/types/api";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost";
  size?: "sm" | "md" | "lg";
};

export function Button({ variant = "primary", size = "md", className = "", ...props }: ButtonProps) {
  const styles = {
    primary: "bg-brand text-brand-fg hover:bg-brand-dark",
    secondary: "bg-surface text-ink border border-line-strong hover:bg-surface-raised",
    ghost: "text-ink-muted hover:bg-surface-raised",
  }[variant];
  const sizing = { sm: "px-2.5 py-1.5 text-xs", md: "px-4 py-2.5 text-sm", lg: "px-5 py-3 text-base" }[size];

  return (
    <button
      {...props}
      className={`inline-flex items-center justify-center rounded-lg font-medium transition disabled:cursor-not-allowed disabled:opacity-50 ${styles} ${sizing} ${className}`}
    />
  );
}

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`w-full rounded-lg border border-line-strong px-3 py-2.5 text-base outline-none focus:border-brand focus:ring-1 focus:ring-brand ${className}`}
    />
  );
}

export function Textarea({ className = "", ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      {...props}
      className={`w-full rounded-lg border border-line-strong px-3 py-2.5 text-base outline-none focus:border-brand focus:ring-1 focus:ring-brand ${className}`}
    />
  );
}

export function Select({ className = "", ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`w-full rounded-lg border border-line-strong bg-surface px-3 py-2.5 text-base outline-none focus:border-brand focus:ring-1 focus:ring-brand ${className}`}
    />
  );
}

export function Field({
  label,
  error,
  hint,
  children,
}: {
  label: string;
  error?: string | null;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <label className="block space-y-1.5">
      <span className="text-sm font-medium">{label}</span>
      {children}
      {hint ? <span className="block text-xs text-ink-muted">{hint}</span> : null}
      {error ? <span className="block text-sm text-brand">{error}</span> : null}
    </label>
  );
}

export function Card({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section className="rounded-xl border border-line bg-surface shadow-sm">
      {title ? (
        <header className="border-b border-line px-5 py-4">
          <h2 className="font-semibold">{title}</h2>
        </header>
      ) : null}
      <div className="p-5">{children}</div>
    </section>
  );
}

const STATUS_STYLES: Record<JobStatus, string> = {
  submitted: "chip-warn",
  dispatching: "chip-warn",
  assigned: "chip-warn",
  accepted: "chip-info",
  en_route: "chip-accent",
  arrived: "chip-accent",
  in_progress: "chip-brand",
  completed: "chip-ok",
  cancelled: "chip-muted",
  unclaimed: "chip-warn",
};

export function StatusBadge({ status, label }: { status: JobStatus; label: string }) {
  return (
    <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_STYLES[status]}`}>
      {label}
    </span>
  );
}

export function Notice({ tone = "info", children }: { tone?: "info" | "warning" | "error"; children: ReactNode }) {
  const styles = {
    info: "border-line chip-muted",
    warning: "border-warning/40 bg-warning/10 text-warning",
    error: "border-danger/40 bg-danger/10 text-danger",
  }[tone];
  return <div className={`rounded-lg border px-4 py-3 text-sm ${styles}`}>{children}</div>;
}

export function Steps({ current, labels }: { current: number; labels: string[] }) {
  return (
    <ol className="flex flex-wrap gap-2 text-xs">
      {labels.map((label, index) => (
        <li
          key={label}
          className={`rounded-full px-3 py-1 ${
            index === current
              ? "bg-brand text-brand-fg"
              : index < current
                ? "chip-ok"
                : "bg-surface-raised text-ink-subtle"
          }`}
        >
          {index + 1}. {label}
        </li>
      ))}
    </ol>
  );
}

export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-ink-muted">{label}</dt>
      <dd className="mt-0.5">{value || "—"}</dd>
    </div>
  );
}
