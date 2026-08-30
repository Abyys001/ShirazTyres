"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useCallback, useState } from "react";

import { NewJobForm } from "@/components/new-job-form";
import {
  AlertBanner,
  Button,
  Card,
  EmptyState,
  LiveDot,
  Select,
  Stat,
  StatusBadge,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { eta, timeAgo } from "@/lib/format";
import { usePanelFeed } from "@/lib/ws";
import type { Job, JobStats, JobStatus, Paginated } from "@/types/api";
import { STATUS_LABELS } from "@/types/api";

const FILTERS: { value: string; label: string }[] = [
  { value: "open", label: "Open jobs" },
  { value: "unclaimed", label: "Unclaimed" },
  { value: "dispatching", label: "Finding a driver" },
  { value: "assigned", label: "Assigned" },
  { value: "accepted", label: "Accepted" },
  { value: "en_route", label: "On the way" },
  { value: "in_progress", label: "In progress" },
  { value: "completed", label: "Completed" },
  { value: "cancelled", label: "Cancelled" },
  { value: "all", label: "All" },
];

function query(filter: string) {
  if (filter === "open") return "?open_only=true";
  if (filter === "all") return "";
  return `?status=${filter}`;
}

export default function JobsPage() {
  const [filter, setFilter] = useState("open");
  const [creating, setCreating] = useState(false);
  const queryClient = useQueryClient();

  // The socket carries every change; the poll is the safety net if it drops.
  const connected = usePanelFeed(
    useCallback(
      (event) => {
        if (event.event.startsWith("job.")) {
          void queryClient.invalidateQueries({ queryKey: ["jobs"] });
          void queryClient.invalidateQueries({ queryKey: ["job-stats"] });
        }
      },
      [queryClient],
    ),
  );

  const jobs = useQuery({
    queryKey: ["jobs", filter],
    queryFn: () => api<Paginated<Job>>(`/jobs${query(filter)}`),
    refetchInterval: connected ? 60_000 : 15_000,
  });

  const stats = useQuery({
    queryKey: ["job-stats"],
    queryFn: () => api<JobStats>("/jobs/stats"),
    refetchInterval: connected ? 60_000 : 15_000,
  });

  const unclaimed = stats.data?.unclaimed ?? 0;

  return (
    <div className="space-y-6">
      {unclaimed > 0 ? (
        <AlertBanner>
          <span>
            <strong>{unclaimed}</strong> job{unclaimed === 1 ? "" : "s"} nobody has taken. Assign a driver by
            hand or start dispatch again.
          </span>
          <Button variant="secondary" size="sm" onClick={() => setFilter("unclaimed")}>
            Show them
          </Button>
        </AlertBanner>
      ) : null}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <Stat label="Submitted" value={stats.data?.submitted ?? 0} tone="alert" />
        <Stat label="Finding a driver" value={stats.data?.dispatching ?? 0} />
        <Stat label="On the way" value={(stats.data?.accepted ?? 0) + (stats.data?.en_route ?? 0)} />
        <Stat label="In progress" value={stats.data?.in_progress ?? 0} />
        <Stat label="Unclaimed" value={unclaimed} tone="alert" />
        <Stat label="Drivers online" value={stats.data?.drivers_online ?? 0} />
      </div>

      <Card
        title="Jobs"
        action={
          <div className="flex items-center gap-2">
            <LiveDot connected={connected} />
            <Select value={filter} onChange={(event) => setFilter(event.target.value)} className="w-44">
              {FILTERS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Select>
            <Button onClick={() => setCreating((open) => !open)} variant={creating ? "secondary" : "primary"}>
              {creating ? "Close" : "New job"}
            </Button>
          </div>
        }
      >
        {creating ? (
          <div className="mb-4 rounded-md border border-line bg-surface-raised p-4">
            <NewJobForm onCreated={() => setCreating(false)} />
          </div>
        ) : null}

        {jobs.isLoading ? <EmptyState>Loading…</EmptyState> : null}
        {jobs.isError ? <EmptyState>Could not load jobs.</EmptyState> : null}
        {jobs.data && jobs.data.results.length === 0 ? (
          <EmptyState>Nothing here — no jobs match this filter.</EmptyState>
        ) : null}

        {jobs.data && jobs.data.results.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                <tr className="border-b border-line">
                  <th className="py-2 pr-3">Reference</th>
                  <th className="py-2 pr-3">Customer</th>
                  <th className="py-2 pr-3">Vehicle</th>
                  <th className="py-2 pr-3">Issue</th>
                  <th className="py-2 pr-3">Location</th>
                  <th className="py-2 pr-3">Driver</th>
                  <th className="py-2 pr-3">ETA</th>
                  <th className="py-2 pr-3">Status</th>
                  <th className="py-2 pr-3">Received</th>
                </tr>
              </thead>
              <tbody>
                {jobs.data.results.map((job) => (
                  <tr key={job.id} className="border-b border-line last:border-0 hover:bg-surface-raised">
                    <td className="py-2 pr-3 font-medium">
                      <Link href={`/jobs/${job.id}`} className="text-brand hover:underline">
                        {job.reference}
                      </Link>
                    </td>
                    <td className="py-2 pr-3">
                      {job.contact_name}
                      <span className="block text-xs text-ink-muted">{job.contact_phone}</span>
                    </td>
                    <td className="py-2 pr-3">
                      {job.plate || "—"}
                      <span className="block text-xs text-ink-muted">{job.tyre_size || "size unknown"}</span>
                    </td>
                    <td className="py-2 pr-3">{job.issue_label}</td>
                    <td className="py-2 pr-3 max-w-[14rem] truncate">{job.location_text}</td>
                    <td className="py-2 pr-3">{job.driver_name || "—"}</td>
                    <td className="py-2 pr-3 text-xs">{eta(job.eta_minutes)}</td>
                    <td className="py-2 pr-3">
                      <StatusBadge status={job.status as JobStatus} label={STATUS_LABELS[job.status]} />
                    </td>
                    <td className="py-2 pr-3 text-xs text-ink-muted">{timeAgo(job.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </Card>
    </div>
  );
}
