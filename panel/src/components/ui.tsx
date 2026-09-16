"use client";

import {
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
  useEffect,
  useRef,
  useState,
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
      <span className="text-sm font-medium text-ink-muted">{label}</span>
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
    <section className="rounded-lg border border-line bg-surface">
      {title ? (
        <header className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-4 py-3">
          <h2 className="font-display text-base font-semibold tracking-tight">{title}</h2>
          {action ? <div className="flex flex-shrink-0 items-center">{action}</div> : null}
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

/**
 * An unknown status still has to be visible.
 *
 * A value the panel does not recognise — a row left behind by an older schema,
 * or a status added to the API before the panel caught up — used to resolve to
 * no chip class and no label, and drew an empty cell. On this board an empty
 * status cell reads as "nothing to do here", which is the one conclusion it must
 * never invite. It gets the muted chip and its own raw value instead, so it is
 * legible as something to go and look at.
 */
export function StatusBadge({ status, label }: { status: JobStatus; label?: string }) {
  const style = JOB_STATUS_STYLES[status] ?? "chip-muted";
  return <Pill className={style}>{label || status || "unknown"}</Pill>;
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
  tone?: "default" | "alert" | "good";
  href?: string;
}) {
  const alarmed = tone === "alert" && value > 0;
  const changed = useValueChanged(value);

  const colour = alarmed ? "text-danger" : tone === "good" && value > 0 ? "text-success" : "text-ink";
  const flash = changed ? (alarmed ? "count-changed-alarm" : "count-changed") : "";

  const body = (
    <div className={`rounded-md px-4 py-3 ${flash}`}>
      <p className={`count ${colour}`}>{value}</p>
      <span className="count-label">{label}</span>
    </div>
  );
  return href ? (
    <a href={href} className="block rounded-md transition hover:bg-surface-raised">
      {body}
    </a>
  ) : (
    body
  );
}

/**
 * True for one beat after `value` moves.
 *
 * A count that changes while nobody is looking at it changes silently, and on a
 * wallboard that is most of the time. The flash is the whole point of the hook:
 * it is a single pass, not a loop, so it catches an eye that was elsewhere and
 * then stops rather than becoming part of the furniture. The first render never
 * flashes — arriving at the page is not a change.
 */
function useValueChanged(value: number, ms = 1100): boolean {
  const previous = useRef<number | null>(null);
  const [changed, setChanged] = useState(false);

  useEffect(() => {
    const had = previous.current;
    previous.current = value;
    if (had === null || had === value) return;

    setChanged(true);
    const timer = window.setTimeout(() => setChanged(false), ms);
    return () => window.clearTimeout(timer);
  }, [value, ms]);

  return changed;
}

/**
 * The counts, as one ruled strip rather than a row of identical cards.
 *
 * Six bordered boxes gave a stranded motorist the same weight as the number of
 * vans on shift. Hairlines between figures cost nothing, and they let the one
 * number that is an alarm be the only one wearing a colour.
 *
 * `inset` drops the strip's own border and corners for when it sits inside a
 * container that already has them — the dispatch hero — so the two do not draw
 * a double rule between the alarm and the counts.
 */
export function StatStrip({ children, inset = false }: { children: ReactNode; inset?: boolean }) {
  const frame = inset ? "h-full" : "rounded-lg border border-line";
  return (
    <div
      className={`grid grid-cols-2 divide-y divide-line bg-surface sm:grid-cols-3 sm:divide-x sm:divide-y-0 lg:grid-cols-5 ${frame}`}
    >
      {children}
    </div>
  );
}

/**
 * A registration, drawn as the plate it is — black on the brand yellow, which is
 * the one gold fill on the board and so the thing the eye lands on first.
 * `size="lg"` is for a job's own page, where the plate heads the record.
 */
export function Plate({ value, size = "sm" }: { value: string | null | undefined; size?: "sm" | "lg" }) {
  const plate = (value ?? "").trim().toUpperCase();
  const classes = `plate ${size === "lg" ? "plate-lg" : ""} ${plate ? "" : "plate-empty"}`;
  return <span className={classes}>{plate || "no plate"}</span>;
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <div className="py-12 text-center text-sm text-ink-subtle">{children}</div>;
}

export function ErrorNote({ children }: { children: ReactNode }) {
  return (
    <p className="rounded-md border border-danger/30 bg-danger/10 px-3 py-2 text-sm text-danger">
      {children}
    </p>
  );
}

export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div>
      <dt className="text-xs text-ink-subtle">{label}</dt>
      <dd className="mt-0.5 text-sm text-ink">{value || "—"}</dd>
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
