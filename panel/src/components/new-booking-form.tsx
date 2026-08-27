"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { api, fieldError } from "@/lib/client-api";
import type { Booking } from "@/types/api";

import { Button, Field, Input, Select } from "./ui";

const ISSUES = [
  { value: "puncture", label: "Puncture" },
  { value: "blowout", label: "Blowout" },
  { value: "tyre_damage", label: "Tyre damage" },
  { value: "wheel_change", label: "Wheel change" },
  { value: "other", label: "Other" },
];

const EMPTY = {
  contact_name: "",
  contact_phone: "",
  plate: "",
  issue_type: "puncture",
  location_text: "",
  description: "",
  source: "phone",
};

/** Phone-in call-outs — the shop takes the details while the customer is on the line. */
export function NewBookingForm({ onCreated }: { onCreated: () => void }) {
  const [form, setForm] = useState(EMPTY);
  const queryClient = useQueryClient();

  const mutation = useMutation({
    mutationFn: (payload: typeof EMPTY) =>
      api<Booking>("/bookings", { method: "POST", body: JSON.stringify(payload) }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      queryClient.invalidateQueries({ queryKey: ["booking-stats"] });
      setForm(EMPTY);
      onCreated();
    },
  });

  function update(key: keyof typeof EMPTY) {
    return (event: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
      setForm((current) => ({ ...current, [key]: event.target.value }));
  }

  return (
    <form
      className="grid gap-3 sm:grid-cols-2"
      onSubmit={(event) => {
        event.preventDefault();
        mutation.mutate(form);
      }}
    >
      <Field label="Customer name" error={fieldError(mutation.error, "contact_name")}>
        <Input value={form.contact_name} onChange={update("contact_name")} required />
      </Field>
      <Field label="Phone" error={fieldError(mutation.error, "contact_phone")}>
        <Input value={form.contact_phone} onChange={update("contact_phone")} placeholder="07700 900123" required />
      </Field>
      <Field label="Registration (optional)" error={fieldError(mutation.error, "plate")}>
        <Input value={form.plate} onChange={update("plate")} placeholder="AB12 CDE" />
      </Field>
      <Field label="Issue">
        <Select value={form.issue_type} onChange={update("issue_type")}>
          {ISSUES.map((issue) => (
            <option key={issue.value} value={issue.value}>
              {issue.label}
            </option>
          ))}
        </Select>
      </Field>
      <div className="sm:col-span-2">
        <Field label="Location" error={fieldError(mutation.error, "location_text")}>
          <Input value={form.location_text} onChange={update("location_text")} required />
        </Field>
      </div>
      <div className="sm:col-span-2">
        <Field label="Notes" error={fieldError(mutation.error, "description")}>
          <Input value={form.description} onChange={update("description")} />
        </Field>
      </div>

      <div className="flex items-center gap-3 sm:col-span-2">
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? "Saving…" : "Create call-out"}
        </Button>
        {mutation.isError ? <span className="text-xs text-brand">{mutation.error.message}</span> : null}
      </div>
    </form>
  );
}
