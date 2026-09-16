"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { SiteHeader } from "@/components/site-header";
import { Button, Card, Field, Input, Notice } from "@/components/ui";
import { api, fieldError } from "@/lib/client-api";
import type { Paginated, SavedVehicle } from "@/types/api";

/**
 * The customer's saved cars (specification 4.2).
 *
 * The app has had this since it shipped and the API has always served it; the
 * website did not, so somebody who saved a car on their phone could not see it
 * on a laptop. A household with two cars is the ordinary case, and the tyre size
 * confirmed once here is the one the next call-out starts from.
 */
export default function GaragePage() {
  const queryClient = useQueryClient();
  const [plate, setPlate] = useState("");
  const [nickname, setNickname] = useState("");

  const vehicles = useQuery({
    queryKey: ["my-vehicles"],
    queryFn: () => api<Paginated<SavedVehicle>>("/my-vehicles"),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["my-vehicles"] });

  const add = useMutation({
    mutationFn: () =>
      api<SavedVehicle>("/my-vehicles", {
        method: "POST",
        body: JSON.stringify({ plate, nickname }),
      }),
    onSuccess: () => {
      setPlate("");
      setNickname("");
      void refresh();
    },
  });

  const remove = useMutation({
    mutationFn: (id: number) => api<null>(`/my-vehicles/${id}`, { method: "DELETE" }),
    onSuccess: refresh,
  });

  const makePrimary = useMutation({
    mutationFn: (id: number) =>
      api<SavedVehicle>(`/my-vehicles/${id}`, {
        method: "PATCH",
        body: JSON.stringify({ is_primary: true }),
      }),
    onSuccess: refresh,
  });

  const saved = vehicles.data?.results ?? [];

  return (
    <>
      <SiteHeader signedIn />
      <main className="mx-auto max-w-2xl space-y-4 px-4 py-8">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-semibold">My vehicles</h1>
          <Link href="/request">
            <Button size="sm">New call-out</Button>
          </Link>
        </div>

        <Card title="Add a vehicle">
          <form
            className="space-y-4"
            onSubmit={(event) => {
              event.preventDefault();
              add.mutate();
            }}
          >
            <Field label="Registration plate" error={fieldError(add.error, "plate")}>
              <Input
                value={plate}
                onChange={(event) => setPlate(event.target.value.toUpperCase())}
                placeholder="AB12 CDE"
                className="font-mono tracking-widest"
                required
              />
            </Field>
            <Field label="A name for it (optional)">
              <Input
                value={nickname}
                onChange={(event) => setNickname(event.target.value)}
                placeholder="The blue one"
              />
            </Field>
            {add.isError && !fieldError(add.error, "plate") ? (
              <Notice tone="error">{add.error.message}</Notice>
            ) : null}
            <Button type="submit" disabled={!plate || add.isPending}>
              {add.isPending ? "Looking it up…" : "Save this vehicle"}
            </Button>
          </form>
        </Card>

        {vehicles.isLoading ? <p className="text-sm text-ink-muted">Loading…</p> : null}

        {!vehicles.isLoading && saved.length === 0 ? (
          <Card>
            <p className="text-sm text-ink-muted">
              No vehicles saved yet. Save one and your next call-out starts with the plate and tyre
              size already filled in.
            </p>
          </Card>
        ) : null}

        <ul className="space-y-3">
          {saved.map((entry) => (
            <li key={entry.id}>
              <Card>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-mono text-base tracking-widest text-ink">
                      {entry.vehicle?.display_plate || "—"}
                    </p>
                    <p className="text-sm text-ink-muted">
                      {entry.nickname || entry.vehicle?.description || "Vehicle"}
                    </p>
                    <p className="text-xs text-ink-subtle">
                      Tyre size {entry.effective_tyre_size || "not known"}
                      {entry.confirmation_path === "overridden" ? " (you told us this)" : ""}
                      {entry.is_primary ? " · your main car" : ""}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    {entry.is_primary ? null : (
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => makePrimary.mutate(entry.id)}
                        disabled={makePrimary.isPending}
                      >
                        Make main
                      </Button>
                    )}
                    <Link href={`/request?plate=${encodeURIComponent(entry.vehicle?.plate ?? "")}`}>
                      <Button size="sm">Call out for this car</Button>
                    </Link>
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => remove.mutate(entry.id)}
                      disabled={remove.isPending}
                    >
                      Remove
                    </Button>
                  </div>
                </div>
              </Card>
            </li>
          ))}
        </ul>
      </main>
    </>
  );
}
