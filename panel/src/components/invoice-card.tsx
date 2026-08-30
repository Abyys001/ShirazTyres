"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, Card, ErrorNote, Field, Input, InvoiceBadge, Select } from "@/components/ui";
import { api } from "@/lib/client-api";
import { money } from "@/lib/format";
import type { Invoice, JobDetail } from "@/types/api";

const PAYMENT_METHODS = [
  { value: "card_reader", label: "Card reader in the van" },
  { value: "payment_link", label: "Payment link by SMS" },
  { value: "cash", label: "Cash" },
  { value: "other", label: "Other" },
];

/**
 * The office view of one job's invoice (specification 7).
 *
 * The call-out fee line is added by the system and cannot be removed here — it is the
 * owner's pricing decision, changed in Settings, not on a job.
 */
export function InvoiceCard({ job }: { job: JobDetail }) {
  const queryClient = useQueryClient();
  const [adding, setAdding] = useState(false);
  const invoice = job.invoice;

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["job", job.id] });

  const addLine = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      api<Invoice>(`/jobs/${job.id}/invoice`, { method: "POST", body: JSON.stringify(payload) }),
    onSuccess: () => {
      setAdding(false);
      void refresh();
    },
  });

  const markPaid = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      api<Invoice>(`/invoices/${invoice?.id}/mark-paid`, {
        method: "POST",
        body: JSON.stringify(payload),
      }),
    onSuccess: refresh,
  });

  if (!invoice) return null;

  return (
    <Card
      title="Invoice"
      action={
        <div className="flex items-center gap-2">
          <InvoiceBadge status={invoice.status} label={invoice.status_display} />
          {invoice.is_editable ? (
            <Button size="sm" variant="secondary" onClick={() => setAdding((open) => !open)}>
              {adding ? "Cancel" : "Add line"}
            </Button>
          ) : null}
        </div>
      }
    >
      <table className="w-full text-sm">
        <tbody>
          {invoice.lines.map((line) => (
            <tr key={line.id} className="border-b border-line last:border-0">
              <td className="py-1.5">
                {line.description}
                {line.is_system ? <span className="ml-2 text-xs text-ink-subtle">set in Settings</span> : null}
              </td>
              <td className="py-1.5 text-right text-xs text-ink-muted">
                {line.quantity} × {money(line.unit_price, invoice.currency)}
              </td>
              <td className="py-1.5 pl-3 text-right">{money(line.line_total, invoice.currency)}</td>
            </tr>
          ))}
        </tbody>
        <tfoot className="text-sm">
          <tr>
            <td colSpan={2} className="pt-2 text-right text-ink-muted">
              Subtotal
            </td>
            <td className="pt-2 pl-3 text-right">{money(invoice.subtotal, invoice.currency)}</td>
          </tr>
          <tr>
            <td colSpan={2} className="text-right text-ink-muted">
              VAT at {invoice.vat_rate}%
            </td>
            <td className="pl-3 text-right">{money(invoice.vat_amount, invoice.currency)}</td>
          </tr>
          <tr className="font-semibold">
            <td colSpan={2} className="pt-1 text-right">
              Total
            </td>
            <td className="pt-1 pl-3 text-right">{money(invoice.total, invoice.currency)}</td>
          </tr>
        </tfoot>
      </table>

      {adding ? (
        <form
          className="mt-4 grid gap-2 rounded-md border border-line bg-surface-raised p-3 sm:grid-cols-4"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            addLine.mutate({
              description: form.get("description"),
              unit_price: form.get("unit_price"),
              quantity: form.get("quantity") || "1",
              kind: form.get("kind"),
            });
          }}
        >
          <div className="sm:col-span-2">
            <Field label="Description">
              <Input name="description" required />
            </Field>
          </div>
          <Field label="Unit price">
            <Input name="unit_price" required inputMode="decimal" />
          </Field>
          <Field label="Quantity">
            <Input name="quantity" defaultValue="1" inputMode="decimal" />
          </Field>
          <Field label="Kind">
            <Select name="kind" defaultValue="part">
              <option value="part">Part</option>
              <option value="labour">Labour</option>
              <option value="other">Other</option>
            </Select>
          </Field>
          <div className="flex items-end sm:col-span-4">
            <Button type="submit" size="sm" disabled={addLine.isPending}>
              Add
            </Button>
          </div>
        </form>
      ) : null}

      {invoice.status !== "paid" && invoice.status !== "void" ? (
        <form
          className="mt-4 flex flex-wrap items-end gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            markPaid.mutate({
              payment_method: form.get("payment_method"),
              payment_reference: form.get("payment_reference") || "",
            });
          }}
        >
          <div className="w-56">
            <Field label="Payment taken by">
              <Select name="payment_method" defaultValue="card_reader">
                {PAYMENT_METHODS.map((method) => (
                  <option key={method.value} value={method.value}>
                    {method.label}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <div className="w-48">
            <Field label="Reference">
              <Input name="payment_reference" />
            </Field>
          </div>
          <Button type="submit" size="sm" variant="secondary" disabled={markPaid.isPending}>
            Mark paid
          </Button>
        </form>
      ) : null}

      {addLine.isError ? <ErrorNote>{addLine.error.message}</ErrorNote> : null}
      {markPaid.isError ? <ErrorNote>{markPaid.error.message}</ErrorNote> : null}
    </Card>
  );
}
