import type { DamagedTyre, TyrePosition } from "@/types/api";

const POSITION_LABEL: Record<TyrePosition, string> = {
  front_left: "Nearside front",
  front_right: "Offside front",
  rear_left: "Nearside rear",
  rear_right: "Offside rear",
  spare: "Spare",
};

const SEVERITY_LABEL: Record<string, string> = {
  flat: "completely flat",
  deflating: "losing air",
  damaged: "damaged but holding",
  blowout: "blowout",
};

/** Where each corner sits on the plan view, as a fraction of the box. */
const CORNERS: Partial<Record<TyrePosition, { x: number; y: number }>> = {
  front_left: { x: 0.175, y: 0.265 },
  front_right: { x: 0.825, y: 0.265 },
  rear_left: { x: 0.175, y: 0.735 },
  rear_right: { x: 0.825, y: 0.735 },
};

/**
 * Which wheels the customer marked, drawn the way they marked them.
 *
 * The office fields the phone call when a technician arrives with the wrong
 * tyre, so the panel needs the same picture the customer tapped and the driver
 * app shows — three different renderings of one fact is how they end up
 * disagreeing. Read-only here: the customer said it, and the record of what they
 * said is the point.
 */
export function TyreDamage({ damaged }: { damaged: DamagedTyre[] }) {
  if (!damaged || damaged.length === 0) {
    return <p className="text-sm text-ink-subtle">The customer did not say which wheel.</p>;
  }

  const hit = new Set(damaged.map((tyre) => tyre.position));
  const onCorners = damaged.some((tyre) => tyre.position in CORNERS);

  return (
    <div className="flex flex-wrap items-start gap-5">
      {onCorners ? (
        <svg
          viewBox="0 -5 100 133"
          className="h-40 w-auto shrink-0"
          role="img"
          aria-label="Plan view of the car with the damaged wheels marked"
        >
          <rect
            x="26" y="6" width="48" height="116" rx="16"
            className="fill-surface-raised stroke-line-strong"
            strokeWidth="1.5"
          />
          <rect x="31" y="17" width="38" height="18" rx="5" className="fill-surface-sunken" />
          <rect x="31" y="92" width="38" height="17" rx="4.5" className="fill-surface-sunken" />
          <line x1="50" y1="38" x2="50" y2="88" className="stroke-line" strokeWidth="1" />

          {Object.entries(CORNERS).map(([position, point]) => {
            const marked = hit.has(position as TyrePosition);
            return (
              <g key={position}>
                <rect
                  x={point.x * 100 - 6.5}
                  y={point.y * 128 - 9}
                  width="13" height="18" rx="3"
                  className="fill-line-strong"
                />
                {marked ? (
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
      ) : null}

      <ul className="min-w-[14rem] flex-1 space-y-2">
        {damaged.map((tyre) => (
          <li key={tyre.position} className="flex items-start gap-2 text-sm">
            <span aria-hidden className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-danger" />
            <span>
              <span className="text-ink">{POSITION_LABEL[tyre.position] ?? tyre.position}</span>
              {tyre.severity ? (
                <span className="text-ink-muted">
                  {" — "}
                  {SEVERITY_LABEL[tyre.severity] ?? tyre.severity}
                </span>
              ) : null}
              {tyre.note ? (
                <span className="block text-xs text-ink-subtle">{tyre.note}</span>
              ) : null}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
