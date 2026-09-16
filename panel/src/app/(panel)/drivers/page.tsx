"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import {
  AlertBanner,
  Card,
  EmptyState,
  Select,
  Stat,
  StatStrip,
  VerificationBadge,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDate } from "@/lib/format";
import type { Compliance, Driver, Paginated } from "@/types/api";

const FILTERS = [
  { value: "", label: "All drivers" },
  { value: "pending", label: "Awaiting approval" },
  { value: "approved", label: "Approved" },
  { value: "suspended", label: "Suspended" },
  { value: "rejected", label: "Rejected" },
];

export default function DriversPage() {
  const [status, setStatus] = useState("");

  const drivers = useQuery({
    queryKey: ["drivers", status],
    queryFn: () => api<Paginated<Driver>>(`/drivers${status ? `?verification_status=${status}` : ""}`),
    refetchInterval: 60_000,
  });

  const compliance = useQuery({
    queryKey: ["compliance"],
    queryFn: () => api<Compliance>("/drivers/compliance"),
    refetchInterval: 60_000,
  });

  const expiring = compliance.data?.expiring ?? [];

  return (
    <div className="space-y-6">
      {compliance.data && compliance.data.counts.pending > 0 ? (
        <AlertBanner>
          <span>
            <strong>{compliance.data.counts.pending}</strong> driver
            {compliance.data.counts.pending === 1 ? "" : "s"} waiting for approval, and{" "}
            {compliance.data.pending_documents} document
            {compliance.data.pending_documents === 1 ? "" : "s"} to review.
          </span>
        </AlertBanner>
      ) : null}

      <StatStrip>
        <Stat label="Awaiting approval" value={compliance.data?.counts.pending ?? 0} tone="alert" />
        <Stat label="Approved" value={compliance.data?.counts.approved ?? 0} />
        <Stat label="Suspended" value={compliance.data?.counts.suspended ?? 0} tone="alert" />
        <Stat label="On shift now" value={compliance.data?.counts.online ?? 0} />
      </StatStrip>

      {expiring.length > 0 ? (
        <Card title="Documents expiring">
          <ul className="space-y-1 text-sm">
            {expiring.map((document) => (
              <li key={document.document_id} className="flex flex-wrap items-center gap-2">
                <Link href={`/drivers/${document.driver_id}`} className="text-brand hover:underline">
                  {document.driver_name}
                </Link>
                <span className="text-ink-muted">{document.document_type}</span>
                <span className={document.is_expired ? "text-brand" : "text-ink-muted"}>
                  {document.is_expired
                    ? `expired ${formatDate(document.expiry_date)}`
                    : `expires in ${document.days_to_expiry} days`}
                </span>
              </li>
            ))}
          </ul>
          <p className="mt-3 text-xs text-ink-subtle">
            A driver whose required documents lapse is suspended automatically (section 8.3).
          </p>
        </Card>
      ) : null}

      <Card
        title="Drivers"
        action={
          <Select value={status} onChange={(event) => setStatus(event.target.value)} className="w-48">
            {FILTERS.map((filter) => (
              <option key={filter.value} value={filter.value}>
                {filter.label}
              </option>
            ))}
          </Select>
        }
      >
        {drivers.isLoading ? <EmptyState>Loading…</EmptyState> : null}
        {drivers.data && drivers.data.results.length === 0 ? (
          <EmptyState>No drivers match this filter.</EmptyState>
        ) : null}

        {drivers.data && drivers.data.results.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs text-ink-subtle">
                <tr className="border-b border-line">
                  <th className="py-2 pr-3">Name</th>
                  <th className="py-2 pr-3">Phone</th>
                  <th className="py-2 pr-3">Van</th>
                  <th className="py-2 pr-3">Status</th>
                  <th className="py-2 pr-3">Online</th>
                  <th className="py-2 pr-3">Jobs now</th>
                  <th className="py-2 pr-3">Outstanding</th>
                </tr>
              </thead>
              <tbody>
                {drivers.data.results.map((driver) => (
                  <tr key={driver.id} className="border-b border-line last:border-0 hover:bg-surface-raised">
                    <td className="py-2 pr-3 font-medium">
                      <Link href={`/drivers/${driver.id}`} className="text-brand hover:underline">
                        {driver.name || "Unnamed"}
                      </Link>
                    </td>
                    <td className="py-2 pr-3">{driver.phone}</td>
                    <td className="py-2 pr-3">{driver.vehicles[0]?.display_plate ?? "—"}</td>
                    <td className="py-2 pr-3">
                      <VerificationBadge status={driver.verification_status} label={driver.status_display} />
                    </td>
                    {/*
                     * On shift is the one cell worth acting on from here: it is
                     * asked when somebody wants to know where that van actually
                     * is, so it answers by going there.
                     */}
                    <td className="py-2 pr-3 text-xs">
                      {driver.is_online ? (
                        <Link
                          href={`/map?driver=${driver.id}`}
                          className="inline-flex items-center gap-1.5 text-success hover:underline"
                          title="Show this driver on the live map"
                        >
                          <span aria-hidden className="live-dot h-1.5 w-1.5 rounded-full bg-success" />
                          on shift
                        </Link>
                      ) : (
                        <span className="text-ink-subtle">off</span>
                      )}
                    </td>
                    <td className="py-2 pr-3 text-xs">{driver.active_jobs}</td>
                    <td className="py-2 pr-3 text-xs text-ink-muted">
                      {driver.missing_documents.length > 0
                        ? driver.missing_documents.join(", ")
                        : driver.expired_documents.length > 0
                          ? `expired: ${driver.expired_documents.join(", ")}`
                          : "—"}
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
