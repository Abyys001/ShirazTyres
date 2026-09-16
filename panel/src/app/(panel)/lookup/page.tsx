"use client";

import { useMutation } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, Input, Pill, Plate } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime } from "@/lib/format";
import type { Vehicle } from "@/types/api";

/**
 * Look a registration up, and read the answer from across the desk.
 *
 * This screen is used with a customer on the phone, so the two things being read
 * aloud — the plate and the tyre size — are set far larger than anything else
 * and given the whole width. Everything DVLA returns is still here; it is simply
 * no longer competing with the two figures that matter.
 */
export default function LookupPage() {
  const [plate, setPlate] = useState("");

  // The staff endpoint, not the public one: it answers for a plate the office has
  // never seen, it is not throttled at the anonymous rate, and it can force a refresh.
  const lookup = useMutation({
    mutationFn: (registration: string) =>
      api<Vehicle>(`/vehicles/${encodeURIComponent(registration.replace(/\s/g, ""))}`),
  });

  const vehicle = lookup.data;

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Card>
        <form
          className="flex flex-wrap items-end gap-4"
          onSubmit={(event) => {
            event.preventDefault();
            lookup.mutate(plate);
          }}
        >
          <label className="block flex-1 min-w-[16rem]">
            <span className="mb-1.5 block text-sm font-medium text-ink-muted">Registration</span>
            {/*
             * Typed as the plate it is. A registration read out over a bad line
             * gets mistyped, and at this size a wrong character is visible
             * before the lookup is sent rather than after it comes back empty.
             */}
            <Input
              value={plate}
              onChange={(event) => setPlate(event.target.value.toUpperCase())}
              placeholder="AB12 CDE"
              className="h-16 text-center font-mono text-3xl font-bold uppercase tracking-[0.2em]"
              autoFocus
              required
            />
          </label>
          <Button type="submit" disabled={lookup.isPending} className="h-16 px-8 text-base">
            {lookup.isPending ? "Looking up…" : "Look up"}
          </Button>
        </form>

        {lookup.isError ? (
          <p className="mt-4 rounded-md border border-danger/40 bg-danger/5 px-3 py-2 text-sm text-danger">
            {lookup.error.message}
          </p>
        ) : null}
      </Card>

      {vehicle ? (
        <>
          {/* The two figures read aloud on the phone, and nothing else. */}
          <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
            <Card>
              <div className="flex flex-col items-center gap-4 py-2">
                <Plate value={vehicle.display_plate} size="lg" />
                <p className="text-center font-display text-xl font-semibold tracking-tight text-ink">
                  {vehicle.description || "Unknown vehicle"}
                </p>
                <div className="flex flex-wrap justify-center gap-2">
                  {vehicle.colour ? <Pill className="chip-muted">{vehicle.colour}</Pill> : null}
                  {vehicle.fuel_type ? <Pill className="chip-muted">{vehicle.fuel_type}</Pill> : null}
                  {vehicle.year_of_manufacture ? (
                    <Pill className="chip-muted">{vehicle.year_of_manufacture}</Pill>
                  ) : null}
                </div>
              </div>
            </Card>

            <Card>
              <p className="count-label">Tyre size the van is loaded from</p>
              <p className="mt-1 break-words font-mono text-4xl font-bold tabular-nums text-brand lg:text-5xl">
                {vehicle.tyre_size_front || "not known"}
              </p>
              {vehicle.tyre_size_rear && vehicle.tyre_size_rear !== vehicle.tyre_size_front ? (
                <p className="mt-2 text-sm text-warning">
                  Rear differs: <span className="font-mono">{vehicle.tyre_size_rear}</span>
                </p>
              ) : null}

              {vehicle.is_fitment_ambiguous || vehicle.tyre_size_options.length > 1 ? (
                <div className="mt-4 rounded-md border border-warning/40 bg-warning/5 px-3 py-2">
                  <p className="text-sm font-medium text-warning">
                    More than one fitment for this model
                  </p>
                  <p className="mt-1 text-sm text-ink-muted">
                    Also recorded:{" "}
                    <span className="font-mono">{vehicle.tyre_size_options.join(", ")}</span>. Confirm
                    with the customer before ordering — trims differ (section 9.3).
                  </p>
                </div>
              ) : null}
            </Card>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card title="Tyre specification">
              <dl className="grid gap-4 sm:grid-cols-2">
                <Detail label="Front" value={vehicle.tyre_size_front || "unknown"} mono />
                <Detail label="Rear" value={vehicle.tyre_size_rear || "unknown"} mono />
                <Detail
                  label="Load / speed"
                  value={
                    [vehicle.tyre_load_index, vehicle.tyre_speed_rating].filter(Boolean).join(" ") ||
                    "—"
                  }
                  mono
                />
                <Detail
                  label="Pressures"
                  value={
                    vehicle.tyre_pressure_front_psi
                      ? `${vehicle.tyre_pressure_front_psi} / ${vehicle.tyre_pressure_rear_psi} psi`
                      : "—"
                  }
                  mono
                />
              </dl>
              <p className="mt-4 border-t border-line pt-3 text-xs text-ink-subtle">
                Source: {vehicle.tyre_source} · DVLA data {formatDateTime(vehicle.dvla_fetched_at)}
              </p>
              {vehicle.lookup_error ? (
                <p className="mt-2 text-sm text-warning">Partial result: {vehicle.lookup_error}</p>
              ) : null}
            </Card>

            <Card title="On the DVLA record">
              <dl className="grid gap-4 sm:grid-cols-2">
                <Detail label="Make / model" value={`${vehicle.make} ${vehicle.model}`.trim() || "—"} />
                <Detail label="Colour" value={vehicle.colour || "—"} />
                <Detail label="Fuel" value={vehicle.fuel_type || "—"} />
                <Detail
                  label="Engine"
                  value={vehicle.engine_capacity ? `${vehicle.engine_capacity}cc` : "—"}
                />
                <Detail label="Year" value={vehicle.year_of_manufacture?.toString() ?? "—"} />
                <Detail
                  label="CO₂"
                  value={vehicle.co2_emissions ? `${vehicle.co2_emissions} g/km` : "—"}
                />
                <Detail
                  label="Tax"
                  value={`${vehicle.tax_status || "—"} ${vehicle.tax_due_date ?? ""}`.trim()}
                  tone={vehicle.tax_status?.toLowerCase().includes("untaxed") ? "warn" : undefined}
                />
                <Detail
                  label="MOT"
                  value={`${vehicle.mot_status || "—"} ${vehicle.mot_expiry_date ?? ""}`.trim()}
                  tone={vehicle.mot_status?.toLowerCase().includes("not valid") ? "warn" : undefined}
                />
              </dl>
            </Card>
          </div>
        </>
      ) : (
        <Card>
          <div className="py-12 text-center">
            <p className="text-base text-ink-muted">
              Enter a registration to pull the DVLA record and the manufacturer&rsquo;s tyre size.
            </p>
            <p className="mt-1 text-sm text-ink-subtle">
              Two separate sources — DVLA returns no tyre data of its own (section 9.1).
            </p>
          </div>
        </Card>
      )}
    </div>
  );
}

function Detail({
  label,
  value,
  mono = false,
  tone,
}: {
  label: string;
  value: string;
  mono?: boolean;
  tone?: "warn";
}) {
  return (
    <div>
      <dt className="text-xs text-ink-subtle">{label}</dt>
      <dd
        className={`mt-0.5 text-sm ${mono ? "font-mono" : ""} ${
          tone === "warn" ? "text-warning" : "text-ink"
        }`}
      >
        {value}
      </dd>
    </div>
  );
}
