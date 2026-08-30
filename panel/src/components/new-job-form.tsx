"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { api, fieldError } from "@/lib/client-api";
import { Button, ErrorNote, Field, Input, Select, Textarea } from "@/components/ui";
import type { ConfirmationPath, JobDetail, Vehicle } from "@/types/api";

interface PublicConfig {
  issue_types: { value: string; label: string }[];
  out_of_area_message: string;
}

interface Coverage {
  covered: boolean;
  area: string | null;
  message: string;
}

/**
 * Manual entry — the phone-in path (specification 4.5 and 15, phase 3).
 *
 * Section 4.4 applies here too: a position is required, because a postcode is not
 * enough for a technician to find a car on a dual carriageway. The office takes the
 * coordinates from the caller's phone, from a map, or from what3words read aloud.
 */
export function NewJobForm({ onCreated }: { onCreated: () => void }) {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [plate, setPlate] = useState("");
  const [vehicle, setVehicle] = useState<Vehicle | null>(null);
  const [confirmationPath, setConfirmationPath] = useState<ConfirmationPath>("confirmed");
  const [tyreSize, setTyreSize] = useState("");
  const [latitude, setLatitude] = useState("");
  const [longitude, setLongitude] = useState("");
  const [coverage, setCoverage] = useState<Coverage | null>(null);

  const config = useQuery({
    queryKey: ["public-config"],
    queryFn: () => api<PublicConfig>("/public/config"),
    staleTime: 5 * 60_000,
  });

  const lookup = useMutation({
    mutationFn: (registration: string) =>
      api<Vehicle>(`/vehicles/${encodeURIComponent(registration.replace(/\s/g, ""))}`),
    onSuccess: (data) => {
      setVehicle(data);
      setTyreSize(data.tyre_size_front);
    },
  });

  const checkCoverage = useMutation({
    mutationFn: (point: { latitude: string; longitude: string }) =>
      api<Coverage>("/public/coverage", { method: "POST", body: JSON.stringify(point) }),
    onSuccess: setCoverage,
  });

  const create = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      api<JobDetail>("/jobs", { method: "POST", body: JSON.stringify(payload) }),
    onSuccess: (job) => {
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
      onCreated();
      router.push(`/jobs/${job.id}`);
    },
  });

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);

    create.mutate({
      source: "phone",
      plate,
      contact_name: form.get("contact_name"),
      contact_phone: form.get("contact_phone"),
      contact_email: form.get("contact_email") || "",
      issue_type: form.get("issue_type"),
      description: form.get("description") || "",
      location_text: form.get("location_text") || "",
      latitude,
      longitude,
      location_source: "staff",
      tyre_confirmation: {
        confirmation_path: confirmationPath,
        tyre_size: tyreSize,
        // Staff took the caller's word for it; the record says so either way (4.3).
        disclaimer_accepted: confirmationPath === "overridden",
      },
    });
  }

  return (
    <form className="space-y-4" onSubmit={submit}>
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field label="Registration" error={fieldError(create.error, "plate")}>
            <div className="flex gap-2">
              <Input
                value={plate}
                onChange={(event) => setPlate(event.target.value.toUpperCase())}
                placeholder="AB12 CDE"
                className="font-mono tracking-widest"
              />
              <Button
                type="button"
                variant="secondary"
                onClick={() => lookup.mutate(plate)}
                disabled={!plate || lookup.isPending}
              >
                {lookup.isPending ? "…" : "Look up"}
              </Button>
            </div>
          </Field>
        </div>
        <Field label="Tyre size" hint={vehicle ? `DVLA: ${vehicle.description}` : undefined}>
          <Input value={tyreSize} onChange={(event) => setTyreSize(event.target.value)} placeholder="205/55R16" />
        </Field>
      </div>

      {vehicle ? (
        <div className="rounded-md border border-line bg-surface p-3 text-sm">
          <p className="font-medium">{vehicle.description || "Vehicle found"}</p>
          <p className="text-xs text-ink-muted">
            Looked-up fitment: {vehicle.tyre_size_front || "none returned"}
            {vehicle.is_fitment_ambiguous ? " · more than one fitment for this model" : ""}
          </p>
          <div className="mt-2 flex gap-4 text-xs">
            <label className="flex items-center gap-1.5">
              <input
                type="radio"
                checked={confirmationPath === "confirmed"}
                onChange={() => {
                  setConfirmationPath("confirmed");
                  setTyreSize(vehicle.tyre_size_front);
                }}
              />
              Caller confirmed this size
            </label>
            <label className="flex items-center gap-1.5">
              <input
                type="radio"
                checked={confirmationPath === "overridden"}
                onChange={() => setConfirmationPath("overridden")}
              />
              Caller gave a different size
            </label>
          </div>
          {confirmationPath === "overridden" ? (
            <p className="mt-2 text-xs text-brand">
              Recorded as customer-supplied. Both figures are kept against the job.
            </p>
          ) : null}
        </div>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="Name" error={fieldError(create.error, "contact_name")}>
          <Input name="contact_name" required />
        </Field>
        <Field label="Phone" error={fieldError(create.error, "contact_phone")}>
          <Input name="contact_phone" required placeholder="07700 900123" />
        </Field>
        <Field label="Email (optional)">
          <Input name="contact_email" type="email" />
        </Field>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="Issue" error={fieldError(create.error, "issue_type")}>
          <Select name="issue_type" required defaultValue="">
            <option value="" disabled>
              Choose…
            </option>
            {(config.data?.issue_types ?? []).map((issue) => (
              <option key={issue.value} value={issue.value}>
                {issue.label}
              </option>
            ))}
          </Select>
        </Field>
        <div className="sm:col-span-2">
          <Field label="Where are they?" error={fieldError(create.error, "location_text")}>
            <Input name="location_text" placeholder="Hard shoulder, A40 westbound, before Perivale" />
          </Field>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="Latitude" error={fieldError(create.error, "location")}>
          <Input
            value={latitude}
            onChange={(event) => setLatitude(event.target.value)}
            placeholder="51.5074"
            required
          />
        </Field>
        <Field label="Longitude">
          <Input
            value={longitude}
            onChange={(event) => setLongitude(event.target.value)}
            placeholder="-0.1278"
            required
            onBlur={() => {
              if (latitude && longitude) checkCoverage.mutate({ latitude, longitude });
            }}
          />
        </Field>
        <div className="flex items-end">
          <p className="text-xs text-ink-subtle">
            A position is required — a postcode will not do (section 4.4).
          </p>
        </div>
      </div>

      {coverage ? (
        <p className={`text-sm ${coverage.covered ? "text-success" : "text-brand"}`}>
          {coverage.covered
            ? `Inside ${coverage.area ?? "the service area"}.`
            : coverage.message || config.data?.out_of_area_message}
        </p>
      ) : null}

      <Field label="Notes">
        <Textarea name="description" rows={2} placeholder="Nearside front, flat. Two children in the car." />
      </Field>

      {create.isError ? <ErrorNote>{create.error.message}</ErrorNote> : null}

      <div className="flex gap-2">
        <Button type="submit" disabled={create.isPending}>
          {create.isPending ? "Creating…" : "Create job"}
        </Button>
        <Button type="button" variant="ghost" onClick={onCreated}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
