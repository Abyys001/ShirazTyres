"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, EmptyState, ErrorNote, Field, Input, Textarea } from "@/components/ui";
import { api } from "@/lib/client-api";
import type { Paginated, ServiceArea } from "@/types/api";

/**
 * Service-area boundaries and their per-area dispatch overrides (specification 12).
 *
 * Boundaries are GeoJSON, entered as text: they come from a drawing tool or from the
 * council boundary file, and re-implementing a polygon editor here would be worse than
 * pasting what those already produce.
 */
export function ServiceAreas() {
  const queryClient = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<number | null>(null);

  const areas = useQuery({
    queryKey: ["service-areas"],
    queryFn: () => api<Paginated<ServiceArea>>("/service-areas"),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["service-areas"] });

  const create = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      api<ServiceArea>("/service-areas", { method: "POST", body: JSON.stringify(payload) }),
    onSuccess: () => {
      setAdding(false);
      void refresh();
    },
  });

  const update = useMutation({
    mutationFn: (payload: { id: number; body: Record<string, unknown> }) =>
      api<ServiceArea>(`/service-areas/${payload.id}`, {
        method: "PATCH",
        body: JSON.stringify(payload.body),
      }),
    onSuccess: () => {
      setEditing(null);
      void refresh();
    },
  });

  return (
    <Card
      title="Areas"
      action={
        <Button size="sm" variant={adding ? "secondary" : "primary"} onClick={() => setAdding((open) => !open)}>
          {adding ? "Cancel" : "Add area"}
        </Button>
      }
    >
      {adding ? <AreaForm onSubmit={(body) => create.mutate(body)} pending={create.isPending} /> : null}
      {create.isError ? <ErrorNote>{create.error.message}</ErrorNote> : null}
      {update.isError ? <ErrorNote>{update.error.message}</ErrorNote> : null}

      {areas.data && areas.data.results.length === 0 ? (
        <EmptyState>
          No areas configured. Until one exists every location is treated as covered, so the site does not
          refuse everybody during setup.
        </EmptyState>
      ) : null}

      <ul className="space-y-3">
        {(areas.data?.results ?? []).map((area) => (
          <li key={area.id} className="rounded-md border border-line p-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="text-sm font-medium">
                  {area.name}
                  {!area.is_active ? <span className="ml-2 text-xs text-ink-muted">(inactive)</span> : null}
                </p>
                <p className="text-xs text-ink-muted">
                  priority {area.priority} · {area.driver_count} driver
                  {area.driver_count === 1 ? "" : "s"} ·{" "}
                  {Object.keys(area.dispatch_overrides ?? {}).length} dispatch override
                  {Object.keys(area.dispatch_overrides ?? {}).length === 1 ? "" : "s"}
                </p>
              </div>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => update.mutate({ id: area.id, body: { is_active: !area.is_active } })}
                >
                  {area.is_active ? "Deactivate" : "Activate"}
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => setEditing(editing === area.id ? null : area.id)}
                >
                  {editing === area.id ? "Close" : "Edit"}
                </Button>
              </div>
            </div>

            {editing === area.id ? (
              <AreaForm
                area={area}
                pending={update.isPending}
                onSubmit={(body) => update.mutate({ id: area.id, body })}
              />
            ) : null}
          </li>
        ))}
      </ul>
    </Card>
  );
}

function AreaForm({
  area,
  pending,
  onSubmit,
}: {
  area?: ServiceArea;
  pending: boolean;
  onSubmit: (body: Record<string, unknown>) => void;
}) {
  const [error, setError] = useState<string | null>(null);

  return (
    <form
      className="mt-3 space-y-3 rounded-md border border-line bg-surface-raised p-3"
      onSubmit={(event) => {
        event.preventDefault();
        const form = new FormData(event.currentTarget);
        try {
          onSubmit({
            name: form.get("name"),
            priority: Number(form.get("priority") ?? 0),
            boundary: JSON.parse(String(form.get("boundary"))),
            dispatch_overrides: JSON.parse(String(form.get("dispatch_overrides") || "{}")),
            notes: form.get("notes") || "",
          });
          setError(null);
        } catch {
          setError("The boundary or the overrides are not valid JSON.");
        }
      }}
    >
      <div className="grid gap-2 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field label="Name">
            <Input name="name" defaultValue={area?.name} required />
          </Field>
        </div>
        <Field label="Priority" hint="Higher wins where areas overlap">
          <Input name="priority" type="number" defaultValue={area?.priority ?? 0} />
        </Field>
      </div>

      <Field label="Boundary (GeoJSON Polygon, [longitude, latitude])">
        <Textarea
          name="boundary"
          rows={5}
          className="font-mono text-xs"
          defaultValue={JSON.stringify(area?.boundary ?? { type: "Polygon", coordinates: [] }, null, 2)}
          required
        />
      </Field>

      <Field label="Dispatch overrides" hint="Only dispatch.* keys are accepted">
        <Textarea
          name="dispatch_overrides"
          rows={3}
          className="font-mono text-xs"
          defaultValue={JSON.stringify(area?.dispatch_overrides ?? {}, null, 2)}
        />
      </Field>

      <Field label="Notes">
        <Input name="notes" defaultValue={area?.notes} />
      </Field>

      {error ? <ErrorNote>{error}</ErrorNote> : null}

      <Button type="submit" size="sm" disabled={pending}>
        {pending ? "Saving…" : "Save area"}
      </Button>
    </form>
  );
}
