"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Button,
  Card,
  Detail,
  DocumentBadge,
  EmptyState,
  ErrorNote,
  Field,
  Input,
  VerificationBadge,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDate, formatDateTime } from "@/lib/format";
import type {
  Driver,
  DriverDocument,
  DriverLocationFix,
  Paginated,
  ServiceArea,
  VerificationStatus,
} from "@/types/api";

export default function DriverPage() {
  const params = useParams<{ id: string }>();
  const id = Number(params.id);
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");
  const [confirming, setConfirming] = useState<"suspended" | "rejected" | null>(null);

  // The roster, the approval queue and the rail's waiting badge all read the
  // same standing, so a decision taken here has to move every one of them.
  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ["driver", id] });
    void queryClient.invalidateQueries({ queryKey: ["drivers"] });
    void queryClient.invalidateQueries({ queryKey: ["compliance"] });
  };

  const driver = useQuery({
    queryKey: ["driver", id],
    queryFn: () => api<Driver>(`/drivers/${id}`),
  });

  const areas = useQuery({
    queryKey: ["service-areas"],
    queryFn: () => api<Paginated<ServiceArea>>("/service-areas"),
  });

  // The card below promised a history the page never fetched. It is the record
  // the office reaches for when a customer disputes where a van was and when.
  const history = useQuery({
    queryKey: ["driver-history", id],
    queryFn: () => api<DriverLocationFix[]>(`/drivers/${id}/location-history`),
  });

  const setVerification = useMutation({
    mutationFn: (verification_status: VerificationStatus) =>
      api<Driver>(`/drivers/${id}/verification`, {
        method: "POST",
        body: JSON.stringify({ verification_status, note }),
      }),
    onSuccess: () => {
      setNote("");
      setConfirming(null);
      void refresh();
    },
  });

  const reviewDocument = useMutation({
    mutationFn: (payload: { documentId: number; status: "approved" | "rejected"; note: string }) =>
      api<DriverDocument>(`/driver-documents/${payload.documentId}/review`, {
        method: "POST",
        body: JSON.stringify({ status: payload.status, note: payload.note }),
      }),
    onSuccess: refresh,
  });

  const saveAreas = useMutation({
    mutationFn: (service_area_ids: number[]) =>
      api<Driver>(`/drivers/${id}`, { method: "PATCH", body: JSON.stringify({ service_area_ids }) }),
    onSuccess: refresh,
  });

  if (driver.isLoading) return <EmptyState>Loading…</EmptyState>;
  if (driver.isError || !driver.data) return <EmptyState>Could not load this driver.</EmptyState>;

  const data = driver.data;
  const blocked = data.missing_documents.length > 0;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/drivers" className="text-sm text-ink-muted hover:underline">
          ← Drivers
        </Link>
        <h1 className="text-lg font-semibold">{data.name || "Unnamed driver"}</h1>
        <VerificationBadge status={data.verification_status} label={data.status_display} />
        {data.is_online ? <span className="text-xs text-success">online</span> : null}
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Card title="Profile">
            <div className="flex gap-4">
              {data.photo ? (
                // The customer sees this photograph too — section 4.6.
                // eslint-disable-next-line @next/next/no-img-element
                <img src={data.photo} alt="" className="h-24 w-24 rounded-md object-cover" />
              ) : (
                <div className="flex h-24 w-24 items-center justify-center rounded-md bg-surface-raised text-xs text-ink-subtle">
                  no photo
                </div>
              )}
              <dl className="grid flex-1 gap-4 sm:grid-cols-2">
                <Detail label="Phone" value={<a href={`tel:${data.phone}`}>{data.phone}</a>} />
                <Detail label="Email" value={data.email} />
                <Detail label="Employment reference" value={data.employment_reference} />
                <Detail label="Approved" value={formatDateTime(data.approved_at)} />
                <Detail label="Jobs in hand" value={String(data.active_jobs)} />
                <Detail label="Last sign-in" value={formatDateTime(data.last_login_at)} />
              </dl>
            </div>
          </Card>

          <Card title="Vehicles">
            {data.vehicles.length === 0 ? (
              <EmptyState>No van registered yet.</EmptyState>
            ) : (
              <ul className="space-y-2 text-sm">
                {data.vehicles.map((vehicle) => (
                  <li key={vehicle.id} className="flex items-center justify-between">
                    <span>
                      <span className="font-mono">{vehicle.display_plate}</span>{" "}
                      <span className="text-ink-muted">{vehicle.description}</span>
                    </span>
                    {vehicle.is_primary ? <span className="text-xs text-ink-muted">primary</span> : null}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card title="Documents">
            {data.documents.length === 0 ? (
              <EmptyState>Nothing uploaded yet.</EmptyState>
            ) : (
              <ul className="space-y-3">
                {data.documents.map((document) => (
                  <li key={document.id} className="rounded-md border border-line p-3">
                    <div className="flex flex-wrap items-center gap-2 text-sm">
                      <span className="font-medium">{document.type_display}</span>
                      <DocumentBadge status={document.status} />
                      <span className={`text-xs ${document.is_expired ? "text-brand" : "text-ink-muted"}`}>
                        expires {formatDate(document.expiry_date)}
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
                    </div>
                    {document.review_note ? (
                      <p className="mt-1 text-xs text-ink-muted">{document.review_note}</p>
                    ) : null}
                    <div className="mt-2 flex gap-2">
                      <Button
                        size="sm"
                        variant="secondary"
                        disabled={reviewDocument.isPending}
                        onClick={() =>
                          reviewDocument.mutate({ documentId: document.id, status: "approved", note: "" })
                        }
                      >
                        Approve
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={reviewDocument.isPending}
                        onClick={() =>
                          reviewDocument.mutate({
                            documentId: document.id,
                            status: "rejected",
                            note: "Rejected in the panel.",
                          })
                        }
                      >
                        Reject
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
            {reviewDocument.isError ? <ErrorNote>{reviewDocument.error.message}</ErrorNote> : null}
          </Card>
        </div>

        <div className="space-y-6">
          {/*
            * The standing, and what changing it costs. Three identical buttons
            * in a row treated "approve" and "reject" as the same kind of act;
            * they are not, and the one that ends somebody's employment should
            * not be a mis-tap away from the one that starts it.
            */}
          <Card title="Standing">
            <div className="mb-3 flex items-center gap-2">
              <VerificationBadge status={data.verification_status} label={data.status_display} />
              {data.verification_status === "approved" ? (
                <span className="text-xs text-ink-subtle">since {formatDateTime(data.approved_at)}</span>
              ) : null}
            </div>

            <p className="mb-3 text-xs text-ink-muted">
              Only approved drivers enter the dispatch pool (section 8.2). Until then their app shows them
              a wait and no jobs at all, so this is the decision they are held up on.
            </p>

            {blocked ? (
              <p className="mb-3 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-xs text-warning">
                Approval is refused while a required document is outstanding. Accept these first:{" "}
                {data.missing_documents.join(", ")}.
              </p>
            ) : null}

            <Field label="Note" hint="The technician reads this in their app.">
              <Input
                value={note}
                onChange={(event) => setNote(event.target.value)}
                placeholder={data.verification_status === "approved" ? "Why this is changing" : "Optional"}
              />
            </Field>

            <div className="mt-3 space-y-2">
              {data.verification_status === "approved" ? null : (
                <Button
                  className="w-full"
                  disabled={blocked || setVerification.isPending}
                  onClick={() => setVerification.mutate("approved")}
                >
                  {setVerification.isPending ? "Working…" : "Approve for dispatch"}
                </Button>
              )}

              {confirming ? (
                <div className="space-y-2 rounded-md border border-line-strong p-3">
                  <p className="text-sm">
                    {confirming === "suspended"
                      ? "Suspend this driver? They come off shift immediately and are offered no further work."
                      : "Reject this driver? They keep their sign-in but are never offered work."}
                  </p>
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      variant="danger"
                      disabled={setVerification.isPending}
                      onClick={() => setVerification.mutate(confirming)}
                    >
                      Yes, {confirming === "suspended" ? "suspend" : "reject"}
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => setConfirming(null)}>
                      Cancel
                    </Button>
                  </div>
                </div>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {data.verification_status === "suspended" ? null : (
                    <Button size="sm" variant="secondary" onClick={() => setConfirming("suspended")}>
                      Suspend
                    </Button>
                  )}
                  {data.verification_status === "rejected" ? null : (
                    <Button size="sm" variant="ghost" onClick={() => setConfirming("rejected")}>
                      Reject
                    </Button>
                  )}
                </div>
              )}
            </div>

            {setVerification.isError ? <ErrorNote>{setVerification.error.message}</ErrorNote> : null}
          </Card>

          <Card title="Service areas">
            <p className="mb-2 text-xs text-ink-muted">
              With none selected the driver is dispatchable everywhere.
            </p>
            <div className="space-y-1">
              {(areas.data?.results ?? []).map((area) => {
                const selected = data.service_area_ids.includes(area.id);
                return (
                  <label key={area.id} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={selected}
                      onChange={() =>
                        saveAreas.mutate(
                          selected
                            ? data.service_area_ids.filter((value) => value !== area.id)
                            : [...data.service_area_ids, area.id],
                        )
                      }
                    />
                    {area.name}
                  </label>
                );
              })}
            </div>
          </Card>

          <Card title="Tracking">
            <dl className="grid gap-3">
              <Detail label="Last fix" value={formatDateTime(data.location_updated_at)} />
              <Detail
                label="Position"
                value={data.latitude ? `${data.latitude}, ${data.longitude}` : "not online"}
              />
            </dl>
            <p className="mt-3 text-xs text-ink-subtle">
              Location history is kept for the configured retention period and then purged (section 18).
            </p>

            {history.data && history.data.length > 0 ? (
              <div className="mt-4 border-t border-line pt-3">
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-subtle">
                  Recent fixes
                </p>
                <ul className="max-h-64 space-y-1 overflow-y-auto font-mono text-xs text-ink-muted">
                  {history.data.map((fix) => (
                    <li key={fix.id} className="flex justify-between gap-3">
                      <span className="text-ink">{formatDateTime(fix.recorded_at)}</span>
                      <span>
                        {fix.latitude}, {fix.longitude}
                        {fix.accuracy_m !== null ? ` ±${fix.accuracy_m}m` : ""}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            ) : (
              <p className="mt-3 text-xs text-ink-subtle">
                {history.isLoading ? "Loading history…" : "No fixes recorded for this driver yet."}
              </p>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
