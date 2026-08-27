"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { use, useState } from "react";

import { Button, Card, EmptyState, Input, StatusBadge } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime } from "@/lib/format";
import type { Booking, BookingStatus } from "@/types/api";
import { NEXT_STATUSES, STATUS_LABELS } from "@/types/api";

export default function BookingDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");

  const booking = useQuery({
    queryKey: ["booking", id],
    queryFn: () => api<Booking>(`/bookings/${id}`),
    refetchInterval: 20_000,
  });

  const transition = useMutation({
    mutationFn: (status: BookingStatus) =>
      api<Booking>(`/bookings/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status, note }),
      }),
    onSuccess: (updated) => {
      queryClient.setQueryData(["booking", id], updated);
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      queryClient.invalidateQueries({ queryKey: ["booking-stats"] });
      setNote("");
    },
  });

  if (booking.isLoading) return <EmptyState>Loading…</EmptyState>;
  if (booking.isError || !booking.data) return <EmptyState>Call-out not found.</EmptyState>;

  const data = booking.data;
  const nextStatuses = NEXT_STATUSES[data.status];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/bookings" className="text-xs text-ink-muted hover:underline">
            ← All call-outs
          </Link>
          <h1 className="flex items-center gap-3 text-xl font-semibold">
            {data.reference}
            <StatusBadge status={data.status} label={STATUS_LABELS[data.status]} />
          </h1>
        </div>

        <div className="flex flex-wrap gap-2">
          {nextStatuses.map((status) => (
            <Button
              key={status}
              variant={status === "cancelled" ? "secondary" : "primary"}
              disabled={transition.isPending}
              onClick={() => transition.mutate(status)}
            >
              {status === "assigned"
                ? "Assign to me"
                : status === "completed"
                  ? "Mark complete"
                  : STATUS_LABELS[status]}
            </Button>
          ))}
          {nextStatuses.length === 0 ? (
            <span className="text-xs text-ink-muted">This call-out is closed.</span>
          ) : null}
        </div>
      </div>

      {transition.isError ? (
        <p className="rounded-md bg-brand-light px-3 py-2 text-sm text-brand-dark">{transition.error.message}</p>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <Card title="Customer">
            <dl className="grid gap-3 sm:grid-cols-2 text-sm">
              <Row label="Name" value={data.contact_name} />
              <Row label="Phone" value={<a href={`tel:${data.contact_phone}`} className="text-brand hover:underline">{data.contact_phone}</a>} />
              <Row label="Email" value={data.contact_email || "—"} />
              <Row label="Source" value={data.source} />
              <Row label="Issue" value={data.issue_display} />
              <Row label="Tyre size" value={data.tyre_size || "unknown"} />
            </dl>
            {data.description ? <p className="mt-3 rounded bg-slate-50 p-3 text-sm">{data.description}</p> : null}
          </Card>

          <Card
            title="Location"
            action={
              <a href={data.maps_url} target="_blank" rel="noreferrer" className="text-xs text-brand hover:underline">
                Open in Maps
              </a>
            }
          >
            <p className="text-sm">{data.location_text}</p>
            {data.latitude ? (
              <p className="mt-1 text-xs text-ink-muted">
                {data.latitude}, {data.longitude}
              </p>
            ) : null}
          </Card>

          <Card title="Vehicle">
            {data.vehicle ? (
              <dl className="grid gap-3 sm:grid-cols-2 text-sm">
                <Row label="Registration" value={data.vehicle.display_plate} />
                <Row label="Vehicle" value={data.vehicle.description || "—"} />
                <Row label="Fuel" value={data.vehicle.fuel_type || "—"} />
                <Row label="Engine" value={data.vehicle.engine_capacity ? `${data.vehicle.engine_capacity}cc` : "—"} />
                <Row label="Front tyres" value={data.vehicle.tyre_size_front || "unknown"} />
                <Row label="Rear tyres" value={data.vehicle.tyre_size_rear || "unknown"} />
                <Row label="MOT" value={`${data.vehicle.mot_status || "—"} ${data.vehicle.mot_expiry_date ?? ""}`} />
                <Row label="Tax" value={`${data.vehicle.tax_status || "—"} ${data.vehicle.tax_due_date ?? ""}`} />
              </dl>
            ) : (
              <EmptyState>No registration was given for this call-out.</EmptyState>
            )}
          </Card>
        </div>

        <div className="space-y-4">
          <Card title="Add a note with the next status change">
            <Input value={note} onChange={(event) => setNote(event.target.value)} placeholder="e.g. ETA 25 minutes" />
            <p className="mt-2 text-xs text-ink-muted">
              The note is stored against the status change, so the history explains itself later.
            </p>
          </Card>

          <Card title="History">
            <ol className="space-y-3 text-sm">
              {(data.status_events ?? []).map((event) => (
                <li key={event.id} className="border-l-2 border-slate-200 pl-3">
                  <p className="font-medium">
                    {event.from_status ? `${STATUS_LABELS[event.from_status as BookingStatus]} → ` : "Created as "}
                    {STATUS_LABELS[event.to_status as BookingStatus]}
                  </p>
                  <p className="text-xs text-ink-muted">
                    {formatDateTime(event.created_at)}
                    {event.changed_by_name ? ` · ${event.changed_by_name}` : ""}
                  </p>
                  {event.note ? <p className="mt-1 text-xs">{event.note}</p> : null}
                </li>
              ))}
            </ol>
          </Card>
        </div>
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-ink-muted">{label}</dt>
      <dd className="mt-0.5">{value}</dd>
    </div>
  );
}
