"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { NewBookingForm } from "@/components/new-booking-form";
import { Button, Card, EmptyState, Select, Stat, StatusBadge } from "@/components/ui";
import { api } from "@/lib/client-api";
import { timeAgo } from "@/lib/format";
import type { Booking, BookingStats, BookingStatus, Paginated } from "@/types/api";
import { STATUS_LABELS } from "@/types/api";

const FILTERS: { value: string; label: string }[] = [
  { value: "open", label: "Open call-outs" },
  { value: "received", label: "Received" },
  { value: "assigned", label: "Assigned" },
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

export default function BookingsPage() {
  const [filter, setFilter] = useState("open");
  const [creating, setCreating] = useState(false);

  // Emergencies land while nobody is looking at the tab — poll rather than wait for a click.
  const bookings = useQuery({
    queryKey: ["bookings", filter],
    queryFn: () => api<Paginated<Booking>>(`/bookings${query(filter)}`),
    refetchInterval: 15_000,
  });

  const stats = useQuery({
    queryKey: ["booking-stats"],
    queryFn: () => api<BookingStats>("/bookings/stats"),
    refetchInterval: 15_000,
  });

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Awaiting response" value={stats.data?.received ?? 0} tone="alert" />
        <Stat label="Assigned" value={stats.data?.assigned ?? 0} />
        <Stat label="In progress" value={stats.data?.in_progress ?? 0} />
        <Stat label="Completed today" value={stats.data?.completed_today ?? 0} />
      </div>

      <Card
        title="Call-outs"
        action={
          <div className="flex items-center gap-2">
            <Select value={filter} onChange={(e) => setFilter(e.target.value)} className="w-44">
              {FILTERS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Select>
            <Button onClick={() => setCreating((open) => !open)} variant={creating ? "secondary" : "primary"}>
              {creating ? "Close" : "New call-out"}
            </Button>
          </div>
        }
      >
        {creating ? (
          <div className="mb-4 rounded-md border border-slate-200 bg-slate-50 p-4">
            <NewBookingForm onCreated={() => setCreating(false)} />
          </div>
        ) : null}

        {bookings.isLoading ? <EmptyState>Loading…</EmptyState> : null}
        {bookings.isError ? <EmptyState>Could not load call-outs.</EmptyState> : null}

        {bookings.data && bookings.data.results.length === 0 ? (
          <EmptyState>Nothing here — no call-outs match this filter.</EmptyState>
        ) : null}

        {bookings.data && bookings.data.results.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                <tr className="border-b border-slate-100">
                  <th className="py-2 pr-3">Reference</th>
                  <th className="py-2 pr-3">Customer</th>
                  <th className="py-2 pr-3">Vehicle</th>
                  <th className="py-2 pr-3">Issue</th>
                  <th className="py-2 pr-3">Location</th>
                  <th className="py-2 pr-3">Status</th>
                  <th className="py-2 pr-3">Received</th>
                </tr>
              </thead>
              <tbody>
                {bookings.data.results.map((booking) => (
                  <tr key={booking.id} className="border-b border-slate-50 last:border-0 hover:bg-slate-50">
                    <td className="py-2 pr-3 font-medium">
                      <Link href={`/bookings/${booking.id}`} className="text-brand hover:underline">
                        {booking.reference}
                      </Link>
                    </td>
                    <td className="py-2 pr-3">
                      {booking.contact_name}
                      <span className="block text-xs text-ink-muted">{booking.contact_phone}</span>
                    </td>
                    <td className="py-2 pr-3">
                      {booking.plate || "—"}
                      <span className="block text-xs text-ink-muted">{booking.tyre_size || "size unknown"}</span>
                    </td>
                    <td className="py-2 pr-3">{booking.issue_display}</td>
                    <td className="py-2 pr-3 max-w-[16rem] truncate">{booking.location_text}</td>
                    <td className="py-2 pr-3">
                      <StatusBadge status={booking.status as BookingStatus} label={STATUS_LABELS[booking.status]} />
                    </td>
                    <td className="py-2 pr-3 text-xs text-ink-muted">{timeAgo(booking.created_at)}</td>
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
