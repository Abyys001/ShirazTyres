"use client";

import { useQuery } from "@tanstack/react-query";

import { api } from "@/lib/client-api";
import type { HealthSnapshot } from "@/types/api";

const LABELS: Record<string, string> = {
  database: "Database",
  cache: "Cache",
  channel_layer: "Realtime",
  celery: "Background jobs",
};

const PROVIDER_LABELS: Record<string, string> = {
  sms: "SMS",
  push: "Push",
  email: "Email",
  routing: "Routing",
  vehicle_lookup: "Vehicle lookup",
  google_oauth: "Google sign-in",
  stripe: "Stripe",
  map_tiles: "Map tiles",
};

/**
 * Is the system actually working, rather than merely running?
 *
 * Every row here is a real round trip made when the page loaded — a `SELECT 1`,
 * a write-then-read through the cache, a Celery `ping` that only answers if a
 * worker is actually alive. A URL
 * in the environment proves nothing, and on a dispatch system the gap between
 * "configured" and "answering" is the whole question: the board looks perfectly
 * healthy while offers fail to reach anybody.
 *
 * The mocked providers get their own row for the same reason. Everything stubbed
 * is indistinguishable from everything working, right up until a real customer
 * is waiting for a text message that was never going to be sent.
 */
export function HealthStrip() {
  const health = useQuery({
    queryKey: ["health"],
    queryFn: () => api<HealthSnapshot>("/health"),
    refetchInterval: 30_000,
  });

  if (health.isLoading) {
    return <div className="h-20 animate-pulse rounded-lg border border-line bg-surface-raised" />;
  }
  if (health.isError || !health.data) {
    return (
      <div className="rounded-lg border border-danger/40 bg-danger/5 px-4 py-3 text-sm text-danger">
        The API did not answer the health check. That is itself the answer — the backend is
        unreachable from the panel.
      </div>
    );
  }

  const data = health.data;
  const checks = Object.entries(data.checks);

  return (
    <div
      className={`overflow-hidden rounded-lg border bg-surface ${
        data.ok ? "border-line" : "border-danger/50"
      }`}
    >
      <div className="grid gap-px bg-line sm:grid-cols-2 lg:grid-cols-4">
        {checks.map(([key, check]) => (
          <div key={key} className="bg-surface px-4 py-3">
            <div className="flex items-center gap-2">
              <span
                className={`h-2.5 w-2.5 shrink-0 rounded-full ${
                  check.ok ? "bg-success" : "bg-danger"
                }`}
              />
              <span className="text-sm font-medium text-ink">{LABELS[key] ?? key}</span>
              <span className="ml-auto font-mono text-xs tabular-nums text-ink-subtle">
                {check.ms}ms
              </span>
            </div>
            <p
              className={`mt-1 break-words text-xs ${
                check.ok ? "text-ink-muted" : "text-danger"
              }`}
            >
              {check.detail || (check.ok ? "responding" : "not responding")}
            </p>
          </div>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-line px-4 py-3">
        <span className="text-xs font-medium uppercase tracking-wider text-ink-subtle">
          Integrations
        </span>
        {Object.entries(data.providers).map(([key, provider]) => (
          <span
            key={key}
            className="flex items-center gap-1.5 text-xs"
            title={`${PROVIDER_LABELS[key] ?? key}: ${provider.mode}`}
          >
            <span
              className={`h-1.5 w-1.5 rounded-full ${
                provider.live ? "bg-success" : "bg-warning"
              }`}
            />
            <span className="text-ink-muted">{PROVIDER_LABELS[key] ?? key}</span>
            <span className={provider.live ? "text-ink-subtle" : "text-warning"}>
              {provider.live ? "live" : "mock"}
            </span>
          </span>
        ))}
      </div>

      {data.mocked.length > 0 ? (
        <p className="border-t border-line bg-warning/5 px-4 py-2 text-xs text-warning">
          {data.mocked.length} integration{data.mocked.length === 1 ? " is" : "s are"} still
          stubbed. Nothing sent through {data.mocked.length === 1 ? "it" : "them"} reaches the
          outside world.
        </p>
      ) : null}
    </div>
  );
}
