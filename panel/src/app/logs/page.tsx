"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";

import { HealthStrip } from "@/components/health-strip";
import { Button, EmptyState, Input, Pill, Select } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime, timeAgo } from "@/lib/format";
import type { AuditEvent, AuditSeverity, AuditSummary, Paginated } from "@/types/api";

const CATEGORIES = [
  { value: "", label: "Everything" },
  { value: "auth", label: "Sign-in & OTP" },
  { value: "sms", label: "SMS" },
  { value: "email", label: "Email" },
  { value: "push", label: "Push" },
  { value: "job", label: "Jobs" },
  { value: "dispatch", label: "Dispatch" },
  { value: "billing", label: "Billing" },
  { value: "stripe", label: "Stripe" },
  { value: "settings", label: "Settings" },
  { value: "driver", label: "Drivers" },
  { value: "staff", label: "Staff" },
  { value: "system", label: "System" },
];

const SEVERITY_STYLE: Record<AuditSeverity, string> = {
  debug: "chip-muted",
  info: "chip-info",
  warning: "chip-warn",
  error: "chip-danger",
};

/**
 * The log window (opened from Settings, deliberately its own tab).
 *
 * Until now the only record of an OTP being issued, an email failing, or a
 * setting changing at two in the morning was the container's stdout — gone the
 * moment it restarted, and unreachable to anybody without a shell. This is the
 * same information, kept, filterable, and readable by the person who actually
 * runs the business.
 *
 * It sits outside the panel's rail on purpose: it gets opened next to the board
 * rather than instead of it, and a sidebar in a second window is just a smaller
 * log.
 */
export default function LogsPage() {
  const [category, setCategory] = useState("");
  const [severity, setSeverity] = useState("");
  const [search, setSearch] = useState("");
  const [live, setLive] = useState(true);
  const [expanded, setExpanded] = useState<number | null>(null);

  const query = new URLSearchParams();
  if (category) query.set("category", category);
  if (severity) query.set("severity", severity);
  if (search.trim()) query.set("search", search.trim());

  const events = useQuery({
    queryKey: ["logs", category, severity, search],
    queryFn: () => api<Paginated<AuditEvent>>(`/logs?${query.toString()}`),
    refetchInterval: live ? 5_000 : false,
  });

  const summary = useQuery({
    queryKey: ["logs-summary"],
    queryFn: () => api<AuditSummary>("/logs/summary"),
    refetchInterval: live ? 30_000 : false,
  });

  const rows = events.data?.results ?? [];

  return (
    <div className="min-h-screen bg-canvas text-ink">
      <header className="sticky top-0 z-10 border-b border-line bg-canvas/90 px-5 py-3 backdrop-blur">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="font-display text-lg font-semibold tracking-tight">System log</h1>
          {summary.data ? (
            <span className="text-sm text-ink-subtle tabular-nums">
              {summary.data.total.toLocaleString()} events
            </span>
          ) : null}
          <div className="flex-1" />
          <button
            onClick={() => setLive((value) => !value)}
            className="flex items-center gap-1.5 rounded-md border border-line-strong px-2 py-1 text-xs text-ink-muted transition hover:text-ink"
            title={live ? "Refreshing every 5 seconds" : "Paused"}
          >
            <span
              className={`h-2 w-2 rounded-full ${live ? "live-dot bg-success" : "bg-ink-subtle"}`}
            />
            {live ? "Live" : "Paused"}
          </button>
          <Button size="sm" variant="secondary" onClick={() => void events.refetch()}>
            Refresh
          </Button>
        </div>
      </header>

      <main className="space-y-4 px-5 py-4">
        <HealthStrip />

        <div className="flex flex-wrap items-end gap-2">
          <label className="block">
            <span className="mb-1 block text-xs text-ink-subtle">Category</span>
            <Select
              value={category}
              onChange={(event) => setCategory(event.target.value)}
              className="w-48"
            >
              {CATEGORIES.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Select>
          </label>
          <label className="block">
            <span className="mb-1 block text-xs text-ink-subtle">Severity</span>
            <Select
              value={severity}
              onChange={(event) => setSeverity(event.target.value)}
              className="w-40"
            >
              <option value="">Any</option>
              <option value="info">Info</option>
              <option value="warning">Warning</option>
              <option value="error">Error</option>
              <option value="debug">Debug</option>
            </Select>
          </label>
          <label className="block min-w-[16rem] flex-1">
            <span className="mb-1 block text-xs text-ink-subtle">Search</span>
            <Input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="A phone number, a job reference, a name…"
            />
          </label>
          {category || severity || search ? (
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                setCategory("");
                setSeverity("");
                setSearch("");
              }}
            >
              Clear
            </Button>
          ) : null}
        </div>

        <div className="overflow-hidden rounded-lg border border-line bg-surface">
          {events.isLoading ? <EmptyState>Reading the log…</EmptyState> : null}
          {events.isError ? <EmptyState>The log could not be loaded.</EmptyState> : null}
          {events.data && rows.length === 0 ? (
            <EmptyState>Nothing matches this filter.</EmptyState>
          ) : null}

          {rows.length > 0 ? (
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-line text-left text-xs text-ink-subtle">
                  <th className="py-2 pl-4 pr-3 font-medium">When</th>
                  <th className="py-2 pr-3 font-medium">Category</th>
                  <th className="py-2 pr-3 font-medium">Level</th>
                  <th className="py-2 pr-3 font-medium">What happened</th>
                  <th className="py-2 pr-4 font-medium">Who</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((event) => {
                  const open = expanded === event.id;
                  const hasPayload = Object.keys(event.payload ?? {}).length > 0;
                  return (
                    <tr
                      key={event.id}
                      onClick={() => setExpanded(open ? null : event.id)}
                      className="cursor-pointer border-b border-line align-top last:border-0 hover:bg-surface-raised"
                    >
                      <td
                        className="whitespace-nowrap py-2 pl-4 pr-3 text-xs text-ink-muted"
                        title={formatDateTime(event.created_at)}
                      >
                        {timeAgo(event.created_at)}
                      </td>
                      <td className="py-2 pr-3">
                        <Pill className="chip-muted">{event.category_display}</Pill>
                      </td>
                      <td className="py-2 pr-3">
                        <Pill className={SEVERITY_STYLE[event.severity]}>{event.severity}</Pill>
                      </td>
                      <td className="py-2 pr-3">
                        <span className="block text-ink">{event.message}</span>
                        {open && hasPayload ? (
                          <pre className="mt-2 overflow-x-auto rounded-md bg-surface-sunken p-3 font-mono text-xs text-ink-muted">
                            {JSON.stringify(event.payload, null, 2)}
                          </pre>
                        ) : null}
                        {!open && hasPayload ? (
                          <span className="mt-0.5 block text-xs text-ink-subtle">
                            {Object.keys(event.payload).slice(0, 5).join(" · ")} — click for detail
                          </span>
                        ) : null}
                      </td>
                      <td className="whitespace-nowrap py-2 pr-4 text-xs text-ink-muted">
                        {event.actor || "—"}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          ) : null}
        </div>

        {events.data && events.data.count > rows.length ? (
          <p className="text-center text-xs text-ink-subtle">
            Showing the most recent {rows.length} of {events.data.count.toLocaleString()}. Narrow the
            filter to reach older events.
          </p>
        ) : null}
      </main>
    </div>
  );
}
