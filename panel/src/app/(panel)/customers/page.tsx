"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Fragment, useState } from "react";

import {
  Button,
  Card,
  EmptyState,
  ErrorNote,
  Field,
  Input,
  Pill,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime, timeAgo } from "@/lib/format";
import type { CustomerRecord, Paginated } from "@/types/api";

/**
 * The people who ring in.
 *
 * The API has served these since customers existed and nothing called it, so the
 * office had no way to look up a caller by number, add somebody who phoned in
 * before taking their job, or re-send the code that lets a staff-created account
 * be claimed in the app. All three are things the phone demands mid-call.
 */
export default function CustomersPage() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState<number | null>(null);
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState({ name: "", phone: "", email: "" });
  const [sent, setSent] = useState<number | null>(null);

  const customers = useQuery({
    queryKey: ["customers", search],
    queryFn: () =>
      api<Paginated<CustomerRecord>>(
        `/customers${search ? `?search=${encodeURIComponent(search)}` : ""}`,
      ),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["customers"] });

  const create = useMutation({
    mutationFn: () => api<CustomerRecord>("/customers", { method: "POST", body: JSON.stringify(draft) }),
    onSuccess: () => {
      setDraft({ name: "", phone: "", email: "" });
      setAdding(false);
      void refresh();
    },
  });

  const sendCode = useMutation({
    mutationFn: (id: number) =>
      api<{ expires_at: string }>(`/customers/${id}/send-login-code`, { method: "POST", body: "{}" }),
    onSuccess: (_data, id) => setSent(id),
  });

  const rows = customers.data?.results ?? [];

  return (
    <div className="space-y-4">
      <Card
        title="Customers"
        action={
          <div className="flex items-center gap-2">
            <Input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Name, number or email"
              className="w-48"
              aria-label="Search customers"
            />
            <Button size="sm" className="whitespace-nowrap" onClick={() => setAdding((was) => !was)}>
              {adding ? "Cancel" : "Add customer"}
            </Button>
          </div>
        }
      >
        {adding ? (
          <form
            className="mb-4 grid gap-3 border-b border-line pb-4 sm:grid-cols-3"
            onSubmit={(event) => {
              event.preventDefault();
              create.mutate();
            }}
          >
            <Field label="Name">
              <Input
                value={draft.name}
                onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                required
              />
            </Field>
            <Field label="Mobile number">
              <Input
                value={draft.phone}
                onChange={(event) => setDraft({ ...draft, phone: event.target.value })}
                placeholder="07700 900123"
              />
            </Field>
            <Field label="Email (optional)">
              <Input
                type="email"
                value={draft.email}
                onChange={(event) => setDraft({ ...draft, email: event.target.value })}
              />
            </Field>
            <div className="sm:col-span-3">
              {create.isError ? <ErrorNote>{create.error.message}</ErrorNote> : null}
              <Button type="submit" size="sm" disabled={!draft.name || create.isPending}>
                {create.isPending ? "Saving…" : "Save customer"}
              </Button>
            </div>
          </form>
        ) : null}

        {customers.isError ? <ErrorNote>{customers.error.message}</ErrorNote> : null}

        {rows.length === 0 && !customers.isLoading ? (
          <EmptyState>
            {search ? "Nobody matches that." : "No customer records yet."}
          </EmptyState>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left text-xs uppercase tracking-wide text-ink-subtle">
                <th className="py-2">Customer</th>
                <th className="py-2">Contact</th>
                <th className="py-2">Call-outs</th>
                <th className="py-2">Last seen</th>
                <th className="py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map((customer) => (
                <Fragment key={customer.id}>
                  <tr className="border-b border-line align-top">
                    <td className="py-2.5">
                      <span className="text-ink">{customer.name || "—"}</span>
                      {customer.is_phone_verified ? null : (
                        <Pill className="ml-2">unverified</Pill>
                      )}
                      {customer.is_active ? null : <Pill className="ml-2">disabled</Pill>}
                    </td>
                    <td className="py-2.5 font-mono text-xs text-ink-muted">
                      <span className="block">{customer.phone || "no number"}</span>
                      <span className="block">{customer.email || ""}</span>
                    </td>
                    <td className="py-2.5 text-ink-muted">{customer.job_count}</td>
                    <td className="py-2.5 text-ink-muted">
                      {customer.last_login_at ? timeAgo(customer.last_login_at) : "never signed in"}
                    </td>
                    <td className="py-2.5 text-right">
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => setOpen(open === customer.id ? null : customer.id)}
                      >
                        {open === customer.id ? "Close" : "Open"}
                      </Button>
                    </td>
                  </tr>
                  {open === customer.id ? (
                    <tr className="border-b border-line bg-surface-sunken">
                      <td colSpan={5} className="px-3 py-3">
                        <div className="grid gap-3 sm:grid-cols-3">
                          <div>
                            <p className="text-xs uppercase tracking-wide text-ink-subtle">Signed up</p>
                            <p className="text-ink">{formatDateTime(customer.created_at)}</p>
                          </div>
                          <div>
                            <p className="text-xs uppercase tracking-wide text-ink-subtle">
                              Saved vehicles
                            </p>
                            <p className="text-ink">{customer.vehicle_count}</p>
                          </div>
                          <div>
                            <p className="text-xs uppercase tracking-wide text-ink-subtle">Sign-in</p>
                            <p className="text-ink">
                              {customer.identities.length > 0
                                ? customer.identities.map((identity) => identity.provider).join(", ")
                                : "phone only"}
                            </p>
                          </div>
                        </div>

                        {customer.notes ? (
                          <p className="mt-3 text-sm text-ink-muted">{customer.notes}</p>
                        ) : null}

                        <div className="mt-3 flex flex-wrap items-center gap-3">
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={!customer.phone || sendCode.isPending}
                            onClick={() => sendCode.mutate(customer.id)}
                          >
                            Text a sign-in code
                          </Button>
                          {sent === customer.id ? (
                            <span className="text-xs text-success">
                              Code sent — they can claim the account in the app.
                            </span>
                          ) : null}
                          {!customer.phone ? (
                            <span className="text-xs text-ink-subtle">
                              No number on file, so there is nowhere to send it.
                            </span>
                          ) : null}
                        </div>
                        {sendCode.isError ? <ErrorNote>{sendCode.error.message}</ErrorNote> : null}
                      </td>
                    </tr>
                  ) : null}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  );
}
