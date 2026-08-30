"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, EmptyState, ErrorNote, Pill } from "@/components/ui";
import { api } from "@/lib/client-api";
import { distance, eta, formatDateTime } from "@/lib/format";
import type { Candidate, DispatchAttempt, JobDetail } from "@/types/api";

const OFFER_STYLES: Record<string, string> = {
  offered: "chip-warn",
  accepted: "chip-ok",
  rejected: "chip-danger",
  withdrawn: "chip-muted",
  timed_out: "chip-muted",
};

/**
 * Dispatch control and audit trail (specification 6 and 13).
 *
 * The trail is the point of `DispatchAttempt`: when a job goes unclaimed it shows who
 * was contacted, when, and whether each said no or simply never answered.
 */
export function DispatchCard({ job }: { job: JobDetail }) {
  const queryClient = useQueryClient();
  const [showCandidates, setShowCandidates] = useState(false);

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["job", job.id] });

  const candidates = useQuery({
    queryKey: ["candidates", job.id],
    queryFn: () => api<Candidate[]>(`/jobs/${job.id}/candidates`),
    enabled: showCandidates,
  });

  const redispatch = useMutation({
    mutationFn: () => api<JobDetail>(`/jobs/${job.id}/dispatch`, { method: "POST" }),
    onSuccess: refresh,
  });

  const assign = useMutation({
    mutationFn: (driverId: number) =>
      api<JobDetail>(`/jobs/${job.id}/assign`, {
        method: "POST",
        body: JSON.stringify({ driver_id: driverId }),
      }),
    onSuccess: refresh,
  });

  const dispatchable = !["completed", "cancelled"].includes(job.status);

  return (
    <Card
      title="Dispatch"
      action={
        dispatchable ? (
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={() => setShowCandidates((open) => !open)}>
              {showCandidates ? "Hide candidates" : "Who is nearest?"}
            </Button>
            <Button size="sm" onClick={() => redispatch.mutate()} disabled={redispatch.isPending}>
              {redispatch.isPending ? "Dispatching…" : "Dispatch again"}
            </Button>
          </div>
        ) : null
      }
    >
      {redispatch.isError ? <ErrorNote>{redispatch.error.message}</ErrorNote> : null}
      {assign.isError ? <ErrorNote>{assign.error.message}</ErrorNote> : null}

      {showCandidates ? (
        <div className="mb-4 rounded-md border border-line bg-surface-raised p-3">
          <p className="mb-2 text-xs text-ink-muted">
            Ranked by routing travel time, not straight-line distance (section 6.4).
          </p>
          {candidates.isLoading ? <p className="text-sm">Working it out…</p> : null}
          {candidates.data?.length === 0 ? (
            <p className="text-sm text-ink-muted">Nobody is eligible for this job right now.</p>
          ) : null}
          <ul className="space-y-1">
            {(candidates.data ?? []).map((candidate) => (
              <li key={candidate.driver_id} className="flex items-center justify-between text-sm">
                <span>
                  {candidate.name}
                  <span className="ml-2 text-xs text-ink-muted">
                    {eta(candidate.eta_minutes)} · {distance(candidate.distance_metres)}
                  </span>
                </span>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => assign.mutate(candidate.driver_id)}
                  disabled={assign.isPending}
                >
                  Assign
                </Button>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {job.dispatch_attempts.length === 0 ? (
        <EmptyState>Dispatch has not run for this job yet.</EmptyState>
      ) : (
        <ol className="space-y-3">
          {job.dispatch_attempts.map((attempt) => (
            <AttemptRow key={attempt.id} attempt={attempt} />
          ))}
        </ol>
      )}
    </Card>
  );
}

function AttemptRow({ attempt }: { attempt: DispatchAttempt }) {
  return (
    <li className="rounded-md border border-line p-3">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="font-medium">Round {attempt.round_number}</span>
        <Pill className="chip-muted">{attempt.mode_display}</Pill>
        <Pill className={attempt.outcome === "accepted" ? "chip-ok" : "chip-muted"}>
          {attempt.outcome_display}
        </Pill>
        <span className="text-xs text-ink-muted">
          {attempt.radius_km} km · {attempt.timeout_seconds}s · {attempt.candidates_considered} considered
        </span>
      </div>

      {attempt.offers.length > 0 ? (
        <ul className="mt-2 space-y-1">
          {attempt.offers.map((offer) => (
            <li key={offer.id} className="flex flex-wrap items-center gap-2 text-xs">
              <span className="w-40 truncate">{offer.driver_name}</span>
              <Pill className={OFFER_STYLES[offer.state] ?? "bg-surface-raised"}>{offer.state}</Pill>
              <span className="text-ink-muted">
                {eta(offer.eta_minutes)} · offered {formatDateTime(offer.offered_at)}
                {offer.responded_at ? ` · answered ${formatDateTime(offer.responded_at)}` : ""}
              </span>
              {offer.reason ? <span className="text-ink-muted">“{offer.reason}”</span> : null}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-2 text-xs text-ink-muted">No driver was in range for this round.</p>
      )}
    </li>
  );
}
