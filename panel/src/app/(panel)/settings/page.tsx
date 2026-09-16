"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";

import { HealthStrip } from "@/components/health-strip";
import { PriceList } from "@/components/price-list";
import { ServiceAreas } from "@/components/service-areas";
import { SettingsForm } from "@/components/settings-form";
import { StaffManager } from "@/components/staff-manager";
import { Button, Card, EmptyState } from "@/components/ui";
import { api } from "@/lib/client-api";
import type { SettingsDocument, StaffUser } from "@/types/api";

/**
 * Each section, and the sentence that says what changing it will do.
 *
 * The blurbs are not decoration. These settings move real behaviour — dispatch
 * radius decides who gets offered a job, the VAT rate lands on every invoice
 * printed afterwards — and a list of labelled inputs gives no sense of that.
 */
const GROUPS: { value: string; label: string; blurb: string }[] = [
  {
    value: "dispatch",
    label: "Dispatch",
    blurb: "How a call-out finds a driver: which mode, how wide, how long before it escalates.",
  },
  {
    value: "pricing",
    label: "Pricing",
    blurb: "The call-out fee, the VAT rate, and the price list the driver invoices from.",
  },
  {
    value: "service_areas",
    label: "Service areas",
    blurb: "Where you cover. A request outside every active area is refused, not queued.",
  },
  {
    value: "drivers",
    label: "Drivers",
    blurb: "What a driver must produce to be approved, and when an expiring document suspends them.",
  },
  {
    value: "notifications",
    label: "Notifications",
    blurb: "Who gets told what, and through which channel.",
  },
  {
    value: "operational",
    label: "Operational",
    blurb: "Business hours, the problems a customer can report, and the cancellation rules.",
  },
  {
    value: "staff",
    label: "Staff",
    blurb: "Who can sign in to this panel, and what each of them is allowed to do.",
  },
  {
    value: "system",
    label: "System",
    blurb: "Whether the system is actually working, and everything it has recorded doing.",
  },
];

export default function SettingsPage() {
  const [group, setGroup] = useState("dispatch");

  const settings = useQuery({
    queryKey: ["settings"],
    queryFn: () => api<SettingsDocument>("/settings"),
  });

  const me = useQuery({
    queryKey: ["staff-me"],
    queryFn: () => api<StaffUser>("/auth/staff/me"),
  });

  const active = GROUPS.find((option) => option.value === group);

  if (settings.isLoading) return <EmptyState>Loading…</EmptyState>;
  if (settings.isError || !settings.data) return <EmptyState>Could not load settings.</EmptyState>;

  const specs = settings.data.specs.filter((spec) => spec.group === group);

  return (
    <div className="grid gap-6 lg:grid-cols-[13rem_minmax(0,1fr)]">
      {/*
       * A rail rather than a row of buttons. Eight sections wrapped onto two
       * lines and the selected one moved as the window resized, which made the
       * page feel like it had rearranged itself between visits.
       */}
      <nav className="flex gap-1 overflow-x-auto lg:sticky lg:top-20 lg:h-fit lg:flex-col lg:overflow-visible">
        {GROUPS.map((option) => {
          const current = group === option.value;
          return (
            <button
              key={option.value}
              onClick={() => setGroup(option.value)}
              aria-current={current ? "page" : undefined}
              className={`shrink-0 rounded-md px-3 py-2 text-left text-sm transition lg:shrink ${
                current
                  ? "bg-brand/10 font-medium text-brand"
                  : "text-ink-muted hover:bg-surface-raised hover:text-ink"
              }`}
            >
              {option.label}
            </button>
          );
        })}
      </nav>

      <div className="min-w-0 space-y-5">
        <header>
          <h2 className="font-display text-xl font-semibold tracking-tight">{active?.label}</h2>
          <p className="mt-1 max-w-2xl text-sm text-ink-muted">{active?.blurb}</p>
        </header>

        {specs.length > 0 ? (
          <Card>
            <SettingsForm specs={specs} values={settings.data.values} />
          </Card>
        ) : null}

        {group === "pricing" ? <PriceList /> : null}
        {group === "service_areas" ? <ServiceAreas /> : null}
        {group === "staff" && me.data ? <StaffManager me={me.data} /> : null}
        {group === "system" ? <SystemPanel /> : null}
      </div>
    </div>
  );
}

/**
 * The health of the thing, and the way into its log.
 *
 * The log opens in its own window rather than as a page here: it gets read
 * alongside the board while something is going wrong, and a tab that replaces
 * the jobs queue at exactly that moment is the wrong trade.
 */
function SystemPanel() {
  return (
    <div className="space-y-4">
      <HealthStrip />
      <Card title="System log">
        <p className="mb-3 max-w-2xl text-sm text-ink-muted">
          Every verification code issued, text and email sent, setting changed, job moved and
          payment callback received — kept, searchable, and outliving a container restart.
        </p>
        <Button
          onClick={() => window.open("/logs", "shiraztyres-logs", "width=1280,height=900,noopener")}
        >
          Open the log
        </Button>
      </Card>
    </div>
  );
}
