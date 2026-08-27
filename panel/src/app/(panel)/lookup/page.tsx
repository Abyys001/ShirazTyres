"use client";

import { useMutation } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, EmptyState, Field, Input } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime } from "@/lib/format";
import type { Vehicle } from "@/types/api";

export default function LookupPage() {
  const [plate, setPlate] = useState("");

  const lookup = useMutation({
    mutationFn: (registration: string) =>
      api<Vehicle>(`/vehicle-lookup/${encodeURIComponent(registration.replace(/\s/g, ""))}`),
  });

  const vehicle = lookup.data;

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <Card title="Vehicle & tyre lookup">
        <form
          className="flex flex-wrap items-end gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            lookup.mutate(plate);
          }}
        >
          <div className="w-56">
            <Field label="Registration">
              <Input
                value={plate}
                onChange={(event) => setPlate(event.target.value.toUpperCase())}
                placeholder="AB12 CDE"
                className="font-mono tracking-widest"
                required
              />
            </Field>
          </div>
          <Button type="submit" disabled={lookup.isPending}>
            {lookup.isPending ? "Looking up…" : "Look up"}
          </Button>
        </form>

        {lookup.isError ? (
          <p className="mt-3 rounded-md bg-brand-light px-3 py-2 text-sm text-brand-dark">{lookup.error.message}</p>
        ) : null}
      </Card>

      {vehicle ? (
        <Card title={`${vehicle.display_plate} — ${vehicle.description || "unknown vehicle"}`}>
          <dl className="grid gap-4 sm:grid-cols-2">
            <Detail label="Make / model" value={`${vehicle.make} ${vehicle.model}`.trim() || "—"} />
            <Detail label="Colour" value={vehicle.colour || "—"} />
            <Detail label="Fuel" value={vehicle.fuel_type || "—"} />
            <Detail label="Engine" value={vehicle.engine_capacity ? `${vehicle.engine_capacity}cc` : "—"} />
            <Detail label="Year" value={vehicle.year_of_manufacture?.toString() ?? "—"} />
            <Detail label="CO₂" value={vehicle.co2_emissions ? `${vehicle.co2_emissions} g/km` : "—"} />
            <Detail label="Tax" value={`${vehicle.tax_status || "—"} ${vehicle.tax_due_date ?? ""}`} />
            <Detail label="MOT" value={`${vehicle.mot_status || "—"} ${vehicle.mot_expiry_date ?? ""}`} />
          </dl>

          <div className="mt-5 rounded-md border border-slate-200 bg-slate-50 p-4">
            <h3 className="text-sm font-semibold">Tyres</h3>
            <dl className="mt-3 grid gap-4 sm:grid-cols-2">
              <Detail label="Front" value={vehicle.tyre_size_front || "unknown"} />
              <Detail label="Rear" value={vehicle.tyre_size_rear || "unknown"} />
              <Detail
                label="Load / speed"
                value={[vehicle.tyre_load_index, vehicle.tyre_speed_rating].filter(Boolean).join(" ") || "—"}
              />
              <Detail
                label="Pressures"
                value={
                  vehicle.tyre_pressure_front_psi
                    ? `${vehicle.tyre_pressure_front_psi} / ${vehicle.tyre_pressure_rear_psi} psi`
                    : "—"
                }
              />
            </dl>

            {vehicle.tyre_size_options.length > 1 ? (
              <p className="mt-3 text-xs text-ink-muted">
                Other fitments recorded for this model: {vehicle.tyre_size_options.join(", ")}. Confirm with the
                driver before ordering — trims differ.
              </p>
            ) : null}

            <p className="mt-3 text-xs text-ink-muted">
              Source: {vehicle.tyre_source} · DVLA data {formatDateTime(vehicle.dvla_fetched_at)}
            </p>
            {vehicle.lookup_error ? (
              <p className="mt-2 text-xs text-brand">Partial result: {vehicle.lookup_error}</p>
            ) : null}
          </div>
        </Card>
      ) : (
        <EmptyState>Enter a registration to pull DVLA details and the manufacturer tyre sizes.</EmptyState>
      )}
    </div>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-ink-muted">{label}</dt>
      <dd className="mt-0.5 text-sm">{value}</dd>
    </div>
  );
}
