"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, EmptyState, Field, Input } from "@/components/ui";
import { api, fieldError } from "@/lib/client-api";
import { formatDateTime } from "@/lib/format";
import type { Driver, Paginated } from "@/types/api";

const EMPTY = { name: "", phone: "", email: "", notes: "" };

export default function DriversPage() {
  const [search, setSearch] = useState("");
  const [form, setForm] = useState(EMPTY);
  const queryClient = useQueryClient();

  const drivers = useQuery({
    queryKey: ["drivers", search],
    queryFn: () => api<Paginated<Driver>>(`/drivers?search=${encodeURIComponent(search)}`),
  });

  const create = useMutation({
    mutationFn: (payload: typeof EMPTY) =>
      api<Driver>("/drivers", { method: "POST", body: JSON.stringify(payload) }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["drivers"] });
      setForm(EMPTY);
    },
  });

  const sendCode = useMutation({
    mutationFn: (id: number) => api(`/drivers/${id}/send-login-code`, { method: "POST" }),
  });

  return (
    <div className="grid gap-4 lg:grid-cols-3">
      <div className="lg:col-span-2">
        <Card
          title="Drivers"
          action={
            <Input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search name or phone"
              className="w-56"
            />
          }
        >
          {drivers.isLoading ? <EmptyState>Loading…</EmptyState> : null}
          {drivers.data?.results.length === 0 ? <EmptyState>No drivers yet.</EmptyState> : null}

          {drivers.data && drivers.data.results.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-slate-100">
                    <th className="py-2 pr-3">Name</th>
                    <th className="py-2 pr-3">Phone</th>
                    <th className="py-2 pr-3">Verified</th>
                    <th className="py-2 pr-3">Vehicles</th>
                    <th className="py-2 pr-3">Last login</th>
                    <th className="py-2" />
                  </tr>
                </thead>
                <tbody>
                  {drivers.data.results.map((driver) => (
                    <tr key={driver.id} className="border-b border-slate-50 last:border-0">
                      <td className="py-2 pr-3">{driver.name || "—"}</td>
                      <td className="py-2 pr-3">{driver.phone}</td>
                      <td className="py-2 pr-3">
                        {driver.is_phone_verified ? (
                          <span className="text-emerald-700">Yes</span>
                        ) : (
                          <span className="text-amber-700">Pending</span>
                        )}
                      </td>
                      <td className="py-2 pr-3">{driver.vehicle_count}</td>
                      <td className="py-2 pr-3 text-xs text-ink-muted">{formatDateTime(driver.last_login_at)}</td>
                      <td className="py-2 text-right">
                        <Button
                          variant="ghost"
                          disabled={sendCode.isPending}
                          onClick={() => sendCode.mutate(driver.id)}
                        >
                          Send login code
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
        </Card>
      </div>

      <Card title="Add a driver">
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            create.mutate(form);
          }}
        >
          <Field label="Name" error={fieldError(create.error, "name")}>
            <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </Field>
          <Field label="Phone" error={fieldError(create.error, "phone")}>
            <Input
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
              placeholder="07700 900123"
              required
            />
          </Field>
          <Field label="Email" error={fieldError(create.error, "email")}>
            <Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          </Field>
          <Field label="Internal notes" error={fieldError(create.error, "notes")}>
            <Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
          </Field>

          <Button type="submit" disabled={create.isPending} className="w-full">
            {create.isPending ? "Saving…" : "Add driver"}
          </Button>
          <p className="text-xs text-ink-muted">
            The driver stays unverified until they sign in with a code — send one from the list.
          </p>
        </form>
      </Card>
    </div>
  );
}
