"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { DispatchHero } from "@/components/dispatch-hero";
import { NewJobForm } from "@/components/new-job-form";
import {
  Button,
  Card,
  EmptyState,
  Plate,
  Select,
  StatusBadge,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { eta, timeAgo } from "@/lib/format";
import { useLiveStatus } from "@/lib/ws";
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

  // LiveSync carries every change; the poll is the safety net if the socket drops.
  const connected = useLiveStatus();

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

  return (
    <div className="space-y-5">
      <DispatchHero stats={stats.data} onShowUnclaimed={() => setFilter("unclaimed")} />

      <Card
        title="Jobs"
        action={
          <div className="flex items-center gap-2">
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

        {jobs.isLoading ? <EmptyState>Loading the board…</EmptyState> : null}
        {jobs.isError ? (
          <EmptyState>
            The board could not be loaded. It will retry on its own; check the API if this stays.
          </EmptyState>
        ) : null}
        {jobs.data && jobs.data.results.length === 0 ? (
          <EmptyState>
            Nothing matches this filter. Every call-out is accounted for.
          </EmptyState>
        ) : null}

        {jobs.data && jobs.data.results.length > 0 ? (
          <div className="-mx-4 overflow-x-auto">
            <table className="w-full min-w-[56rem] border-collapse text-sm">
              <thead>
                <tr className="border-b border-line text-left text-xs text-ink-subtle">
                  <th className="py-2 pl-4 pr-3 font-medium">Job</th>
                  <th className="py-2 pr-3 font-medium">Customer</th>
                  <th className="py-2 pr-3 font-medium">Vehicle</th>
                  <th className="py-2 pr-3 font-medium">Problem</th>
                  <th className="py-2 pr-3 font-medium">Where</th>
                  <th className="py-2 pr-3 font-medium">Driver</th>
                  <th className="py-2 pr-3 text-right font-medium">ETA</th>
                  <th className="py-2 pr-4 font-medium">Status</th>
                </tr>
              </thead>
              <tbody>
                {jobs.data.results.map((job) => (
                  <tr
                    key={job.id}
                    className="border-b border-line align-top last:border-0 hover:bg-surface-raised"
                  >
                    {/* The rail is the cell, not its contents, so it runs the full height of the row. */}
                    <td className={`py-2.5 pl-4 pr-3 ${treadFor(job.status)}`}>
                      <Link
                        href={`/jobs/${job.id}`}
                        className="font-mono text-sm font-medium text-brand hover:underline"
                      >
                        {job.reference}
                      </Link>
                      <span className="mt-0.5 block text-xs text-ink-subtle">{timeAgo(job.created_at)}</span>
                    </td>
                    <td className="py-2.5 pr-3">
                      <span className="block text-ink">{job.contact_name}</span>
                      <span className="block font-mono text-xs text-ink-subtle">{job.contact_phone}</span>
                    </td>
                    <td className="py-2.5 pr-3">
                      <Plate value={job.plate} />
                      <span className="mt-1 block font-mono text-xs text-ink-subtle">
                        {job.tyre_size || "size not known"}
                      </span>
                    </td>
                    <td className="py-2.5 pr-3 text-ink">
                      {job.issue_label}
                      {job.damaged_summary ? (
                        <span className="mt-0.5 block text-xs text-ink-subtle">
                          {job.damaged_summary}
                        </span>
                      ) : null}
                    </td>
                    <td className="max-w-[16rem] truncate py-2.5 pr-3 text-ink-muted">{job.location_text}</td>
                    <td className="py-2.5 pr-3 text-ink">
                      {job.driver_name || <span className="text-ink-subtle">nobody yet</span>}
                    </td>
                    <td className="py-2.5 pr-3 text-right font-mono tabular-nums text-ink">
                      {eta(job.eta_minutes)}
                    </td>
                    <td className="py-2.5 pr-4">
                      <StatusBadge status={job.status as JobStatus} label={STATUS_LABELS[job.status]} />
                    </td>
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

/**
 * The left edge of a row reads as tread, and its rhythm is the job's state:
 * gold and tight while somebody is moving on it, red and gapped the moment
 * nobody is, faint once it is closed. Scanning the edge answers "is anyone
 * stranded" without reading a word.
 */
function treadFor(status: string): string {
  if (status === "unclaimed") return "tread tread-alarm";
  if (status === "completed" || status === "cancelled") return "tread tread-done";
  if (status === "submitted" || status === "dispatching") return "tread";
  return "tread tread-live";
}
