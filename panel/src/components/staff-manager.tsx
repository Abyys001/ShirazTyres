"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, EmptyState, ErrorNote, Field, Input, Pill, Select } from "@/components/ui";
import { api, fieldError } from "@/lib/client-api";
import { formatDateTime } from "@/lib/format";
import type { Paginated, StaffUser } from "@/types/api";

const ROLES: { value: StaffUser["role"]; label: string; help: string }[] = [
  { value: "owner", label: "Owner", help: "Everything, including other owners." },
  {
    value: "shop_owner",
    label: "Shop owner",
    help: "Runs the business day to day — staff, settings, invoices.",
  },
  { value: "staff", label: "Office", help: "Works the board: jobs, drivers, invoices." },
];

function roleLabel(role: StaffUser["role"]): string {
  return ROLES.find((option) => option.value === role)?.label ?? role;
}

/**
 * Who can sign in to the panel.
 *
 * Adding a colleague previously meant `manage.py createsuperuser` on a
 * production box, which in practice meant it never happened and everybody shared
 * the owner's login — so the job history recorded one person doing everything.
 * Restricted to owners and shop owners by the API; the office works the board,
 * it does not decide who else can.
 */
export function StaffManager({ me }: { me: StaffUser }) {
  const queryClient = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [resetting, setResetting] = useState<number | null>(null);

  const staff = useQuery({
    queryKey: ["staff"],
    queryFn: () => api<Paginated<StaffUser>>("/staff"),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["staff"] });

  const create = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api<StaffUser>("/staff", { method: "POST", body: JSON.stringify(body) }),
    onSuccess: () => {
      setAdding(false);
      void refresh();
    },
  });

  const update = useMutation({
    mutationFn: ({ id, body }: { id: number; body: Record<string, unknown> }) =>
      api<StaffUser>(`/staff/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
    onSuccess: refresh,
  });

  const deactivate = useMutation({
    mutationFn: (id: number) => api<void>(`/staff/${id}`, { method: "DELETE" }),
    onSuccess: refresh,
  });

  const rows = staff.data?.results ?? [];

  if (staff.isError) {
    return (
      <Card title="Staff">
        <EmptyState>
          Only an owner or shop owner can manage panel accounts.
        </EmptyState>
      </Card>
    );
  }

  return (
    <Card
      title="Staff"
      action={
        <Button size="sm" variant={adding ? "secondary" : "primary"} onClick={() => setAdding((v) => !v)}>
          {adding ? "Close" : "Add someone"}
        </Button>
      }
    >
      {adding ? (
        <form
          className="mb-4 space-y-3 rounded-md border border-line bg-surface-raised p-4"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            create.mutate({
              name: String(form.get("name") ?? "").trim(),
              email: String(form.get("email") ?? "").trim(),
              role: String(form.get("role") ?? "staff"),
              password: String(form.get("password") ?? ""),
            });
          }}
        >
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Name" error={fieldError(create.error, "name")}>
              <Input name="name" required autoComplete="off" />
            </Field>
            <Field label="Email" error={fieldError(create.error, "email")}>
              <Input name="email" type="email" required autoComplete="off" />
            </Field>
            <Field label="Role" error={fieldError(create.error, "role")}>
              <Select name="role" defaultValue="staff">
                {ROLES.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label} — {option.help}
                  </option>
                ))}
              </Select>
            </Field>
            <Field
              label="Password"
              hint="At least 8 characters. They can change it once they are in."
              error={fieldError(create.error, "password")}
            >
              <Input name="password" type="password" required minLength={8} autoComplete="new-password" />
            </Field>
          </div>
          {create.isError ? <ErrorNote>{create.error.message}</ErrorNote> : null}
          <Button type="submit" size="sm" disabled={create.isPending}>
            {create.isPending ? "Creating…" : "Create account"}
          </Button>
        </form>
      ) : null}

      {update.isError ? <ErrorNote>{update.error.message}</ErrorNote> : null}
      {deactivate.isError ? <ErrorNote>{deactivate.error.message}</ErrorNote> : null}

      {staff.isLoading ? <EmptyState>Loading…</EmptyState> : null}

      {rows.length > 0 ? (
        <div className="-mx-4 overflow-x-auto">
          <table className="w-full min-w-[42rem] border-collapse text-sm">
            <thead>
              <tr className="border-b border-line text-left text-xs text-ink-subtle">
                <th className="py-2 pl-4 pr-3 font-medium">Name</th>
                <th className="py-2 pr-3 font-medium">Email</th>
                <th className="py-2 pr-3 font-medium">Role</th>
                <th className="py-2 pr-3 font-medium">Since</th>
                <th className="py-2 pr-4 font-medium" />
              </tr>
            </thead>
            <tbody>
              {rows.map((user) => {
                const self = user.id === me.id;
                return (
                  <tr key={user.id} className="border-b border-line last:border-0 align-top">
                    <td className="py-2.5 pl-4 pr-3">
                      <span className="text-ink">{user.name}</span>
                      {self ? (
                        <Pill className="chip-brand ml-2">you</Pill>
                      ) : user.is_active ? null : (
                        <Pill className="chip-muted ml-2">deactivated</Pill>
                      )}
                    </td>
                    <td className="py-2.5 pr-3 text-ink-muted">{user.email}</td>
                    <td className="py-2.5 pr-3">
                      {/* Nobody edits their own role: it is the one change that
                          can lock the last owner out of their own panel. */}
                      {self ? (
                        <span className="text-ink-muted">{roleLabel(user.role)}</span>
                      ) : (
                        <Select
                          value={user.role}
                          onChange={(event) =>
                            update.mutate({ id: user.id, body: { role: event.target.value } })
                          }
                          className="w-36"
                        >
                          {ROLES.map((option) => (
                            <option key={option.value} value={option.value}>
                              {option.label}
                            </option>
                          ))}
                        </Select>
                      )}
                    </td>
                    <td className="py-2.5 pr-3 text-xs text-ink-subtle">
                      {formatDateTime(user.date_joined)}
                    </td>
                    <td className="py-2.5 pr-4">
                      {self ? null : (
                        <div className="flex justify-end gap-2">
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setResetting(resetting === user.id ? null : user.id)}
                          >
                            Set password
                          </Button>
                          {user.is_active ? (
                            <Button
                              size="sm"
                              variant="ghost"
                              className="text-danger"
                              onClick={() => deactivate.mutate(user.id)}
                              disabled={deactivate.isPending}
                            >
                              Deactivate
                            </Button>
                          ) : (
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() => update.mutate({ id: user.id, body: { is_active: true } })}
                            >
                              Reactivate
                            </Button>
                          )}
                        </div>
                      )}
                      {resetting === user.id ? (
                        <SetPassword userId={user.id} onDone={() => setResetting(null)} />
                      ) : null}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : null}
    </Card>
  );
}

/** An administrator setting somebody else's password — the forgotten-password path. */
function SetPassword({ userId, onDone }: { userId: number; onDone: () => void }) {
  const [value, setValue] = useState("");

  const save = useMutation({
    mutationFn: () =>
      api<StaffUser>(`/staff/${userId}/set-password`, {
        method: "POST",
        body: JSON.stringify({ new_password: value }),
      }),
    onSuccess: onDone,
  });

  return (
    <div className="mt-2 space-y-2 rounded-md border border-line bg-surface-raised p-3">
      <Field label="New password" error={fieldError(save.error, "new_password")}>
        <Input
          type="password"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          minLength={8}
          autoComplete="new-password"
        />
      </Field>
      {save.isError ? <ErrorNote>{save.error.message}</ErrorNote> : null}
      <div className="flex gap-2">
        <Button size="sm" onClick={() => save.mutate()} disabled={value.length < 8 || save.isPending}>
          {save.isPending ? "Saving…" : "Set it"}
        </Button>
        <Button size="sm" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

/** Changing your own password, from the account menu. */
export function ChangePasswordForm({ onDone }: { onDone: () => void }) {
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [done, setDone] = useState(false);

  const save = useMutation({
    mutationFn: () =>
      api<{ detail: string }>("/auth/staff/password", {
        method: "POST",
        body: JSON.stringify({ current_password: current, new_password: next }),
      }),
    onSuccess: () => {
      setDone(true);
      setCurrent("");
      setNext("");
    },
  });

  if (done) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-success">Password changed. You stay signed in here.</p>
        <Button size="sm" variant="secondary" onClick={onDone}>
          Close
        </Button>
      </div>
    );
  }

  return (
    <form
      className="space-y-3"
      onSubmit={(event) => {
        event.preventDefault();
        save.mutate();
      }}
    >
      <Field label="Current password" error={fieldError(save.error, "current_password")}>
        <Input
          type="password"
          value={current}
          onChange={(event) => setCurrent(event.target.value)}
          required
          autoComplete="current-password"
        />
      </Field>
      <Field
        label="New password"
        hint="At least 8 characters."
        error={fieldError(save.error, "new_password")}
      >
        <Input
          type="password"
          value={next}
          onChange={(event) => setNext(event.target.value)}
          required
          minLength={8}
          autoComplete="new-password"
        />
      </Field>
      {save.isError ? <ErrorNote>{save.error.message}</ErrorNote> : null}
      <div className="flex gap-2">
        <Button type="submit" size="sm" disabled={save.isPending}>
          {save.isPending ? "Changing…" : "Change password"}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
