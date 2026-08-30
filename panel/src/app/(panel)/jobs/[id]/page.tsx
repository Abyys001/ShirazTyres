"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useState } from "react";

import { DispatchCard } from "@/components/dispatch-card";
import { InvoiceCard } from "@/components/invoice-card";
import {
  Button,
  Card,
  Detail,
  EmptyState,
  ErrorNote,
  Field,
  Input,
  LiveDot,
  Pill,
  Select,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { distance, eta, formatDateTime, timeAgo } from "@/lib/format";
import { usePanelFeed } from "@/lib/ws";
import type { JobDetail, JobStatus } from "@/types/api";
import { NEXT_STATUSES, STATUS_LABELS } from "@/types/api";

export default function JobDetailPage() {
  const params = useParams<{ id: string }>();
  const id = Number(params.id);
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");

  const connected = usePanelFeed(
    useCallback(
      (event) => {
        const payload = event.job as { id?: number } | undefined;
        if (event.event.startsWith("job.") && payload?.id === id) {
          void queryClient.invalidateQueries({ queryKey: ["job", id] });
        }
      },
      [id, queryClient],
    ),
  );

  const job = useQuery({
    queryKey: ["job", id],
    queryFn: () => api<JobDetail>(`/jobs/${id}`),
    refetchInterval: connected ? 60_000 : 15_000,
  });

  const setStatus = useMutation({
    mutationFn: (status: JobStatus) =>
      api<JobDetail>(`/jobs/${id}/status`, {
        method: "POST",
        body: JSON.stringify({ status, note }),
      }),
    onSuccess: () => {
      setNote("");
      void queryClient.invalidateQueries({ queryKey: ["job", id] });
    },
  });

  const saveNotes = useMutation({
    mutationFn: (internal_notes: string) =>
      api<JobDetail>(`/jobs/${id}`, { method: "PATCH", body: JSON.stringify({ internal_notes }) }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["job", id] }),
  });

  if (job.isLoading) return <EmptyState>Loading…</EmptyState>;
  if (job.isError || !job.data) return <EmptyState>Could not load this job.</EmptyState>;

  const data = job.data;
  const overridden = data.tyre_confirmation_path === "overridden";

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/jobs" className="text-sm text-ink-muted hover:underline">
            ← Jobs
          </Link>
          <h1 className="text-lg font-semibold">{data.reference}</h1>
          <StatusBadge status={data.status} label={STATUS_LABELS[data.status]} />
          <Pill className="chip-muted">{data.source}</Pill>
        </div>
        <LiveDot connected={connected} />
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Card title="Call-out">
            <dl className="grid gap-4 sm:grid-cols-3">
              <Detail label="Customer" value={data.contact_name} />
              <Detail label="Phone" value={<a href={`tel:${data.contact_phone}`}>{data.contact_phone}</a>} />
              <Detail label="Email" value={data.contact_email} />
              <Detail label="Issue" value={data.issue_label} />
              <Detail label="Vehicle" value={data.vehicle?.description || data.plate} />
              <Detail label="Registration" value={data.vehicle?.display_plate || data.plate} />
              <div className="sm:col-span-3">
                <Detail label="Notes from the customer" value={data.description} />
              </div>
            </dl>
          </Card>

          <Card title="Tyre specification">
            <dl className="grid gap-4 sm:grid-cols-3">
              <Detail label="Fitting" value={data.tyre_size} />
              <Detail label="Looked up" value={data.looked_up_tyre_size} />
              <Detail label="Customer supplied" value={data.customer_tyre_size} />
            </dl>
            {overridden ? (
              <p className="mt-3 rounded-md bg-warning/10 px-3 py-2 text-xs text-warning">
                The customer declined the looked-up specification and accepted responsibility for the size they
                gave, at {formatDateTime(data.disclaimer_accepted_at)}. Both figures are recorded above.
              </p>
            ) : (
              <p className="mt-3 text-xs text-ink-muted">Customer confirmed the looked-up specification.</p>
            )}
            {data.tyre_corrected_on_site ? (
              <p className="mt-2 text-xs text-ink-muted">
                Corrected on site by the technician. {data.tyre_correction_note}
              </p>
            ) : null}
          </Card>

          <DispatchCard job={data} />
          <InvoiceCard job={data} />

          <Card title="History">
            <ol className="space-y-2">
              {data.status_events.map((event) => (
                <li key={event.id} className="flex flex-wrap items-baseline gap-2 text-sm">
                  <span className="text-xs text-ink-muted">{formatDateTime(event.created_at)}</span>
                  <span className="font-medium">{STATUS_LABELS[event.to_status as JobStatus] ?? event.to_status}</span>
                  <span className="text-xs text-ink-muted">
                    {event.actor_name || event.actor_type}
                    {event.note ? ` — ${event.note}` : ""}
                  </span>
                </li>
              ))}
            </ol>
          </Card>
        </div>

        <div className="space-y-6">
          <Card title="Where">
            <dl className="grid gap-4">
              <Detail label="Description" value={data.location_text} />
              <Detail
                label="Position"
                value={
                  data.latitude ? (
                    <a className="text-brand hover:underline" href={data.maps_url} target="_blank" rel="noreferrer">
                      {data.latitude}, {data.longitude}
                    </a>
                  ) : (
                    "not shared"
                  )
                }
              />
              <Detail label="Captured by" value={data.location_source} />
              <Detail label="Accuracy" value={distance(data.location_accuracy_m)} />
              <Detail label="Service area" value={data.service_area_name} />
            </dl>
          </Card>

          <Card title="Driver">
            {data.driver ? (
              <dl className="grid gap-4">
                <Detail
                  label="Assigned"
                  value={
                    <Link href={`/drivers/${data.driver}`} className="text-brand hover:underline">
                      {data.driver_name}
                    </Link>
                  }
                />
                <Detail label="Phone" value={<a href={`tel:${data.driver_phone}`}>{data.driver_phone}</a>} />
                <Detail label="ETA" value={eta(data.eta_minutes)} />
                <Detail
                  label="ETA updated"
                  value={data.eta_updated_at ? timeAgo(data.eta_updated_at) : "—"}
                />
              </dl>
            ) : (
              <p className="text-sm text-ink-muted">Nobody is assigned yet.</p>
            )}
          </Card>

          <Card title="Move this job">
            <div className="space-y-2">
              <Field label="Note (optional)">
                <Input value={note} onChange={(event) => setNote(event.target.value)} />
              </Field>
              <div className="flex flex-wrap gap-2">
                {NEXT_STATUSES[data.status].map((status) => (
                  <Button
                    key={status}
                    size="sm"
                    variant={status === "cancelled" ? "danger" : "secondary"}
                    onClick={() => setStatus.mutate(status)}
                    disabled={setStatus.isPending}
                  >
                    {STATUS_LABELS[status]}
                  </Button>
                ))}
                {NEXT_STATUSES[data.status].length === 0 ? (
                  <p className="text-sm text-ink-muted">This job is closed.</p>
                ) : null}
              </div>
              {setStatus.isError ? <ErrorNote>{setStatus.error.message}</ErrorNote> : null}
            </div>
          </Card>

          <Card title="Office notes">
            <form
              className="space-y-2"
              onSubmit={(event) => {
                event.preventDefault();
                const form = new FormData(event.currentTarget);
                saveNotes.mutate(String(form.get("internal_notes") ?? ""));
              }}
            >
              <Textarea name="internal_notes" rows={4} defaultValue={data.internal_notes} />
              <Button type="submit" size="sm" variant="secondary" disabled={saveNotes.isPending}>
                Save
              </Button>
            </form>
          </Card>
        </div>
      </div>
    </div>
  );
}
