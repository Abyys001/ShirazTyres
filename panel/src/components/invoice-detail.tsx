"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, ErrorNote, Field, Input, Select } from "@/components/ui";
import { api, fieldError } from "@/lib/client-api";
import { money } from "@/lib/format";
import type { Invoice, ServiceItem } from "@/types/api";

/**
 * One invoice, opened in place on the list.
 *
 * Everything the office does to an invoice happens here rather than on a page of
 * its own: the work is nearly always "look at this one, add the missing line,
 * send it", and a navigation in the middle of that loses the list position they
 * were working down.
 */
export function InvoiceDetail({ invoice }: { invoice: Invoice }) {
  const queryClient = useQueryClient();
  const [adding, setAdding] = useState(false);

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ["invoices"] });
    void queryClient.invalidateQueries({ queryKey: ["job"] });
  };

  const items = useQuery({
    queryKey: ["service-items"],
    queryFn: () => api<{ results: ServiceItem[] }>("/service-items?is_active=true"),
    staleTime: 5 * 60_000,
    enabled: adding,
  });

  const addLine = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api<Invoice>(`/invoices/${invoice.id}/lines`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    onSuccess: () => {
      setAdding(false);
      refresh();
    },
  });

  const removeLine = useMutation({
    mutationFn: (lineId: number) =>
      api<Invoice>(`/invoices/${invoice.id}/lines/${lineId}`, { method: "DELETE" }),
    onSuccess: refresh,
  });

  const sendLink = useMutation({
    mutationFn: () =>
      api<Invoice>(`/invoices/${invoice.id}/send-payment-link`, { method: "POST", body: "{}" }),
    onSuccess: refresh,
  });

  const voidInvoice = useMutation({
    mutationFn: (reason: string) =>
      api<Invoice>(`/invoices/${invoice.id}/void`, {
        method: "POST",
        body: JSON.stringify({ reason }),
      }),
    onSuccess: refresh,
  });

  const refund = useMutation({
    mutationFn: () =>
      api<Invoice>(`/invoices/${invoice.id}/refund`, { method: "POST", body: "{}" }),
    onSuccess: refresh,
  });

  return (
    <div className="grid gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
      <div>
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-line text-left text-xs text-ink-subtle">
              <th className="py-1.5 pr-3 font-medium">Description</th>
              <th className="py-1.5 pr-3 text-right font-medium">Qty</th>
              <th className="py-1.5 pr-3 text-right font-medium">Unit</th>
              <th className="py-1.5 pr-3 text-right font-medium">Line</th>
              <th className="py-1.5 font-medium" />
            </tr>
          </thead>
          <tbody>
            {invoice.lines.map((line) => (
              <tr key={line.id} className="border-b border-line last:border-0">
                <td className="py-1.5 pr-3 text-ink">
                  {line.description}
                  {line.is_system ? (
                    <span className="ml-1.5 text-xs text-ink-subtle">(set by the office)</span>
                  ) : null}
                </td>
                <td className="py-1.5 pr-3 text-right font-mono tabular-nums text-ink-muted">
                  {line.quantity}
                </td>
                <td className="py-1.5 pr-3 text-right font-mono tabular-nums text-ink-muted">
                  {money(line.unit_price, invoice.currency)}
                </td>
                <td className="py-1.5 pr-3 text-right font-mono tabular-nums text-ink">
                  {money(line.line_total, invoice.currency)}
                </td>
                <td className="py-1.5 text-right">
                  {invoice.is_editable && !line.is_system ? (
                    <button
                      onClick={() => removeLine.mutate(line.id)}
                      className="text-xs text-ink-subtle hover:text-danger"
                    >
                      Remove
                    </button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr>
              <td colSpan={3} className="py-1.5 pr-3 text-right text-ink-muted">
                Net
              </td>
              <td className="py-1.5 pr-3 text-right font-mono tabular-nums text-ink-muted">
                {money(invoice.subtotal, invoice.currency)}
              </td>
              <td />
            </tr>
            <tr>
              <td colSpan={3} className="py-1.5 pr-3 text-right text-ink-muted">
                VAT at {invoice.vat_rate}%
              </td>
              <td className="py-1.5 pr-3 text-right font-mono tabular-nums text-ink-muted">
                {money(invoice.vat_amount, invoice.currency)}
              </td>
              <td />
            </tr>
            <tr className="border-t border-line-strong">
              <td colSpan={3} className="py-2 pr-3 text-right font-medium text-ink">
                Total
              </td>
              <td className="py-2 pr-3 text-right font-mono font-bold tabular-nums text-ink">
                {money(invoice.total, invoice.currency)}
              </td>
              <td />
            </tr>
          </tfoot>
        </table>

        {invoice.is_editable ? (
          <div className="mt-3">
            {adding ? (
              <form
                className="space-y-3 rounded-md border border-line bg-surface p-3"
                onSubmit={(event) => {
                  event.preventDefault();
                  const form = new FormData(event.currentTarget);
                  const itemId = String(form.get("service_item_id") ?? "");
                  addLine.mutate({
                    ...(itemId ? { service_item_id: Number(itemId) } : {}),
                    description: String(form.get("description") ?? "").trim(),
                    quantity: String(form.get("quantity") ?? "1"),
                    ...(String(form.get("unit_price") ?? "").trim()
                      ? { unit_price: String(form.get("unit_price")) }
                      : {}),
                    kind: String(form.get("kind") ?? "part"),
                  });
                }}
              >
                <div className="grid gap-3 sm:grid-cols-2">
                  <Field label="From the price list" hint="Or leave blank and type it in below.">
                    <Select name="service_item_id" defaultValue="">
                      <option value="">Not from the list</option>
                      {(items.data?.results ?? []).map((item) => (
                        <option key={item.id} value={item.id}>
                          {item.name} — {money(item.unit_price, invoice.currency)}
                        </option>
                      ))}
                    </Select>
                  </Field>
                  <Field label="Description" error={fieldError(addLine.error, "description")}>
                    <Input name="description" />
                  </Field>
                  <Field label="Quantity">
                    <Input name="quantity" defaultValue="1" inputMode="decimal" />
                  </Field>
                  <Field label="Unit price" error={fieldError(addLine.error, "unit_price")}>
                    <Input name="unit_price" inputMode="decimal" placeholder="0.00" />
                  </Field>
                  <Field label="Kind">
                    <Select name="kind" defaultValue="part">
                      <option value="part">Part</option>
                      <option value="labour">Labour</option>
                      <option value="callout">Call-out</option>
                      <option value="other">Other</option>
                    </Select>
                  </Field>
                </div>
                {addLine.isError ? <ErrorNote>{addLine.error.message}</ErrorNote> : null}
                <div className="flex gap-2">
                  <Button type="submit" size="sm" disabled={addLine.isPending}>
                    {addLine.isPending ? "Adding…" : "Add line"}
                  </Button>
                  <Button type="button" size="sm" variant="ghost" onClick={() => setAdding(false)}>
                    Cancel
                  </Button>
                </div>
              </form>
            ) : (
              <Button size="sm" variant="secondary" onClick={() => setAdding(true)}>
                Add a line
              </Button>
            )}
          </div>
        ) : (
          <p className="mt-3 text-xs text-ink-subtle">
            This invoice has been issued, so its lines are fixed. Void it to start again.
          </p>
        )}
      </div>

      <div className="space-y-3">
        <dl className="space-y-2 text-sm">
          <Row label="Billed to">{invoice.bill_to || "nobody named"}</Row>
          {invoice.bill_to_email ? <Row label="Email">{invoice.bill_to_email}</Row> : null}
          {invoice.bill_to_phone ? <Row label="Phone">{invoice.bill_to_phone}</Row> : null}
          {invoice.stripe_mode ? (
            <Row label="Stripe">
              <span className={invoice.stripe_mode === "live" ? "text-ink" : "text-warning"}>
                {invoice.stripe_status || "raised"} ({invoice.stripe_mode})
              </span>
            </Row>
          ) : null}
        </dl>

        {invoice.hosted_invoice_url ? (
          <a
            href={invoice.hosted_invoice_url}
            target="_blank"
            rel="noreferrer"
            className="block truncate rounded-md border border-line bg-surface px-3 py-2 text-xs text-brand hover:underline"
          >
            {invoice.hosted_invoice_url}
          </a>
        ) : null}

        {sendLink.isError ? <ErrorNote>{sendLink.error.message}</ErrorNote> : null}
        {voidInvoice.isError ? <ErrorNote>{voidInvoice.error.message}</ErrorNote> : null}
        {refund.isError ? <ErrorNote>{refund.error.message}</ErrorNote> : null}

        <div className="flex flex-wrap gap-2">
          {invoice.status !== "paid" && invoice.status !== "void" ? (
            <Button
              size="sm"
              onClick={() => sendLink.mutate()}
              disabled={sendLink.isPending || invoice.total === "0.00"}
            >
              {sendLink.isPending
                ? "Raising…"
                : invoice.hosted_invoice_url
                  ? "Resend the link"
                  : "Send a payment link"}
            </Button>
          ) : null}

          {invoice.status === "paid" && invoice.stripe_invoice_id ? (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => refund.mutate()}
              disabled={refund.isPending}
            >
              {refund.isPending ? "Refunding…" : "Refund in full"}
            </Button>
          ) : null}

          {invoice.status !== "void" ? (
            <VoidButton onVoid={(reason) => voidInvoice.mutate(reason)} busy={voidInvoice.isPending} />
          ) : null}
        </div>
      </div>
    </div>
  );
}

/** Voiding is irreversible, so it asks for a reason before it will do anything. */
function VoidButton({ onVoid, busy }: { onVoid: (reason: string) => void; busy: boolean }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");

  if (!open) {
    return (
      <Button size="sm" variant="ghost" className="text-danger" onClick={() => setOpen(true)}>
        Void
      </Button>
    );
  }

  return (
    <div className="w-full space-y-2 rounded-md border border-danger/40 bg-danger/5 p-3">
      <Field label="Why is this being voided?">
        <Input value={reason} onChange={(event) => setReason(event.target.value)} />
      </Field>
      <div className="flex gap-2">
        <Button
          size="sm"
          variant="danger"
          onClick={() => onVoid(reason)}
          disabled={!reason.trim() || busy}
        >
          {busy ? "Voiding…" : "Void it"}
        </Button>
        <Button size="sm" variant="ghost" onClick={() => setOpen(false)}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[5.5rem_minmax(0,1fr)] gap-2">
      <dt className="text-ink-subtle">{label}</dt>
      <dd className="min-w-0 break-words text-ink">{children}</dd>
    </div>
  );
}
