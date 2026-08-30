"use client";

import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";

import type { DocumentStatus, InvoiceStatus, JobStatus, VerificationStatus } from "@/types/api";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  size?: "sm" | "md";
};

export function Button({ variant = "primary", size = "md", className = "", ...props }: ButtonProps) {
  const styles = {
    primary: "bg-brand text-brand-fg hover:bg-brand-dark",
    secondary: "bg-surface text-ink border border-line-strong hover:bg-surface-raised",
    ghost: "text-ink-muted hover:bg-surface-raised",
    danger: "bg-danger text-ink-inverse hover:bg-danger/85",
  }[variant];
  const sizing = size === "sm" ? "px-2 py-1 text-xs" : "px-3 py-2 text-sm";

  return (
    <button
      {...props}
      className={`inline-flex items-center justify-center rounded-md font-medium transition disabled:cursor-not-allowed disabled:opacity-50 ${styles} ${sizing} ${className}`}
    />
  );
}

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`w-full rounded-md border border-line-strong px-3 py-2 text-sm outline-none focus:border-brand focus:ring-1 focus:ring-brand ${className}`}
    />
  );
}

export function Textarea({ className = "", ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      {...props}
      className={`w-full rounded-md border border-line-strong px-3 py-2 text-sm outline-none focus:border-brand focus:ring-1 focus:ring-brand ${className}`}
    />
  );
}

export function Select({ className = "", ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`w-full rounded-md border border-line-strong bg-surface px-3 py-2 text-sm outline-none focus:border-brand focus:ring-1 focus:ring-brand ${className}`}
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
    <label className="block space-y-1">
      <span className="text-xs font-medium uppercase tracking-wide text-ink-muted">{label}</span>
      {children}
      {hint ? <span className="block text-xs text-ink-subtle">{hint}</span> : null}
      {error ? <span className="block text-xs text-brand">{error}</span> : null}
    </label>
  );
}

export function Card({
  title,
  action,
  children,
}: {
  title?: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="rounded-lg border border-line bg-surface shadow-sm">
      {title ? (
        <header className="flex items-center justify-between gap-3 border-b border-line px-4 py-3">
          <h2 className="text-sm font-semibold">{title}</h2>
          {action}
        </header>
      ) : null}
      <div className="p-4">{children}</div>
    </section>
  );
}

/** Section 5's ten statuses. Amber means somebody has to do something. */
const JOB_STATUS_STYLES: Record<JobStatus, string> = {
  submitted: "chip-warn",
  dispatching: "chip-warn",
  assigned: "chip-info",
  accepted: "chip-info",
  en_route: "chip-accent",
  arrived: "chip-accent",
  in_progress: "chip-brand",
  completed: "chip-ok",
  cancelled: "chip-muted",
  unclaimed: "chip-danger",
};

export function StatusBadge({ status, label }: { status: JobStatus; label: string }) {
  return <Pill className={JOB_STATUS_STYLES[status]}>{label}</Pill>;
}

const VERIFICATION_STYLES: Record<VerificationStatus, string> = {
  pending: "chip-warn",
  approved: "chip-ok",
  rejected: "chip-muted",
  suspended: "chip-danger",
};

export function VerificationBadge({ status, label }: { status: VerificationStatus; label?: string }) {
  return <Pill className={VERIFICATION_STYLES[status]}>{label ?? status}</Pill>;
}

const DOCUMENT_STYLES: Record<DocumentStatus, string> = {
  pending: "chip-warn",
  approved: "chip-ok",
  rejected: "chip-danger",
};

export function DocumentBadge({ status }: { status: DocumentStatus }) {
  return <Pill className={DOCUMENT_STYLES[status]}>{status}</Pill>;
}

const INVOICE_STYLES: Record<InvoiceStatus, string> = {
  draft: "chip-muted",
  issued: "chip-info",
  paid: "chip-ok",
  void: "chip-muted",
};

export function InvoiceBadge({ status, label }: { status: InvoiceStatus; label?: string }) {
  return <Pill className={INVOICE_STYLES[status]}>{label ?? status}</Pill>;
}

export function Pill({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${className}`}>{children}</span>
  );
}

export function Stat({
  label,
  value,
  tone = "default",
  href,
}: {
  label: string;
  value: number;
  tone?: "default" | "alert";
  href?: string;
}) {
  const body = (
    <div className="rounded-lg border border-line bg-surface p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">{label}</p>
      <p className={`mt-1 text-2xl font-semibold ${tone === "alert" && value > 0 ? "text-brand" : "text-ink"}`}>
        {value}
      </p>
    </div>
  );
  return href ? (
    <a href={href} className="block transition hover:opacity-80">
      {body}
    </a>
  ) : (
    body
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <p className="py-10 text-center text-sm text-ink-subtle">{children}</p>;
}

export function ErrorNote({ children }: { children: ReactNode }) {
  return <p className="rounded-md bg-danger/10 px-3 py-2 text-sm text-danger">{children}</p>;
}

export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-ink-muted">{label}</dt>
      <dd className="mt-0.5 text-sm">{value || "—"}</dd>
    </div>
  );
}

/** The unclaimed queue is the one thing the panel must never let slide (section 5). */
export function AlertBanner({ children, href }: { children: ReactNode; href?: string }) {
  const content = (
    <div className="flex items-center justify-between gap-3 rounded-lg border border-danger/40 bg-danger/10 px-4 py-3 text-sm text-danger">
      {children}
    </div>
  );
  return href ? <a href={href}>{content}</a> : content;
}

export function LiveDot({ connected }: { connected: boolean }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-ink-muted">
      <span
        className={`h-2 w-2 rounded-full ${connected ? "bg-success" : "bg-line-strong"}`}
        aria-hidden
      />
      {connected ? "Live" : "Reconnecting…"}
    </span>
  );
}
