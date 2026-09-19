"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { Button, Card, DocumentBadge, EmptyState, ErrorNote, Plate, Textarea } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDate, timeAgo } from "@/lib/format";
import type { Driver, DriverDocument } from "@/types/api";

/**
 * The onboarding queue, as the decision it actually is.
 *
 * Section 8.2 makes approval an administrator's act, and until it happens the
 * technician's app can show them nothing but a wait. The old panel put that
 * decision behind two navigations and three unlabelled buttons on a record
 * page, which is how a driver ends up waiting on somebody who never saw they
 * were there. Everything the decision needs — who they are, what they drive,
 * what they uploaded and what is still missing — is on one card here, with the
 * approval on the same card.
 *
 * Approve is deliberately the only filled button. Reject and suspend are
 * recoverable but consequential, so they ask first and never sit under a thumb
 * next to the one that is pressed fifty times a week.
 */

const DOCUMENT_LABELS: Record<string, string> = {
  insurance: "Insurance certificate",
  licence: "Driving licence",
  mot: "MOT certificate",
  right_to_work: "Right to work",
  other: "Other document",
};

function documentLabel(type: string): string {
  return DOCUMENT_LABELS[type] ?? type.replace(/_/g, " ");
}

export function ApprovalQueue({ drivers, isLoading }: { drivers: Driver[]; isLoading: boolean }) {
  // The queue is usually one or two people. Opening the head of it saves the
  // click that the whole card exists to save.
  const [open, setOpen] = useState<number | null>(null);
  const head = drivers[0]?.id ?? null;
  const expanded = open ?? head;

  return (
    <Card
      title="Awaiting approval"
      action={
        drivers.length > 0 ? (
          <span className="rounded-full bg-danger/10 px-2.5 py-0.5 text-xs font-semibold text-danger">
            {drivers.length} to review
          </span>
        ) : null
      }
    >
      {isLoading ? <EmptyState>Loading…</EmptyState> : null}

      {!isLoading && drivers.length === 0 ? (
        <EmptyState>
          Nobody is waiting. New technicians appear here the moment they sign in for the first time.
        </EmptyState>
      ) : null}

      {drivers.length > 0 ? (
        <ul className="space-y-3">
          {drivers.map((driver) => (
            <ApplicantCard
              key={driver.id}
              driver={driver}
              expanded={expanded === driver.id}
              onToggle={() => setOpen(expanded === driver.id ? -1 : driver.id)}
            />
          ))}
        </ul>
      ) : null}
    </Card>
  );
}

