"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";

import { Button, ErrorNote, Field, Input, Textarea } from "@/components/ui";
import { api, fieldError } from "@/lib/client-api";
import type { Invoice } from "@/types/api";

/**
 * Raise an invoice for something that is not a call-out.
 *
 * A job's invoice is created with the job (section 7.1 step 2) and needs no form.
 * This is the rest: a fleet account settled monthly, a counter sale, a re-issue
 * after a dispute — all of which an invoice welded to a job could not express.
 */
export function NewInvoiceForm({ onCreated }: { onCreated: (invoice: Invoice) => void }) {
  const queryClient = useQueryClient();

  const create = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api<Invoice>("/invoices", { method: "POST", body: JSON.stringify(body) }),
    onSuccess: (invoice) => {
      void queryClient.invalidateQueries({ queryKey: ["invoices"] });
      onCreated(invoice);
    },
  });

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        const form = new FormData(event.currentTarget);
        const text = (key: string) => String(form.get(key) ?? "").trim();
        create.mutate({
          bill_to_name: text("bill_to_name"),
          bill_to_email: text("bill_to_email"),
          bill_to_phone: text("bill_to_phone"),
          ...(text("due_date") ? { due_date: text("due_date") } : {}),
          notes: text("notes"),
        });
      }}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Bill to"
          hint="A person or a company."
          error={fieldError(create.error, "bill_to_name")}
        >
          <Input name="bill_to_name" required autoComplete="off" />
        </Field>
        <Field
          label="Email"
          hint="Where the payment link goes if there is no mobile."
          error={fieldError(create.error, "bill_to_email")}
        >
          <Input name="bill_to_email" type="email" autoComplete="off" />
        </Field>
        <Field
          label="Mobile"
          hint="Preferred — the link is texted."
          error={fieldError(create.error, "bill_to_phone")}
        >
          <Input name="bill_to_phone" autoComplete="off" />
        </Field>
        <Field label="Due date" error={fieldError(create.error, "due_date")}>
          <Input name="due_date" type="date" />
        </Field>
      </div>

      <Field label="Notes" hint="Internal. The customer never sees this.">
        <Textarea name="notes" rows={2} />
      </Field>

      {create.isError ? <ErrorNote>{create.error.message}</ErrorNote> : null}

      <Button type="submit" size="sm" disabled={create.isPending}>
        {create.isPending ? "Creating…" : "Create the invoice"}
      </Button>
      <p className="text-xs text-ink-subtle">
        It opens as a draft with no lines. Add what is being charged for, then send the payment link.
      </p>
    </form>
  );
}
