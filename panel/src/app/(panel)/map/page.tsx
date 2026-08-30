"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useCallback } from "react";

import { Card, EmptyState, LiveDot, VerificationBadge } from "@/components/ui";
import { api } from "@/lib/client-api";
import { fixAge } from "@/lib/format";
import { usePanelFeed } from "@/lib/ws";
import type { DriverMapRow } from "@/types/api";

// Leaflet touches `window` on import, so it can only load in the browser.
const DriverMap = dynamic(() => import("@/components/driver-map").then((m) => m.DriverMap), {
  ssr: false,
  loading: () => <div className="h-[70vh] w-full animate-pulse rounded-lg bg-surface-raised" />,
});

export default function MapPage() {
  const queryClient = useQueryClient();

  const connected = usePanelFeed(
    useCallback(
      (event) => {
        if (event.event === "driver.location") {
          void queryClient.invalidateQueries({ queryKey: ["driver-map"] });
        }
      },
      [queryClient],
    ),
  );

  const drivers = useQuery({
    queryKey: ["driver-map"],
    queryFn: () => api<DriverMapRow[]>("/drivers/map"),
    refetchInterval: connected ? 30_000 : 10_000,
  });

  const rows = drivers.data ?? [];

  return (
    <div className="grid gap-6 lg:grid-cols-4">
      <div className="lg:col-span-3">
        <DriverMap drivers={rows} />
        <p className="mt-2 text-xs text-ink-subtle">
          Positions are only recorded while a driver is online (section 11.1) and never reach a customer
          surface.
        </p>
      </div>

      <Card title={`Online (${rows.length})`} action={<LiveDot connected={connected} />}>
        {rows.length === 0 ? <EmptyState>Nobody is online.</EmptyState> : null}
        <ul className="space-y-3">
          {rows.map((driver) => (
            <li key={driver.id} className="border-b border-line pb-2 last:border-0">
              <Link href={`/drivers/${driver.id}`} className="text-sm font-medium text-brand hover:underline">
                {driver.name}
              </Link>
              <p className="text-xs text-ink-muted">
                {driver.vehicle_plate || "no van recorded"} · {fixAge(driver.location_updated_at)}
              </p>
              <p className="mt-1 flex items-center gap-2 text-xs">
                <VerificationBadge status={driver.verification_status} />
                {driver.active_jobs > 0 ? "on a job" : "free"}
              </p>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
