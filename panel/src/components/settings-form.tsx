"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button, ErrorNote, Input, Select, Textarea } from "@/components/ui";
import { api } from "@/lib/client-api";
import type { SettingSpec, SettingsDocument } from "@/types/api";

/**
 * Renders one group of the configuration catalogue (specification 12) from the specs the
 * API ships alongside the values, so a new setting on the server appears here without a
 * front-end change.
 */
export function SettingsForm({ specs, values }: { specs: SettingSpec[]; values: Record<string, unknown> }) {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [invalid, setInvalid] = useState<string[]>([]);

  const save = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      api<SettingsDocument>("/settings", { method: "PATCH", body: JSON.stringify({ values: payload }) }),
    onSuccess: () => {
      setDraft({});
      void queryClient.invalidateQueries({ queryKey: ["settings"] });
    },
  });

  const dirty = Object.keys(draft).length > 0;

  function update(key: string, value: unknown) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    const bad: string[] = [];
    const payload: Record<string, unknown> = {};

    for (const [key, value] of Object.entries(draft)) {
      const spec = specs.find((candidate) => candidate.key === key);
      if (spec?.type === "json" && typeof value === "string") {
        try {
          payload[key] = JSON.parse(value);
        } catch {
          bad.push(key);
        }
      } else {
        payload[key] = value;
      }
    }

    setInvalid(bad);
    if (bad.length === 0) save.mutate(payload);
  }

  return (
    <form className="space-y-5" onSubmit={submit}>
      {specs.map((spec) => {
        const current = spec.key in draft ? draft[spec.key] : values[spec.key];
        return (
          <div key={spec.key} className="grid gap-2 border-b border-line pb-4 last:border-0 sm:grid-cols-3">
            <div className="sm:col-span-1">
              <p className="text-sm font-medium">{spec.label}</p>
              {spec.help_text ? <p className="text-xs text-ink-muted">{spec.help_text}</p> : null}
              <p className="mt-1 font-mono text-[10px] text-ink-subtle">{spec.key}</p>
            </div>
            <div className="sm:col-span-2">
              <SettingInput spec={spec} value={current} onChange={(value) => update(spec.key, value)} />
              {invalid.includes(spec.key) ? (
                <p className="mt-1 text-xs text-brand">That is not valid JSON.</p>
              ) : null}
            </div>
          </div>
        );
      })}

      {save.isError ? <ErrorNote>{save.error.message}</ErrorNote> : null}
      {save.isSuccess && !dirty ? <p className="text-sm text-success">Saved.</p> : null}

      <Button type="submit" disabled={!dirty || save.isPending}>
        {save.isPending ? "Saving…" : "Save changes"}
      </Button>
    </form>
  );
}

function SettingInput({
  spec,
  value,
  onChange,
}: {
  spec: SettingSpec;
  value: unknown;
  onChange: (value: unknown) => void;
}) {
  if (spec.type === "bool") {
    return (
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={Boolean(value)} onChange={(event) => onChange(event.target.checked)} />
        {value ? "On" : "Off"}
      </label>
    );
  }

  if (spec.type === "choice") {
    return (
      <Select value={String(value ?? "")} onChange={(event) => onChange(event.target.value)}>
        {spec.choices.map((choice) => (
          <option key={choice.value} value={choice.value}>
            {choice.label}
          </option>
        ))}
      </Select>
    );
  }

  if (spec.type === "json") {
    const text = typeof value === "string" ? value : JSON.stringify(value, null, 2);
    return <Textarea rows={6} className="font-mono text-xs" value={text} onChange={(event) => onChange(event.target.value)} />;
  }

  if (spec.type === "text") {
    return <Textarea rows={3} value={String(value ?? "")} onChange={(event) => onChange(event.target.value)} />;
  }

  return (
    <Input
      value={String(value ?? "")}
      inputMode={spec.type === "int" || spec.type === "decimal" ? "decimal" : undefined}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}
