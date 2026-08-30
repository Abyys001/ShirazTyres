"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, EmptyState, ErrorNote, Field, Input, Select } from "@/components/ui";
import { api } from "@/lib/client-api";
import { money } from "@/lib/format";
import type { Paginated, ServiceItem } from "@/types/api";

/** The price list the driver picks from on site (specification 7.1 step 3, 12). */
export function PriceList() {
  const queryClient = useQueryClient();
  const [adding, setAdding] = useState(false);

  const items = useQuery({
    queryKey: ["service-items"],
    queryFn: () => api<Paginated<ServiceItem>>("/service-items"),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["service-items"] });

  const create = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      api<ServiceItem>("/service-items", { method: "POST", body: JSON.stringify(payload) }),
    onSuccess: () => {
      setAdding(false);
      void refresh();
    },
  });

  const toggle = useMutation({
    mutationFn: (item: ServiceItem) =>
      api<ServiceItem>(`/service-items/${item.id}`, {
        method: "PATCH",
        body: JSON.stringify({ is_active: !item.is_active }),
      }),
    onSuccess: refresh,
  });

  return (
    <Card
      title="Price list"
      action={
        <Button size="sm" variant={adding ? "secondary" : "primary"} onClick={() => setAdding((open) => !open)}>
          {adding ? "Cancel" : "Add item"}
        </Button>
      }
    >
      {adding ? (
        <form
          className="mb-4 grid gap-2 rounded-md border border-line bg-surface-raised p-3 sm:grid-cols-5"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            create.mutate({
              code: form.get("code"),
              name: form.get("name"),
              kind: form.get("kind"),
              unit_price: form.get("unit_price"),
              unit: form.get("unit") || "",
            });
          }}
        >
          <Field label="Code">
            <Input name="code" required />
          </Field>
          <div className="sm:col-span-2">
            <Field label="Name">
              <Input name="name" required />
            </Field>
          </div>
          <Field label="Kind">
            <Select name="kind" defaultValue="part">
              <option value="part">Part</option>
              <option value="labour">Labour</option>
              <option value="other">Other</option>
            </Select>
          </Field>
          <Field label="Price">
            <Input name="unit_price" required inputMode="decimal" />
          </Field>
          <div className="sm:col-span-5">
            <Button type="submit" size="sm" disabled={create.isPending}>
              Add
            </Button>
          </div>
        </form>
      ) : null}

      {create.isError ? <ErrorNote>{create.error.message}</ErrorNote> : null}

      {items.data && items.data.results.length === 0 ? <EmptyState>No items yet.</EmptyState> : null}

      <ul className="divide-y divide-line text-sm">
        {(items.data?.results ?? []).map((item) => (
          <li key={item.id} className="flex items-center justify-between py-2">
            <span>
              {item.name}
              <span className="ml-2 font-mono text-xs text-ink-subtle">{item.code}</span>
              {!item.is_active ? <span className="ml-2 text-xs text-ink-muted">(hidden)</span> : null}
            </span>
            <span className="flex items-center gap-3">
              <span>
                {money(item.unit_price)} {item.unit ? `/ ${item.unit}` : ""}
              </span>
              <Button size="sm" variant="ghost" onClick={() => toggle.mutate(item)}>
                {item.is_active ? "Hide" : "Show"}
              </Button>
            </span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
