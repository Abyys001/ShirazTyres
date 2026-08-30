"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { Button, Card, EmptyState, InvoiceBadge, Select } from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime, money } from "@/lib/format";
import type { Invoice, Paginated } from "@/types/api";

const FILTERS = [
  { value: "", label: "All invoices" },
  { value: "draft", label: "Draft" },
  { value: "issued", label: "Issued, unpaid" },
  { value: "paid", label: "Paid" },
  { value: "void", label: "Void" },
];

export default function InvoicesPage() {
  const [status, setStatus] = useState("");
  const queryClient = useQueryClient();

  const invoices = useQuery({
    queryKey: ["invoices", status],
    queryFn: () => api<Paginated<Invoice>>(`/invoices${status ? `?status=${status}` : ""}`),
    refetchInterval: 60_000,
  });

  const markPaid = useMutation({
    mutationFn: (id: number) => api<Invoice>(`/invoices/${id}/mark-paid`, { method: "POST", body: "{}" }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["invoices"] }),
  });

  return (
    <Card
      title="Invoices"
      action={
        <Select value={status} onChange={(event) => setStatus(event.target.value)} className="w-44">
          {FILTERS.map((filter) => (
            <option key={filter.value} value={filter.value}>
              {filter.label}
            </option>
          ))}
        </Select>
      }
    >
      {invoices.isLoading ? <EmptyState>Loading…</EmptyState> : null}
      {invoices.data && invoices.data.results.length === 0 ? (
        <EmptyState>No invoices match this filter.</EmptyState>
      ) : null}

      {invoices.data && invoices.data.results.length > 0 ? (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
              <tr className="border-b border-line">
                <th className="py-2 pr-3">Job</th>
                <th className="py-2 pr-3">Status</th>
                <th className="py-2 pr-3">Subtotal</th>
                <th className="py-2 pr-3">VAT</th>
                <th className="py-2 pr-3">Total</th>
                <th className="py-2 pr-3">Paid by</th>
                <th className="py-2 pr-3">Issued</th>
                <th className="py-2 pr-3" />
              </tr>
            </thead>
            <tbody>
              {invoices.data.results.map((invoice) => (
                <tr key={invoice.id} className="border-b border-line last:border-0 hover:bg-surface-raised">
                  <td className="py-2 pr-3 font-medium">
                    <Link href={`/jobs/${invoice.job}`} className="text-brand hover:underline">
                      {invoice.job_reference}
                    </Link>
                  </td>
                  <td className="py-2 pr-3">
                    <InvoiceBadge status={invoice.status} label={invoice.status_display} />
                  </td>
                  <td className="py-2 pr-3">{money(invoice.subtotal, invoice.currency)}</td>
                  <td className="py-2 pr-3">{money(invoice.vat_amount, invoice.currency)}</td>
                  <td className="py-2 pr-3 font-medium">{money(invoice.total, invoice.currency)}</td>
                  <td className="py-2 pr-3 text-xs">{invoice.payment_method.replace("_", " ")}</td>
                  <td className="py-2 pr-3 text-xs text-ink-muted">{formatDateTime(invoice.issued_at)}</td>
                  <td className="py-2 pr-3">
                    {invoice.status !== "paid" && invoice.status !== "void" ? (
                      <Button size="sm" variant="secondary" onClick={() => markPaid.mutate(invoice.id)}>
                        Mark paid
                      </Button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </Card>
  );
}
