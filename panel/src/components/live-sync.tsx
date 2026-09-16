"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";

import { useLiveStatus, usePanelFeed, type PanelEvent } from "@/lib/ws";
import type { DriverMapRow } from "@/types/api";

/**
 * The panel's one subscription to the API, mounted once for the whole app.
 *
 * Every page reads through TanStack Query, so keeping the panel current is a
 * question of which cache keys an event invalidates — not of each page
 * remembering to open a socket. A page added later is live by default; the only
 * thing it has to do is use a key listed here.
 *
 * Keys are matched by prefix, so ["job"] covers ["job", 41].
 */
const INVALIDATIONS: Array<{ prefix: string; keys: string[][] }> = [
  {
    prefix: "job.",
    keys: [["jobs"], ["job-stats"], ["job"], ["invoices"], ["driver-map"], ["job-map"]],
  },
  {
    prefix: "dispatch.",
    keys: [["jobs"], ["job-stats"], ["job"], ["candidates"], ["job-map"]],
  },
  {
    prefix: "driver.",
    keys: [["drivers"], ["driver"], ["compliance"], ["driver-map"]],
  },
  {
    prefix: "offer.",
    keys: [["jobs"], ["job"], ["candidates"]],
  },
  {
    prefix: "invoice.",
    keys: [["invoices"], ["job"], ["jobs"]],
  },
  /*
   * The catalogue the office works from. Two people on the settings screen used
   * to overwrite each other silently — the second save went in against a copy
   * fetched before the first one, and neither screen said so. The price list,
   * the service areas and the staff list have the same problem in a quieter way.
   *
   * These change rarely, so the event carries only its kind and every reader
   * refetches. The public config is in the list because the call-out fee and the
   * issue types the customer surfaces show are drawn from the same settings.
   */
  {
    prefix: "config.",
    keys: [
      ["settings"],
      ["service-items"],
      ["service-areas"],
      ["staff"],
      ["public-config"],
      ["health"],
    ],
  },
];

/**
 * `driver.location` carries the whole new position, so it is applied to the
 * cache rather than used as a signal to go and ask for one.
 *
 * Four vans pinging every few seconds turned into four `GET /drivers/map` round
 * trips a second, each re-fetching every driver to move one pin — and the map
 * still only updated as fast as the slowest of them came back. Writing the
 * payload straight into the cache moves the pin on arrival and leaves the
 * network for things that actually changed.
 */
function applyDriverLocation(queryClient: ReturnType<typeof useQueryClient>, event: PanelEvent) {
  const driverId = event.driver_id;
  if (typeof driverId !== "number") return;

  queryClient.setQueriesData<DriverMapRow[]>({ queryKey: ["driver-map"] }, (rows) => {
    if (!rows) return rows;
    let touched = false;
    const next = rows.map((row) => {
      if (row.id !== driverId) return row;
      touched = true;
      return {
        ...row,
        latitude: asText(event.latitude) ?? row.latitude,
        longitude: asText(event.longitude) ?? row.longitude,
        location_accuracy_m:
          typeof event.accuracy_m === "number" ? event.accuracy_m : row.location_accuracy_m,
        location_updated_at: asText(event.recorded_at) ?? row.location_updated_at,
      };
    });

    // A driver who has just come on shift is not in the list yet. Let the query
    // refetch rather than invent a row from a payload that has no name or plate.
    if (!touched) {
      void queryClient.invalidateQueries({ queryKey: ["driver-map"] });
      return rows;
    }
    return next;
  });
}

function asText(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export function LiveSync() {
  const queryClient = useQueryClient();

  usePanelFeed(
    useCallback(
      (event: PanelEvent) => {
        if (event.event === "driver.location") {
          applyDriverLocation(queryClient, event);
          return;
        }

        for (const rule of INVALIDATIONS) {
          if (!event.event.startsWith(rule.prefix)) continue;
          for (const key of rule.keys) {
            void queryClient.invalidateQueries({ queryKey: key });
          }
        }
      },
      [queryClient],
    ),
  );

  return null;
}

/**
 * The one place the office is told the panel has stopped being live.
 *
 * Silence looks identical to "nothing is happening", which on a dispatch board is
 * the dangerous reading — so a dropped socket says so rather than leaving a
 * screen that quietly stopped moving.
 */
export function LiveBadge() {
  const connected = useLiveStatus();

  return (
    <span
      className="hidden items-center gap-1.5 text-xs text-ink-muted sm:flex"
      title={connected ? "Live — updates arrive as they happen" : "Reconnecting — falling back to polling"}
    >
      <span
        className={`h-2 w-2 rounded-full ${connected ? "bg-success" : "animate-pulse bg-warning"}`}
      />
      {connected ? "Live" : "Reconnecting"}
    </span>
  );
}