function ApplicantCard({
  driver,
  expanded,
  onToggle,
}: {
  driver: Driver;
  expanded: boolean;
  onToggle: () => void;
}) {
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");
  const [confirming, setConfirming] = useState<"rejected" | null>(null);

  const refresh = () => {
    setNote("");
    setConfirming(null);
    void queryClient.invalidateQueries({ queryKey: ["drivers"] });
    void queryClient.invalidateQueries({ queryKey: ["driver", driver.id] });
    void queryClient.invalidateQueries({ queryKey: ["compliance"] });
  };

  const decide = useMutation({
    mutationFn: (verification_status: "approved" | "rejected") =>
      api<Driver>(`/drivers/${driver.id}/verification`, {
        method: "POST",
        body: JSON.stringify({ verification_status, note }),
      }),
    onSuccess: refresh,
  });

  const reviewDocument = useMutation({
    mutationFn: (payload: { id: number; status: "approved" | "rejected" }) =>
      api<DriverDocument>(`/driver-documents/${payload.id}/review`, {
        method: "POST",
        body: JSON.stringify({
          status: payload.status,
          note: payload.status === "rejected" ? note : "",
        }),
      }),
    onSuccess: refresh,
  });

  const van = driver.vehicles.find((vehicle) => vehicle.is_primary) ?? driver.vehicles[0];
  const outstanding = driver.missing_documents;
  const ready = outstanding.length === 0;
  const busy = decide.isPending || reviewDocument.isPending;

  return (
    <li className="rounded-lg border border-line bg-surface-raised/40">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={expanded}
        className="flex w-full items-center gap-3 px-3 py-3 text-left transition hover:bg-surface-raised"
      >
        <Avatar driver={driver} />

        <span className="min-w-0 flex-1">
          <span className="flex flex-wrap items-center gap-2">
            <span className="truncate font-medium">{driver.name || "Unnamed technician"}</span>
            <span className="font-mono text-xs text-ink-muted">{driver.phone}</span>
          </span>
          <span className="mt-0.5 block text-xs text-ink-subtle">
            signed up {timeAgo(driver.created_at)}
            {driver.last_login_at ? ` · last opened the app ${timeAgo(driver.last_login_at)}` : null}
          </span>
        </span>

        {/*
         * The one fact that decides whether this card can be closed in a
         * second: a technician with their paperwork in is a yes or a no, and
         * one without it is not a decision at all yet.
         */}
        <span
          className={`hidden shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium sm:inline ${
            ready ? "chip-ok" : "chip-warn"
          }`}
        >
          {ready ? "ready to approve" : `${outstanding.length} document${outstanding.length === 1 ? "" : "s"} short`}
        </span>

        <svg
          aria-hidden
          viewBox="0 0 20 20"
          className={`h-4 w-4 shrink-0 text-ink-subtle transition-transform ${expanded ? "rotate-180" : ""}`}
        >
          <path d="M5 8l5 5 5-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      </button>

      {expanded ? (
        <div className="space-y-4 border-t border-line px-3 py-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <p className="text-xs text-ink-subtle">Van</p>
              {van ? (
                <p className="mt-1 flex flex-wrap items-center gap-2 text-sm">
                  <Plate value={van.display_plate} />
                  <span className="text-ink-muted">{van.description || "details not fetched"}</span>
                </p>
              ) : (
                <p className="mt-1 text-sm text-warning">No van registered yet.</p>
              )}
            </div>
            <div>
              <p className="text-xs text-ink-subtle">Contact</p>
              <p className="mt-1 text-sm">
                <a href={`tel:${driver.phone}`} className="text-brand hover:underline">
                  {driver.phone}
                </a>
                {driver.email ? <span className="text-ink-muted"> · {driver.email}</span> : null}
              </p>
            </div>
          </div>

          <div>
            <p className="mb-2 text-xs text-ink-subtle">Documents</p>
            {driver.documents.length === 0 ? (
              <p className="text-sm text-ink-muted">Nothing uploaded yet.</p>
            ) : (
              <ul className="space-y-2">
                {driver.documents.map((document) => (
                  <li
                    key={document.id}
                    className="flex flex-wrap items-center gap-2 rounded-md border border-line bg-surface px-3 py-2 text-sm"
                  >
                    <span className="font-medium">{document.type_display || documentLabel(document.document_type)}</span>
                    <DocumentBadge status={document.status} />
                    <span className={`text-xs ${document.is_expired ? "text-danger" : "text-ink-muted"}`}>
                      {document.is_expired ? "expired" : "expires"} {formatDate(document.expiry_date)}
                    </span>
                    {document.file ? (
                      <a
                        href={document.file}
                        target="_blank"
                        rel="noreferrer"
                        className="text-xs text-brand hover:underline"
                      >
                        Open
                      </a>
                    ) : null}
                    {document.status === "pending" ? (
                      <span className="ml-auto flex gap-2">
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={busy}
                          onClick={() => reviewDocument.mutate({ id: document.id, status: "approved" })}
                        >
                          Accept
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy}
                          onClick={() => reviewDocument.mutate({ id: document.id, status: "rejected" })}
                        >
                          Reject
                        </Button>
                      </span>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/*
           * Approval is refused server-side while a required document is
           * outstanding, so the button says so before it is pressed rather than
           * after — and names what is missing, because "not yet" on its own
           * sends somebody back to the record to work out why.
           */}
          {!ready ? (
            <p className="rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-sm text-warning">
              Accept these documents first: {outstanding.map(documentLabel).join(", ")}.
            </p>
          ) : null}

          <div className="space-y-2">
            <Textarea
              rows={2}
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder="Note — the technician reads this in their app. Optional when approving, worth writing when not."
            />

            <div className="flex flex-wrap items-center gap-2">
              <Button disabled={!ready || busy} onClick={() => decide.mutate("approved")}>
                {decide.isPending ? "Working…" : `Approve ${driver.name.split(" ")[0] || "technician"}`}
              </Button>

              {confirming === "rejected" ? (
                <>
                  <span className="text-sm text-ink-muted">Turn this application down?</span>
                  <Button size="sm" variant="danger" disabled={busy} onClick={() => decide.mutate("rejected")}>
                    Yes, reject
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setConfirming(null)}>
                    Cancel
                  </Button>
                </>
              ) : (
                <Button size="sm" variant="ghost" disabled={busy} onClick={() => setConfirming("rejected")}>
                  Reject
                </Button>
              )}

              <Link href={`/drivers/${driver.id}`} className="ml-auto text-sm text-ink-muted hover:underline">
                Full record →
              </Link>
            </div>
          </div>

          {decide.isError ? <ErrorNote>{decide.error.message}</ErrorNote> : null}
          {reviewDocument.isError ? <ErrorNote>{reviewDocument.error.message}</ErrorNote> : null}
        </div>
      ) : null}
    </li>
  );
}

function Avatar({ driver }: { driver: Driver }) {
  const initials =
    (driver.name || "")
      .split(" ")
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "—";

  return driver.photo ? (
    // The same photograph the customer is shown on the day — section 4.6.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={driver.photo} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
  ) : (
    <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-surface text-xs font-semibold text-ink-subtle">
      {initials}
    </span>
  );
}
