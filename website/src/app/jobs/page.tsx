"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useCallback } from "react";

import { SiteHeader } from "@/components/site-header";
import { Button, Card, StatusBadge } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime } from "@/lib/format";
import { useCustomerFeed } from "@/lib/ws";
import type { CustomerJob, Paginated } from "@/types/api";
import { STATUS_LABELS } from "@/types/api";

export default function JobsPage() {
  const queryClient = useQueryClient();

  // The list shows the same statuses the detail page does, so it has to move on
  // the same events. Left on the poll alone, a call-out a technician accepted
  // seconds ago sat here as "Finding a driver" for up to half a minute.
  const connected = useCustomerFeed(
    useCallback(
      () => void queryClient.invalidateQueries({ queryKey: ["my-jobs"] }),
      [queryClient],
    ),
  );

  const jobs = useQuery({
    queryKey: ["my-jobs"],
    queryFn: () => api<Paginated<CustomerJob>>("/my/jobs"),
    refetchInterval: connected ? 60_000 : 15_000,
  });

  return (
    <>
      <SiteHeader signedIn />
      <main className="mx-auto max-w-2xl space-y-4 px-4 py-8">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-semibold">My call-outs</h1>
          <Link href="/request">
            <Button size="sm">New call-out</Button>
          </Link>
        </div>

        {jobs.isLoading ? <p className="text-sm text-ink-muted">Loading…</p> : null}
        {jobs.data && jobs.data.results.length === 0 ? (
          <Card>
            <p className="text-sm text-ink-muted">You have not requested a technician yet.</p>
          </Card>
        ) : null}

        <ul className="space-y-3">
          {(jobs.data?.results ?? []).map((job) => (
            <li key={job.id}>
              <Link href={`/jobs/${job.id}`}>
                <Card>
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <p className="font-medium">{job.reference}</p>
                      <p className="text-sm text-ink-muted">
                        {job.issue_label} · {job.vehicle?.display_plate || job.plate}
                      </p>
                      <p className="text-xs text-ink-subtle">{formatDateTime(job.created_at)}</p>
                    </div>
                    <StatusBadge status={job.status} label={STATUS_LABELS[job.status]} />
                  </div>
                </Card>
              </Link>
            </li>
          ))}
        </ul>
      </main>
    </>
  );
}
