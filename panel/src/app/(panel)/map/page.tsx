"use client";

import { useQuery } from "@tanstack/react-query";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useMemo, useState } from "react";

import { Card, EmptyState, Plate, StatusBadge, VerificationBadge } from "@/components/ui";
import { api } from "@/lib/client-api";
import { distance, eta, fixAge, timeAgo } from "@/lib/format";
import { useLiveStatus } from "@/lib/ws";
import type { DriverMapRow, JobMapRow, JobStatus } from "@/types/api";
import { STATUS_LABELS } from "@/types/api";

// Leaflet touches `window` on import, so it can only load in the browser.
const LiveMap = dynamic(() => import("@/components/live-map").then((m) => m.LiveMap), {
  ssr: false,
  loading: () => <div className="h-[70vh] w-full animate-pulse rounded-lg bg-surface-raised" />,
});

export default function MapPage() {
  return (
    <Suspense fallback={<div className="h-[70vh] w-full animate-pulse rounded-lg bg-surface-raised" />}>
      <MapBoard />
    </Suspense>
  );
}

function MapBoard() {
  const router = useRouter();
  const params = useSearchParams();
  const connected = useLiveStatus();

  // The driver is in the URL so "show me Amir" is a link the drivers page can
  // hand over, and so a dispatcher can keep one van on screen through a reload.
  const focusDriverId = numberOrNull(params.get("driver"));
  const [focusJobId, setFocusJobId] = useState<number | null>(null);

  const drivers = useQuery({
    queryKey: ["driver-map"],
    // LiveSync writes each ping straight into this cache, so the poll is only
    // here to catch a driver coming on or off shift while the socket was down.
    queryFn: () => api<DriverMapRow[]>("/drivers/map"),
    refetchInterval: connected ? 120_000 : 10_000,
  });

  const jobs = useQuery({
    queryKey: ["job-map"],
    queryFn: () => api<JobMapRow[]>("/jobs/map"),
    refetchInterval: connected ? 120_000 : 15_000,
  });

  const driverRows = useMemo(() => drivers.data ?? [], [drivers.data]);
  const jobRows = useMemo(() => jobs.data ?? [], [jobs.data]);

  const tracked = focusJobId ? jobRows.find((job) => job.id === focusJobId) ?? null : null;

  // A job that closes while it is being watched should not leave a stale card.
  useEffect(() => {
    if (focusJobId && !jobRows.some((job) => job.id === focusJobId)) setFocusJobId(null);
  }, [focusJobId, jobRows]);

  function focusDriver(id: number) {
    router.replace(`/map?driver=${id}`, { scroll: false });
  }

  return (
    <div className="grid gap-5 lg:grid-cols-4">
      <div className="lg:col-span-3">
        <LiveMap
          drivers={driverRows}
          jobs={jobRows}
          focusDriverId={focusDriverId}
          focusJobId={focusJobId}
          onSelectDriver={focusDriver}
          onSelectJob={setFocusJobId}
        />
        <p className="mt-2 text-xs text-ink-subtle">
          Positions are only recorded while a driver is online (section 11.1) and never reach a customer
          surface.
        </p>
      </div>

      <div className="space-y-5">
        <TrackingCard job={tracked} onClear={() => setFocusJobId(null)} />

        <Card title={`Live call-outs (${jobRows.length})`}>
          {jobRows.length === 0 ? <EmptyState>Nothing open right now.</EmptyState> : null}
          <ul className="-mx-1 space-y-1">
            {jobRows.map((job) => (
              <li key={job.id}>
                <button
                  onClick={() => setFocusJobId(job.id)}
                  className={`w-full rounded-md px-2 py-2 text-left transition ${
                    focusJobId === job.id ? "bg-brand/10" : "hover:bg-surface-raised"
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <Plate value={job.plate} />
                    <StatusBadge
                      status={job.status as JobStatus}
                      label={STATUS_LABELS[job.status] ?? job.status_display}
                    />
                  </span>
                  <span className="mt-1 block truncate text-xs text-ink-muted">
                    {job.location_text || "no address"}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </Card>

        <Card title={`On shift (${driverRows.length})`}>
          {driverRows.length === 0 ? <EmptyState>Nobody is online.</EmptyState> : null}
          <ul className="-mx-1 space-y-1">
            {driverRows.map((driver) => (
              <li key={driver.id}>
                {/*
                 * Clicking a driver puts them on the map, which is the question
                 * being asked from this list. Their record is still one click
                 * further on, and says so.
                 */}
                <button
                  onClick={() => focusDriver(driver.id)}
                  className={`w-full rounded-md px-2 py-2 text-left transition ${
                    focusDriverId === driver.id ? "bg-brand/10" : "hover:bg-surface-raised"
                  }`}
                >
                  <span className="flex items-center justify-between gap-2">
                    <span className="truncate text-sm font-medium text-ink">{driver.name}</span>
                    <span className="shrink-0 text-xs text-ink-subtle">
                      {driver.active_jobs > 0 ? "on a job" : "free"}
                    </span>
                  </span>
                  <span className="mt-0.5 block text-xs text-ink-muted">
                    {driver.vehicle_plate || "no van recorded"} · {fixAge(driver.location_updated_at)}
                  </span>
                  <span className="mt-1 flex items-center gap-2 text-xs">
                    <VerificationBadge status={driver.verification_status} />
                    <Link
                      href={`/drivers/${driver.id}`}
                      onClick={(event) => event.stopPropagation()}
                      className="text-brand hover:underline"
                    >
                      Open record
                    </Link>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </div>
  );
}

/**
 * One call-out, tracked.
 *
 * Everything an office needs while a job is running, in the order they get asked
 * for it on the phone: who is waiting, who is coming, how far out they are, and
 * both numbers to ring. The phone numbers are `tel:` links because this card
 * gets used while a customer is already on the other line.
 */
function TrackingCard({ job, onClear }: { job: JobMapRow | null; onClear: () => void }) {
  if (!job) {
    return (
      <Card title="Tracking">
        <EmptyState>Pick a call-out to follow it here.</EmptyState>
      </Card>
    );
  }

  const claimed = Boolean(job.driver);
  const takenAt = job.accepted_at ?? job.assigned_at;

  return (
    <Card
      title="Tracking"
      action={
        <button onClick={onClear} className="text-xs text-ink-muted hover:text-ink">
          Clear
        </button>
      }
    >
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href={`/jobs/${job.id}`}
            className="font-mono text-sm font-medium text-brand hover:underline"
          >
            {job.reference}
          </Link>
          <StatusBadge
            status={job.status as JobStatus}
            label={STATUS_LABELS[job.status] ?? job.status_display}
          />
        </div>

        <div className="flex items-center gap-2">
          <Plate value={job.plate} size="lg" />
          <span className="text-sm text-ink-muted">{job.issue_label}</span>
        </div>

        <dl className="space-y-2 border-t border-line pt-3 text-sm">
          <Row label="Reported">{timeAgo(job.created_at)}</Row>
          <Row label="Where">{job.location_text || "no address"}</Row>
          <Row label="Customer">
            <span className="block">{job.contact_name}</span>
            <PhoneLink number={job.contact_phone} />
          </Row>
          <Row label="Driver">
            {claimed ? (
              <>
                <span className="block">{job.driver_name}</span>
                <PhoneLink number={job.driver_phone} />
                {takenAt ? (
                  <span className="mt-0.5 block text-xs text-ink-subtle">
                    took it {timeAgo(takenAt)}
                  </span>
                ) : null}
              </>
            ) : (
              <span className="text-danger">nobody coming</span>
            )}
          </Row>
          {claimed ? (
            <>
              <Row label="Distance">
                {job.eta_distance_metres !== null ? (
                  <span className="font-mono tabular-nums">{distance(job.eta_distance_metres)}</span>
                ) : (
                  <span className="text-ink-subtle">not known yet</span>
                )}
              </Row>
              <Row label="ETA">
                <span className="font-mono tabular-nums">{eta(job.eta_minutes)}</span>
                {job.eta_updated_at ? (
                  <span className="ml-1.5 text-xs text-ink-subtle">
                    ({fixAge(job.eta_updated_at)})
                  </span>
                ) : null}
              </Row>
            </>
          ) : null}
        </dl>
      </div>
    </Card>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[6rem_minmax(0,1fr)] gap-2">
      <dt className="text-ink-subtle">{label}</dt>
      <dd className="min-w-0 text-ink">{children}</dd>
    </div>
  );
}

function PhoneLink({ number }: { number: string }) {
  if (!number) return <span className="text-ink-subtle">no number</span>;
  return (
    <a href={`tel:${number}`} className="block font-mono text-sm text-brand hover:underline">
      {number}
    </a>
  );
}

function numberOrNull(value: string | null): number | null {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}
