"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback } from "react";

import { SiteHeader } from "@/components/site-header";
import { Button, Card, Detail, Notice, StatusBadge } from "@/components/ui";
import { api } from "@/lib/client-api";
import { eta, formatDateTime, money } from "@/lib/format";
import { useCustomerFeed } from "@/lib/ws";
import type { CustomerJob } from "@/types/api";
import { STATUS_BLURB, STATUS_LABELS } from "@/types/api";

export default function JobPage() {
  const params = useParams<{ id: string }>();
  const id = Number(params.id);
  const queryClient = useQueryClient();

  const connected = useCustomerFeed(
    useCallback(
      (event) => {
        const job = event.job as { id?: number } | undefined;
        if (job?.id === id) void queryClient.invalidateQueries({ queryKey: ["my-job", id] });
      },
      [id, queryClient],
    ),
  );

  const job = useQuery({
    queryKey: ["my-job", id],
    queryFn: () => api<CustomerJob>(`/my/jobs/${id}`),
    // The socket carries the ETA; polling is the fallback when it is not connected.
    refetchInterval: connected ? 60_000 : 15_000,
  });

  const cancel = useMutation({
    mutationFn: () => api<CustomerJob>(`/my/jobs/${id}/cancel`, { method: "POST", body: "{}" }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["my-job", id] }),
  });

  const data = job.data;

  return (
    <>
      <SiteHeader signedIn />
      <main className="mx-auto max-w-2xl space-y-4 px-4 py-8">
        {job.isLoading ? <p className="text-sm text-ink-muted">Loading…</p> : null}
        {job.isError ? <Notice tone="error">We could not find that call-out.</Notice> : null}

        {data ? (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <Link href="/jobs" className="text-sm text-ink-muted hover:underline">
                ← My call-outs
              </Link>
              <h1 className="text-lg font-semibold">{data.reference}</h1>
              <StatusBadge status={data.status} label={STATUS_LABELS[data.status]} />
            </div>

            <Card>
              <p className="text-lg">{STATUS_BLURB[data.status]}</p>
              {data.eta_minutes !== null && !["completed", "cancelled"].includes(data.status) ? (
                <p className="mt-4 text-3xl font-semibold">
                  {eta(data.eta_minutes)}
                  <span className="ml-2 text-base font-normal text-ink-muted">estimated arrival</span>
                </p>
              ) : null}
              {data.eta_updated_at ? (
                <p className="mt-1 text-xs text-ink-subtle">
                  Updated {formatDateTime(data.eta_updated_at)} — it changes with the traffic.
                </p>
              ) : null}
            </Card>

            {data.driver ? (
              <Card title="Your technician">
                <div className="flex items-center gap-4">
                  {data.driver.photo ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={data.driver.photo} alt="" className="h-20 w-20 rounded-full object-cover" />
                  ) : (
                    <div className="flex h-20 w-20 items-center justify-center rounded-full bg-surface-raised text-xs text-ink-subtle">
                      no photo
                    </div>
                  )}
                  <div>
                    <p className="text-lg font-medium">{data.driver.first_name}</p>
                    <p className="text-sm text-ink-muted">
                      {data.driver.vehicle_colour} {data.driver.vehicle_make} {data.driver.vehicle_model}
                    </p>
                    <p className="font-mono text-sm">{data.driver.vehicle_plate}</p>
                  </div>
                </div>
                <p className="mt-4 text-xs text-ink-subtle">
                  Need to speak to them? Call the office and we will pass a message on.
                </p>
              </Card>
            ) : null}

            <Card title="Your request">
              <dl className="grid gap-4 sm:grid-cols-2">
                <Detail label="Vehicle" value={data.vehicle?.description || data.plate} />
                <Detail label="Registration" value={data.vehicle?.display_plate || data.plate} />
                <Detail label="Problem" value={data.issue_label} />
                <Detail
                  label="Damaged wheel"
                  value={data.damaged_summary || "not specified"}
                />
                <Detail label="Tyre size" value={data.tyre_size} />
                <Detail label="Where" value={data.location_text || "position shared"} />
                <Detail label="Requested" value={formatDateTime(data.created_at)} />
              </dl>
              {data.tyre_confirmation_path === "overridden" ? (
                <Notice tone="warning">
                  You gave us the tyre size {data.customer_tyre_size}. Our record showed{" "}
                  {data.looked_up_tyre_size || "no size"}.
                </Notice>
              ) : null}
            </Card>

            {data.invoice ? (
              <Card title="Your bill">
                <ul className="space-y-1 text-sm">
                  {data.invoice.lines.map((line) => (
                    <li key={line.id} className="flex justify-between">
                      <span>{line.description}</span>
                      <span>{money(line.line_total, data.invoice?.currency)}</span>
                    </li>
                  ))}
                </ul>
                <div className="mt-3 border-t border-line pt-3 text-sm">
                  <p className="flex justify-between text-ink-muted">
                    <span>VAT at {data.invoice.vat_rate}%</span>
                    <span>{money(data.invoice.vat_amount, data.invoice.currency)}</span>
                  </p>
                  <p className="mt-1 flex justify-between font-semibold">
                    <span>Total</span>
                    <span>{money(data.invoice.total, data.invoice.currency)}</span>
                  </p>
                </div>
                <p className="mt-3 text-xs text-ink-subtle">You pay once the work is finished.</p>
              </Card>
            ) : null}

            {data.timeline && data.timeline.length > 0 ? (
              <Card title="Progress">
                <ol className="space-y-2 text-sm">
                  {data.timeline.map((entry) => (
                    <li key={`${entry.status}-${entry.at}`} className="flex justify-between">
                      <span>{entry.label}</span>
                      <span className="text-ink-muted">{formatDateTime(entry.at)}</span>
                    </li>
                  ))}
                </ol>
              </Card>
            ) : null}

            {data.can_cancel ? (
              <Button variant="secondary" onClick={() => cancel.mutate()} disabled={cancel.isPending}>
                {cancel.isPending ? "Cancelling…" : "Cancel this call-out"}
              </Button>
            ) : null}
            {cancel.isError ? <Notice tone="error">{cancel.error.message}</Notice> : null}
          </>
        ) : null}
      </main>
    </>
  );
}
