"use client";

import { Button, Field, Input, Notice } from "@/components/ui";
import type { ConfirmationPath, Vehicle } from "@/types/api";

export interface TyreDecision {
  path: ConfirmationPath | null;
  disclaimerAccepted: boolean;
  tyreSize: string;
  loadIndex: string;
  speedRating: string;
}

export const EMPTY_DECISION: TyreDecision = {
  path: null,
  disclaimerAccepted: false,
  tyreSize: "",
  loadIndex: "",
  speedRating: "",
};

/**
 * The confirmation step (specification 4.3), which the request cannot skip.
 *
 * Path A confirms the looked-up specification. Path B shows the responsibility notice,
 * requires an explicit acknowledgement, and only then opens the fields. Both the
 * looked-up and the customer-supplied values are sent, so a technician who arrives with
 * the wrong tyre can be shown exactly what was displayed and what was entered.
 */
export function TyreConfirmation({
  vehicle,
  decision,
  onChange,
}: {
  vehicle: Vehicle;
  decision: TyreDecision;
  onChange: (decision: TyreDecision) => void;
}) {
  const lookedUp = vehicle.tyre_size_front;

  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-line bg-surface-raised p-4">
        <p className="text-sm text-ink-muted">Your vehicle</p>
        <p className="font-medium">{vehicle.description || vehicle.display_plate}</p>
        <p className="mt-3 text-sm text-ink-muted">Tyre size on record</p>
        <p className="text-2xl font-semibold">{lookedUp || "not available"}</p>
        {vehicle.tyre_load_index || vehicle.tyre_speed_rating ? (
          <p className="text-sm text-ink-muted">
            Load {vehicle.tyre_load_index || "—"} · Speed {vehicle.tyre_speed_rating || "—"}
          </p>
        ) : null}
        {vehicle.is_fitment_ambiguous ? (
          <p className="mt-2 text-xs text-warning">
            More than one size is recorded for this model — please check the sidewall of your tyre.
          </p>
        ) : null}
        {vehicle.lookup_error ? (
          <p className="mt-2 text-xs text-brand">{vehicle.lookup_error}</p>
        ) : null}
      </div>

      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          variant={decision.path === "confirmed" ? "primary" : "secondary"}
          disabled={!lookedUp}
          onClick={() =>
            onChange({ ...EMPTY_DECISION, path: "confirmed", tyreSize: lookedUp })
          }
        >
          That is correct
        </Button>
        <Button
          type="button"
          variant={decision.path === "overridden" ? "primary" : "secondary"}
          onClick={() =>
            onChange({
              ...decision,
              path: "overridden",
              disclaimerAccepted: false,
              tyreSize: decision.tyreSize || "",
            })
          }
        >
          {lookedUp ? "That is not my tyre size" : "Enter my tyre size"}
        </Button>
      </div>

      {decision.path === "overridden" ? (
        <div className="space-y-3">
          <Notice tone="warning">
            <p className="font-medium">Please read before continuing.</p>
            <p className="mt-1">
              If you give us a tyre size yourself, any mismatch — and anything that follows from it, including a
              wasted call-out or a tyre that cannot be fitted — is your responsibility. Our technician will load
              the van based on the size you enter. If you are not sure, the size is printed on the sidewall of
              your existing tyre, for example 205/55R16.
            </p>
          </Notice>

          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              className="mt-1"
              checked={decision.disclaimerAccepted}
              onChange={(event) => onChange({ ...decision, disclaimerAccepted: event.target.checked })}
            />
            I understand and accept responsibility for the tyre specification I enter.
          </label>

          {decision.disclaimerAccepted ? (
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="sm:col-span-3">
                <Field label="Tyre size" hint="As printed on the sidewall, for example 205/55R16">
                  <Input
                    value={decision.tyreSize}
                    onChange={(event) => onChange({ ...decision, tyreSize: event.target.value })}
                    placeholder="205/55R16"
                  />
                </Field>
              </div>
              <Field label="Load index (optional)">
                <Input
                  value={decision.loadIndex}
                  onChange={(event) => onChange({ ...decision, loadIndex: event.target.value })}
                  placeholder="91"
                />
              </Field>
              <Field label="Speed rating (optional)">
                <Input
                  value={decision.speedRating}
                  onChange={(event) => onChange({ ...decision, speedRating: event.target.value })}
                  placeholder="V"
                />
              </Field>
            </div>
          ) : null}
        </div>
      ) : null}

      {decision.path === "confirmed" ? (
        <Notice>Confirmed: {decision.tyreSize}. We will load {decision.tyreSize} for you.</Notice>
      ) : null}
    </div>
  );
}
