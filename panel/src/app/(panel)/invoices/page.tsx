"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { Fragment, useState } from "react";

import { InvoiceDetail } from "@/components/invoice-detail";
import { NewInvoiceForm } from "@/components/new-invoice-form";
import {
  Button,
  Card,
  EmptyState,
  ErrorNote,
  Input,
  InvoiceBadge,
  Pill,
  Select,
  Stat,
  StatStrip,
} from "@/components/ui";
import { api } from "@/lib/client-api";
import { formatDateTime, money, timeAgo } from "@/lib/format";
import { useLiveStatus } from "@/lib/ws";
import type { HealthSnapshot, Invoice, Paginated } from "@/types/api";

const FILTERS = [
  { value: "", label: "All invoices" },
  { value: "draft", label: "Draft" },
  { value: "issued", label: "Issued, unpaid" },
  { value: "paid", label: "Paid" },
  { value: "void", label: "Void" },
];

export default function InvoicesPage() {
  const connected = useLiveStatus();
  const queryClient = useQueryClient();

  const [status, setStatus] = useState("");
  const [search, setSearch] = useState("");
  const [creating, setCreating] = useState(false);
  const [openId, setOpenId] = useState<number | null>(null);

  const query = new URLSearchParams();
  if (status) query.set("status", status);
  if (search.trim()) query.set("search", search.trim());

  const invoices = useQuery({
    queryKey: ["invoices", status, search],
    queryFn: () => api<Paginated<Invoice>>(`/invoices?${query.toString()}`),
    refetchInterval: connected ? 60_000 : 20_000,
  });

  // Which Stripe mode is live decides whether a "paid" row is money or a rehearsal.
  const health = useQuery({
    queryKey: ["health"],
    queryFn: () => api<HealthSnapshot>("/health"),
    staleTime: 60_000,
  });

  const markPaid = useMutation({
    mutationFn: (id: number) =>
      api<Invoice>(`/invoices/${id}/mark-paid`, { method: "POST", body: "{}" }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["invoices"] }),
  });

  const rows = invoices.data?.results ?? [];
  const stripeMode = health.data?.providers?.stripe?.mode ?? "";

  const outstanding = rows
    .filter((invoice) => invoice.status === "issued")
    .reduce((sum, invoice) => sum + Number(invoice.total), 0);
  const paid = rows
    .filter((invoice) => invoice.status === "paid")
    .reduce((sum, invoice) => sum + Number(invoice.total), 0);

  return (
    <div className="space-y-5">
      {/*
       * A test-mode invoice that reads as income is the one Stripe mistake that
       * actually costs something, so the mode is stated above the money rather
       * than buried in settings.
       */}
      {stripeMode && stripeMode !== "live" ? (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border border-warning/40 bg-warning/5 px-4 py-2.5 text-sm text-warning">
          <strong>Stripe is in {stripeMode} mode.</strong>
          <span className="text-ink-muted">
            {stripeMode === "mock"
              ? "Payment links are generated locally and collect nothing."
              : "Payments use the Stripe sandbox — no money moves."}
          </span>
        </div>
      ) : null}

      <StatStrip>
        <Stat label="Invoices shown" value={rows.length} />
        <Stat label="Awaiting payment" value={rows.filter((i) => i.status === "issued").length} tone="alert" />
        <Stat label="Drafts" value={rows.filter((i) => i.status === "draft").length} />
        <Stat label="Paid" value={rows.filter((i) => i.status === "paid").length} tone="good" />
        <Stat label="Void" value={rows.filter((i) => i.status === "void").length} />
      </StatStrip>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <p className="count-label">Outstanding on screen</p>
          <p className="count mt-1 text-danger">{money(String(outstanding), "GBP")}</p>
        </Card>
        <Card>
          <p className="count-label">Collected on screen</p>
          <p className="count mt-1 text-success">{money(String(paid), "GBP")}</p>
        </Card>
      </div>

      <Card
        title="Invoices"
        action={
          <div className="flex flex-wrap items-center gap-2 sm:flex-nowrap">
            <Input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Reference, job, name…"
              className="w-52"
            />
            <Select
              value={status}
              onChange={(event) => setStatus(event.target.value)}
              className="w-44"
            >
              {FILTERS.map((filter) => (
                <option key={filter.value} value={filter.value}>
                  {filter.label}
                </option>
              ))}
            </Select>
            <Button
              variant={creating ? "secondary" : "primary"}
              onClick={() => setCreating((open) => !open)}
            >
              {creating ? "Close" : "New invoice"}
            </Button>
          </div>
        }
      >
        {creating ? (
          <div className="mb-4 rounded-md border border-line bg-surface-raised p-4">
            <NewInvoiceForm
              onCreated={(invoice) => {
                setCreating(false);
                setOpenId(invoice.id);
              }}
            />
          </div>
        ) : null}

        {markPaid.isError ? <ErrorNote>{markPaid.error.message}</ErrorNote> : null}
        {invoices.isLoading ? <EmptyState>Loading…</EmptyState> : null}
        {invoices.data && rows.length === 0 ? (
          <EmptyState>No invoices match this filter.</EmptyState>
        ) : null}

        {rows.length > 0 ? (
          <div className="-mx-4 overflow-x-auto">
            <table className="w-full min-w-[56rem] border-collapse text-sm">
              <thead>
                <tr className="border-b border-line text-left text-xs text-ink-subtle">
                  <th className="py-2 pl-4 pr-3 font-medium">Invoice</th>
                  <th className="py-2 pr-3 font-medium">For</th>
                  <th className="py-2 pr-3 font-medium">Status</th>
                  <th className="py-2 pr-3 text-right font-medium">Net</th>
                  <th className="py-2 pr-3 text-right font-medium">VAT</th>
                  <th className="py-2 pr-3 text-right font-medium">Total</th>
                  <th className="py-2 pr-3 font-medium">Paid by</th>
                  <th className="py-2 pr-4 font-medium" />
                </tr>
              </thead>
              <tbody>
                {rows.map((invoice) => {
                  const open = openId === invoice.id;
                  return (
                    <Fragment key={invoice.id}>
                      <tr
                        onClick={() => setOpenId(open ? null : invoice.id)}
                        className="cursor-pointer border-b border-line align-top last:border-0 hover:bg-surface-raised"
                      >
                        <td className="py-2.5 pl-4 pr-3">
                          <span className="font-mono text-sm font-medium text-brand">
                            {invoice.display_reference}
                          </span>
                          <span className="mt-0.5 block text-xs text-ink-subtle">
                            {timeAgo(invoice.created_at)}
                          </span>
                        </td>
                        <td className="py-2.5 pr-3">
                          <span className="block text-ink">{invoice.bill_to || "—"}</span>
                          {invoice.job ? (
                            <Link
                              href={`/jobs/${invoice.job}`}
                              onClick={(event) => event.stopPropagation()}
                              className="font-mono text-xs text-brand hover:underline"
                            >
                              {invoice.job_reference}
                            </Link>
                          ) : (
                            <span className="text-xs text-ink-subtle">no job</span>
                          )}
                        </td>
                        <td className="py-2.5 pr-3">
                          <InvoiceBadge status={invoice.status} label={invoice.status_display} />
                          {invoice.is_payable_online ? (
                            <Pill className="chip-info ml-1.5">link sent</Pill>
                          ) : null}
                        </td>
                        <td className="py-2.5 pr-3 text-right font-mono tabular-nums text-ink-muted">
                          {money(invoice.subtotal, invoice.currency)}
                        </td>
                        <td className="py-2.5 pr-3 text-right font-mono tabular-nums text-ink-muted">
                          {money(invoice.vat_amount, invoice.currency)}
                        </td>
                        <td className="py-2.5 pr-3 text-right font-mono font-medium tabular-nums text-ink">
                          {money(invoice.total, invoice.currency)}
                        </td>
                        <td className="py-2.5 pr-3 text-xs text-ink-muted">
                          {invoice.status === "paid"
                            ? invoice.payment_method.replace(/_/g, " ")
                            : formatDateTime(invoice.issued_at) || "—"}
                        </td>
                        <td className="py-2.5 pr-4 text-right">
                          {invoice.status !== "paid" && invoice.status !== "void" ? (
                            <Button
                              size="sm"
                              variant="secondary"
                              onClick={(event) => {
                                event.stopPropagation();
                                markPaid.mutate(invoice.id);
                              }}
                              disabled={markPaid.isPending}
                            >
                              Mark paid
                            </Button>
                          ) : null}
                        </td>
                      </tr>
                      {open ? (
                        <tr className="border-b border-line">
                          <td colSpan={8} className="bg-surface-raised p-4">
                            <InvoiceDetail invoice={invoice} />
                          </td>
                        </tr>
                      ) : null}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : null}
      </Card>
    </div>
  );
}
