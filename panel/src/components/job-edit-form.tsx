"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, ErrorNote, Field, Input, Select, Textarea } from "@/components/ui";
import { api, fieldError } from "@/lib/client-api";
import type { JobDetail } from "@/types/api";

interface PublicConfig {
  issue_types: { value: string; label: string }[];
}

/**
 * Everything on a call-out the office is allowed to correct, in one form.
 *
 * A job is taken down over the phone from somebody standing on a hard shoulder,
 * so it arrives wrong more often than not — a misheard digit, a road named after
 * the wrong junction, a plate read back from memory. Until now the only editable
 * field on the record was the office's own notes, and correcting anything else
 * meant the database. The fields here are exactly the set
 * `JobStaffUpdateSerializer` accepts; the API remains the authority on each one.
 */
export function JobEditForm({ job, onDone }: { job: JobDetail; onDone: () => void }) {
  const queryClient = useQueryClient();

  const config = useQuery({
    queryKey: ["public-config"],
    queryFn: () => api<PublicConfig>("/public/config"),
    staleTime: 5 * 60_000,
  });

  const save = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api<JobDetail>(`/jobs/${job.id}`, { method: "PATCH", body: JSON.stringify(body) }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["job", job.id] });
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
      void queryClient.invalidateQueries({ queryKey: ["job-map"] });
      onDone();
    },
  });

  // The configured list may not contain a legacy job's own issue type. Keeping it
  // as an option stops opening the form from silently rewriting the record.
  const issueTypes = config.data?.issue_types ?? [];
  const hasOwnIssue = issueTypes.some((issue) => issue.value === job.issue_type);

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        const form = new FormData(event.currentTarget);
        const text = (key: string) => String(form.get(key) ?? "").trim();
        const coordinate = (key: string) => {
          const value = text(key);
          return value === "" ? null : value;
        };

        save.mutate({
          contact_name: text("contact_name"),
          contact_phone: text("contact_phone"),
          contact_email: text("contact_email"),
          issue_type: text("issue_type"),
          description: text("description"),
          tyre_size: text("tyre_size"),
          location_text: text("location_text"),
          latitude: coordinate("latitude"),
          longitude: coordinate("longitude"),
        });
      }}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Customer" error={fieldError(save.error, "contact_name")}>
          <Input name="contact_name" defaultValue={job.contact_name} required />
        </Field>
        <Field label="Phone" error={fieldError(save.error, "contact_phone")}>
          <Input name="contact_phone" defaultValue={job.contact_phone} required />
        </Field>
        <Field label="Email" error={fieldError(save.error, "contact_email")}>
          <Input name="contact_email" type="email" defaultValue={job.contact_email} />
        </Field>
        <Field label="Issue" error={fieldError(save.error, "issue_type")}>
          <Select name="issue_type" defaultValue={job.issue_type} required>
            {hasOwnIssue ? null : (
              <option value={job.issue_type}>{job.issue_label || job.issue_type}</option>
            )}
            {issueTypes.map((issue) => (
              <option key={issue.value} value={issue.value}>
                {issue.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          label="Tyre being fitted"
          hint="What the technician loads the van with."
          error={fieldError(save.error, "tyre_size")}
        >
          <Input name="tyre_size" defaultValue={job.tyre_size} className="font-mono" />
        </Field>
        <Field label="Where" error={fieldError(save.error, "location_text")}>
          <Input name="location_text" defaultValue={job.location_text} />
        </Field>
        <Field
          label="Latitude"
          hint="A postcode is not enough — section 4.4."
          error={fieldError(save.error, "latitude")}
        >
          <Input name="latitude" defaultValue={job.latitude ?? ""} className="font-mono" />
        </Field>
        <Field label="Longitude" error={fieldError(save.error, "longitude")}>
          <Input name="longitude" defaultValue={job.longitude ?? ""} className="font-mono" />
        </Field>
      </div>

      <Field label="Notes from the customer" error={fieldError(save.error, "description")}>
        <Textarea name="description" rows={3} defaultValue={job.description} />
      </Field>

      {save.isError ? <ErrorNote>{save.error.message}</ErrorNote> : null}

      <div className="flex gap-2">
        <Button type="submit" size="sm" disabled={save.isPending}>
          {save.isPending ? "Saving…" : "Save changes"}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </form>
  );
}

/**
 * The lifecycle override (section 5), kept deliberately apart from the ordinary
 * next-step buttons.
 *
 * Those buttons are the job moving the way it is supposed to. This is staff
 * overruling that, and the two must never sit in the same row of controls where
 * one can be hit for the other. It stays folded away, it names what it is, and
 * it will not submit without a reason — which is also what the API demands.
 */
export function StatusOverride({ job }: { job: JobDetail }) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState("");
  const [reason, setReason] = useState("");

  const force = useMutation({
    mutationFn: () =>
      api<JobDetail>(`/jobs/${job.id}/status`, {
        method: "POST",
        body: JSON.stringify({ status, note: reason, force: true }),
      }),
    onSuccess: () => {
      setOpen(false);
      setStatus("");
      setReason("");
      void queryClient.invalidateQueries({ queryKey: ["job", job.id] });
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
      void queryClient.invalidateQueries({ queryKey: ["job-stats"] });
    },
  });

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="mt-3 text-xs text-ink-subtle underline-offset-2 hover:text-ink hover:underline"
      >
        Override the status…
      </button>
    );
  }

  const ready = status !== "" && reason.trim() !== "";

  return (
    <div className="mt-3 space-y-2 rounded-md border border-warning/40 bg-warning/5 p-3">
      <p className="text-xs text-warning">
        This moves the job regardless of the normal lifecycle. It is recorded against your name
        as an override.
      </p>
      <Field label="Move to">
        <Select value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="">Choose a status…</option>
          {OVERRIDE_STATUSES.filter((option) => option.value !== job.status).map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
      </Field>
      <Field label="Why" hint="Required — this is the record of what happened.">
        <Input
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Finished on paper, driver's phone died"
        />
      </Field>
      {force.isError ? <ErrorNote>{force.error.message}</ErrorNote> : null}
      <div className="flex gap-2">
        <Button
          size="sm"
          variant="danger"
          onClick={() => force.mutate()}
          disabled={!ready || force.isPending}
        >
          {force.isPending ? "Moving…" : "Override"}
        </Button>
        <Button size="sm" variant="ghost" onClick={() => setOpen(false)}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

/** Every status the API will accept, including the ones no transition leads to. */
const OVERRIDE_STATUSES = [
  { value: "submitted", label: "Just in" },
  { value: "dispatching", label: "Finding a driver" },
  { value: "assigned", label: "Assigned" },
  { value: "accepted", label: "Accepted" },
  { value: "en_route", label: "On the way" },
  { value: "arrived", label: "Arrived" },
  { value: "in_progress", label: "Being worked on" },
  { value: "completed", label: "Completed" },
  { value: "cancelled", label: "Cancelled" },
  { value: "unclaimed", label: "Unclaimed" },
];
