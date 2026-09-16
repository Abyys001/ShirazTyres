"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { Button, Plate, Stat, StatStrip } from "@/components/ui";
import { api } from "@/lib/client-api";
import { timeAgo } from "@/lib/format";
import type { Job, JobStats, Paginated } from "@/types/api";

/**
 * The first thing on the board, and the only thing that moves.
 *
 * The old banner stated the problem in a sentence the same weight as everything
 * around it — a dispatcher walking past read it as chrome. Three things changed:
 *
 * 1. The number is the headline, at a size that carries across a room, wearing
 *    the alarm tone and a slow halo so peripheral vision catches it.
 * 2. The counts sit in the same band. "Two stranded" only means something next
 *    to "three vans on shift", and separating them made the reader do the join.
 * 3. The stranded jobs themselves are here, each with the two buttons the old
 *    sentence only named. Reading the alarm and acting on it is now one place.
 *
 * With nothing unclaimed the band keeps its footprint and goes quiet, so the
 * layout never jumps and the calm state is a statement rather than an absence.
 */
export function DispatchHero({
  stats,
  onShowUnclaimed,
}: {
  stats: JobStats | undefined;
  onShowUnclaimed: () => void;
}) {
  const unclaimed = stats?.unclaimed ?? 0;
  const alarmed = unclaimed > 0;

  return (
    <section
      className={`overflow-hidden rounded-lg border bg-surface transition-colors ${
        alarmed ? "border-danger/45" : "border-line"
      }`}
    >
      <div className="grid gap-px bg-line lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)]">
        <div className="bg-surface">
          {alarmed ? (
            <AlarmBlock count={unclaimed} onShow={onShowUnclaimed} />
          ) : (
            <CalmBlock onShift={stats?.drivers_online ?? 0} />
          )}
        </div>

        <div className="bg-surface">
          <StatStrip inset>
            <Stat label="Just in" value={stats?.submitted ?? 0} />
            <Stat label="Finding a driver" value={stats?.dispatching ?? 0} />
            <Stat label="On the way" value={(stats?.accepted ?? 0) + (stats?.en_route ?? 0)} />
            <Stat label="Being worked on" value={stats?.in_progress ?? 0} />
            <Stat label="Drivers on shift" value={stats?.drivers_online ?? 0} tone="good" />
          </StatStrip>
        </div>
      </div>

      {alarmed ? <UnclaimedList /> : null}
    </section>
  );
}

function AlarmBlock({ count, onShow }: { count: number; onShow: () => void }) {
  return (
    <div className="flex h-full items-center gap-4 p-5">
      <span
        aria-hidden
        className="alarm-ring flex h-3 w-3 shrink-0 self-start rounded-full bg-danger"
        style={{ marginTop: "0.9rem" }}
      />
      <div className="min-w-0">
        <p className="alarm-breathe font-display text-5xl font-bold leading-none tabular-nums text-danger">
          {count}
        </p>
        <p className="mt-2 text-base font-medium text-ink">
          {count === 1 ? "car is stranded" : "cars are stranded"} with nobody coming
        </p>
        <p className="mt-1 text-sm text-ink-muted">
          Send dispatch out again, or put a driver on it yourself.
        </p>
        <Button variant="danger" size="sm" onClick={onShow} className="mt-3">
          Show only these
        </Button>
      </div>
    </div>
  );
}

function CalmBlock({ onShift }: { onShift: number }) {
  return (
    <div className="flex h-full items-center gap-3.5 p-5">
      <span
        aria-hidden
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-success/15 text-success"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="h-5 w-5"
        >
          <path d="m5 13 4 4L19 7" />
        </svg>
      </span>
      <div>
        <p className="font-display text-lg font-semibold tracking-tight text-ink">
          Every call-out has a driver
        </p>
        <p className="mt-0.5 text-sm text-ink-muted">
          {onShift > 0
            ? `${onShift} van${onShift === 1 ? "" : "s"} on shift and nobody waiting.`
            : "Nobody waiting — but there is no one on shift either."}
        </p>
      </div>
    </div>
  );
}

/**
 * The stranded jobs, in the alarm itself.
 *
 * A dispatcher who sees the count then has to find the rows, and under pressure
 * that is where the seconds go. Both recovery paths are on the row: hand it back
 * to dispatch, or open it and choose a driver from the ranked candidates.
 */
function UnclaimedList() {
  const client = useQueryClient();
  const [failed, setFailed] = useState<Record<number, string>>({});

  const jobs = useQuery({
    queryKey: ["jobs", "unclaimed"],
    queryFn: () => api<Paginated<Job>>("/jobs?status=unclaimed"),
    refetchInterval: 30_000,
  });

  const redispatch = useMutation({
    mutationFn: (jobId: number) => api<Job>(`/jobs/${jobId}/dispatch`, { method: "POST" }),
    onMutate: (jobId) =>
      setFailed((current) => {
        const { [jobId]: _removed, ...rest } = current;
        return rest;
      }),
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["jobs"] });
      client.invalidateQueries({ queryKey: ["job-stats"] });
    },
    onError: (error: Error, jobId) =>
      setFailed((current) => ({ ...current, [jobId]: error.message || "Could not dispatch." })),
  });

  const rows = jobs.data?.results ?? [];
  if (rows.length === 0) return null;

  return (
    <ul className="divide-y divide-line border-t border-danger/30">
      {rows.map((job) => (
        <li
          key={job.id}
          className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3 transition hover:bg-surface-raised"
        >
          <Link
            href={`/jobs/${job.id}`}
            className="font-mono text-sm font-medium text-brand hover:underline"
          >
            {job.reference}
          </Link>
          <Plate value={job.plate} />
          <span className="min-w-0 flex-1 truncate text-sm text-ink-muted">{job.location_text}</span>
          <span className="text-sm tabular-nums text-danger" title="Waiting since">
            {timeAgo(job.created_at)}
          </span>

          {failed[job.id] ? (
            <span className="text-sm text-danger">{failed[job.id]}</span>
          ) : null}

          <div className="flex items-center gap-2">
            <Button
              size="sm"
              onClick={() => redispatch.mutate(job.id)}
              disabled={redispatch.isPending && redispatch.variables === job.id}
            >
              {redispatch.isPending && redispatch.variables === job.id
                ? "Sending…"
                : "Dispatch again"}
            </Button>
            <Link href={`/jobs/${job.id}`}>
              <Button size="sm" variant="secondary">
                Assign by hand
              </Button>
            </Link>
          </div>
        </li>
      ))}
    </ul>
  );
}
