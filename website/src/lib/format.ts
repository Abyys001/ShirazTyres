const DATE_TIME = new Intl.DateTimeFormat("en-GB", {
  day: "2-digit",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});

const DATE = new Intl.DateTimeFormat("en-GB", { day: "2-digit", month: "short", year: "numeric" });

export function formatDateTime(value: string | null | undefined): string {
  return value ? DATE_TIME.format(new Date(value)) : "—";
}

export function formatDate(value: string | null | undefined): string {
  return value ? DATE.format(new Date(value)) : "—";
}

export function timeAgo(value: string): string {
  const seconds = Math.floor((Date.now() - new Date(value).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export function money(value: string | number | null | undefined, currency = "GBP"): string {
  if (value === null || value === undefined || value === "") return "—";
  return new Intl.NumberFormat("en-GB", { style: "currency", currency }).format(Number(value));
}

export function eta(minutes: number | null | undefined): string {
  if (minutes === null || minutes === undefined) return "—";
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

export function distance(metres: number | null | undefined): string {
  if (metres === null || metres === undefined) return "—";
  return metres < 1000 ? `${metres} m` : `${(metres / 1000).toFixed(1)} km`;
}

/** How stale a driver's last position is — the map needs this to be honest. */
export function fixAge(value: string | null): string {
  if (!value) return "no fix";
  const seconds = Math.floor((Date.now() - new Date(value).getTime()) / 1000);
  if (seconds < 90) return "live";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m old`;
  return `${Math.floor(seconds / 3600)}h old`;
}
