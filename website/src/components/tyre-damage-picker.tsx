"use client";

import type { DamagedTyre, TyrePosition, TyreSeverity } from "@/types/api";

const POSITIONS: { value: TyrePosition; label: string }[] = [
  { value: "front_left", label: "Nearside front" },
  { value: "front_right", label: "Offside front" },
  { value: "rear_left", label: "Nearside rear" },
  { value: "rear_right", label: "Offside rear" },
  { value: "spare", label: "Spare" },
];

const SEVERITIES: { value: TyreSeverity; label: string }[] = [
  { value: "flat", label: "Completely flat" },
  { value: "deflating", label: "Losing air" },
  { value: "damaged", label: "Damaged but holding" },
  { value: "blowout", label: "Blowout" },
];

/** Where each corner sits on the plan view, as a fraction of the box. */
const CORNERS: Partial<Record<TyrePosition, { x: number; y: number }>> = {
  front_left: { x: 0.175, y: 0.265 },
  front_right: { x: 0.825, y: 0.265 },
  rear_left: { x: 0.175, y: 0.735 },
  rear_right: { x: 0.825, y: 0.735 },
};

/**
 * Which wheels are damaged (specification 4.5).
 *
 * The app and the panel have had this since the field existed; the website was
 * sending the job without it, so a call-out raised from a laptop reached the
 * technician saying only "puncture" and they arrived not knowing which corner to
 * jack up. The car is drawn from above and tapped, because "nearside" and
 * "offside" are not words most drivers are sure of under stress.
 */
export function TyreDamagePicker({
  value,
  onChange,
}: {
  value: DamagedTyre[];
  onChange: (next: DamagedTyre[]) => void;
}) {
  const marked = new Map(value.map((tyre) => [tyre.position, tyre]));

  function toggle(position: TyrePosition) {
    onChange(
      marked.has(position)
        ? value.filter((tyre) => tyre.position !== position)
        : [...value, { position, severity: "" as const, note: "" }],
    );
  }

  function setSeverity(position: TyrePosition, severity: TyreSeverity | "") {
    onChange(value.map((tyre) => (tyre.position === position ? { ...tyre, severity } : tyre)));
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start gap-6">
        <svg
          viewBox="0 -5 100 133"
          className="h-44 w-auto shrink-0"
          role="group"
          aria-label="Plan view of your car — tap a damaged wheel"
        >
          <rect
            x="26" y="6" width="48" height="116" rx="16"
            className="fill-surface-raised stroke-line-strong"
            strokeWidth="1.5"
          />
          <rect x="31" y="17" width="38" height="18" rx="5" className="fill-surface-sunken" />
          <rect x="31" y="92" width="38" height="17" rx="4.5" className="fill-surface-sunken" />
          <line x1="50" y1="38" x2="50" y2="88" className="stroke-line" strokeWidth="1" />

          {POSITIONS.filter((entry) => entry.value in CORNERS).map((entry) => {
            const point = CORNERS[entry.value]!;
            const hit = marked.has(entry.value);
            return (
              <g
                key={entry.value}
                role="checkbox"
                aria-checked={hit}
                aria-label={entry.label}
                tabIndex={0}
                className="cursor-pointer outline-none"
                onClick={() => toggle(entry.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    toggle(entry.value);
                  }
                }}
              >
                {/* A wheel is a small target; this is the one the finger hits. */}
                <circle
                  cx={point.x * 100}
                  cy={point.y * 128}
                  r="13"
                  className="fill-transparent"
                />
                <rect
                  x={point.x * 100 - 6.5}
                  y={point.y * 128 - 9}
                  width="13" height="18" rx="3"
                  className="fill-line-strong"
                />
                {hit ? (
                  <circle
                    cx={point.x * 100}
                    cy={point.y * 128}
                    r="10"
                    className="fill-danger/25 stroke-danger"
                    strokeWidth="2.5"
                  />
                ) : null}
              </g>
            );
          })}

          <text x="17" y="64" className="fill-ink-subtle text-[6px] font-semibold"
                transform="rotate(-90 17 64)" textAnchor="middle">
            NEARSIDE
          </text>
          <text x="83" y="64" className="fill-ink-subtle text-[6px] font-semibold"
                transform="rotate(90 83 64)" textAnchor="middle">
            OFFSIDE
          </text>
          <text x="50" y="4" className="fill-ink-subtle text-[6px] font-semibold" textAnchor="middle">
            FRONT
          </text>
        </svg>

        <div className="min-w-[14rem] flex-1 space-y-2">
          {POSITIONS.map((entry) => {
            const hit = marked.has(entry.value);
            return (
              <button
                key={entry.value}
                type="button"
                onClick={() => toggle(entry.value)}
                aria-pressed={hit}
                className={`block w-full rounded-lg border px-3 py-2 text-left text-sm transition ${
                  hit
                    ? "border-danger bg-danger/10 text-ink"
                    : "border-line bg-surface-raised text-ink-muted hover:border-line-strong"
                }`}
              >
                {entry.label}
              </button>
            );
          })}
        </div>
      </div>

      {value.length > 0 ? (
        <div className="space-y-2">
          {value.map((tyre) => (
            <div key={tyre.position} className="flex flex-wrap items-center gap-2 text-sm">
              <span className="min-w-[8.5rem] text-ink">
                {POSITIONS.find((entry) => entry.value === tyre.position)?.label ?? tyre.position}
              </span>
              <select
                value={tyre.severity || ""}
                onChange={(event) =>
                  setSeverity(tyre.position, event.target.value as TyreSeverity | "")
                }
                aria-label={`How bad is the ${
                  POSITIONS.find((entry) => entry.value === tyre.position)?.label ?? tyre.position
                }?`}
                className="rounded-lg border border-line bg-surface-sunken px-2 py-1.5 text-sm text-ink"
              >
                <option value="">How bad is it? (optional)</option>
                {SEVERITIES.map((severity) => (
                  <option key={severity.value} value={severity.value}>
                    {severity.label}
                  </option>
                ))}
              </select>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-ink-subtle">
          Tap the wheel that is damaged. If you are not sure, leave it — the technician will check.
        </p>
      )}
    </div>
  );
}
