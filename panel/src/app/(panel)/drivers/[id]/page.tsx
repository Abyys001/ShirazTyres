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
import type { Driver, DriverDocument, Paginated, ServiceArea, VerificationStatus } from "@/types/api";

export default function DriverPage() {
  const params = useParams<{ id: string }>();
  const id = Number(params.id);
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["driver", id] });

  const driver = useQuery({
    queryKey: ["driver", id],
    queryFn: () => api<Driver>(`/drivers/${id}`),
  });

  const areas = useQuery({
    queryKey: ["service-areas"],
    queryFn: () => api<Paginated<ServiceArea>>("/service-areas"),
  });

  const setVerification = useMutation({
    mutationFn: (verification_status: VerificationStatus) =>
      api<Driver>(`/drivers/${id}/verification`, {
        method: "POST",
        body: JSON.stringify({ verification_status, note }),
      }),
    onSuccess: () => {
      setNote("");
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
          <Card title="Verification">
            <p className="mb-3 text-xs text-ink-muted">
              Only approved drivers enter the dispatch pool (section 8.2), and approval is refused while a
              required document is missing.
            </p>
            {data.missing_documents.length > 0 ? (
              <p className="mb-3 text-xs text-brand">Outstanding: {data.missing_documents.join(", ")}</p>
            ) : null}
            <Field label="Note">
              <Input value={note} onChange={(event) => setNote(event.target.value)} />
            </Field>
            <div className="mt-2 flex flex-wrap gap-2">
              <Button size="sm" onClick={() => setVerification.mutate("approved")}>
                Approve
              </Button>
              <Button size="sm" variant="secondary" onClick={() => setVerification.mutate("suspended")}>
                Suspend
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setVerification.mutate("rejected")}>
                Reject
              </Button>
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
          </Card>
        </div>
      </div>
    </div>
  );
}
