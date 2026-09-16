"use client";

import "leaflet/dist/leaflet.css";

import L from "leaflet";
import { useEffect, useRef } from "react";

import type { DriverMapRow, JobMapRow } from "@/types/api";

/*
 * Section 10.1: production must not point at OSM's own tile server, so the tile
 * URL is configuration.
 *
 * It shipped empty, though, which meant the map drew markers on a flat void and
 * every reasonable person called that "the map doesn't open" — nothing on screen
 * says whether you are looking at a broken map or an empty London. Development
 * now falls back to OSM so the thing works out of the box; a production build
 * with no tile source says so on the map instead of going quiet.
 */
const OSM_TILES = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png";
const CONFIGURED_TILES = process.env.NEXT_PUBLIC_MAP_TILE_URL || "";
const TILE_URL =
  CONFIGURED_TILES || (process.env.NODE_ENV === "development" ? OSM_TILES : "");
const ATTRIBUTION =
  process.env.NEXT_PUBLIC_MAP_TILE_ATTRIBUTION || "© OpenStreetMap contributors";

const LONDON: [number, number] = [51.5074, -0.1278];

/*
 * Marker colours are literals, not tokens.
 *
 * Leaflet writes `stroke` and `fill` as SVG presentation attributes, which do
 * not resolve `var()` — a token here paints nothing at all. They are also drawn
 * on map tiles rather than on our own surfaces, so they have to hold up against
 * whatever the tile source looks like rather than against the panel's theme.
 * These are the mid-weight steps of the same ramps as the status chips.
 */
const MAP_DANGER = "#DC2626";
const MAP_WARNING = "#D97706";
const MAP_INFO = "#2563EB";
const MAP_ACCENT = "#0891B2";
const MAP_BRAND = "#C99700";
const MAP_SUCCESS = "#059669";
const MAP_MUTED = "#64748B";

/** The job pin's fill, by state. Same readings as the board's status chips. */
const JOB_TONE: Record<string, string> = {
  unclaimed: MAP_DANGER,
  submitted: MAP_WARNING,
  dispatching: MAP_WARNING,
  assigned: MAP_INFO,
  accepted: MAP_INFO,
  en_route: MAP_ACCENT,
  arrived: MAP_ACCENT,
  in_progress: MAP_BRAND,
};

function coords(lat: string | null, lon: string | null): [number, number] | null {
  if (lat === null || lon === null) return null;
  const latitude = Number(lat);
  const longitude = Number(lon);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return [latitude, longitude];
}

/**
 * The panel's live map (specification 11.1) — vans and call-outs on one surface.
 *
 * Drivers alone answered "where are my vans", which is only half the question a
 * dispatcher is actually asking. The other half is who is waiting and how far
 * the van still has to go, so jobs are drawn here too and the pair currently
 * being tracked is joined by a line. Reading the gap between two points is
 * immediate in a way that reading "4.2 km" next to a name is not.
 */
export function LiveMap({
  drivers,
  jobs,
  focusDriverId,
  focusJobId,
  onSelectDriver,
  onSelectJob,
  height = "h-[70vh]",
}: {
  drivers: DriverMapRow[];
  jobs: JobMapRow[];
  focusDriverId?: number | null;
  focusJobId?: number | null;
  onSelectDriver?: (id: number) => void;
  onSelectJob?: (id: number) => void;
  height?: string;
}) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const driverMarkers = useRef<Map<number, L.CircleMarker>>(new Map());
  const jobMarkers = useRef<Map<number, L.Marker>>(new Map());
  const link = useRef<L.Polyline | null>(null);

  // Handlers live in a ref so re-rendering the page does not rebind every pin.
  const handlers = useRef({ onSelectDriver, onSelectJob });
  handlers.current = { onSelectDriver, onSelectJob };

  useEffect(() => {
    if (!container.current || map.current) return;
    const placedDrivers = driverMarkers.current;
    const placedJobs = jobMarkers.current;

    map.current = L.map(container.current, { zoomControl: true }).setView(LONDON, 11);
    if (TILE_URL) {
      L.tileLayer(TILE_URL, { attribution: ATTRIBUTION, maxZoom: 19 }).addTo(map.current);
    } else {
      // Attribution still belongs on screen the moment real tiles are configured.
      L.control.attribution({ prefix: false }).addAttribution(ATTRIBUTION).addTo(map.current);
    }

    return () => {
      map.current?.remove();
      map.current = null;
      placedDrivers.clear();
      placedJobs.clear();
      link.current = null;
    };
  }, []);

  // ------------------------------------------------------------- drivers ----
  useEffect(() => {
    if (!map.current) return;
    const seen = new Set<number>();

    for (const driver of drivers) {
      const position = coords(driver.latitude, driver.longitude);
      if (!position) continue;
      seen.add(driver.id);

      const busy = driver.active_jobs > 0;
      const colour = busy ? MAP_INFO : MAP_SUCCESS;
      const label = `<strong>${escapeHtml(driver.name)}</strong><br>${
        escapeHtml(driver.vehicle_plate || "no van")
      } · ${busy ? "on a job" : "free"}`;

      const existing = driverMarkers.current.get(driver.id);
      if (existing) {
        existing.setLatLng(position).setStyle({ color: colour, fillColor: colour });
        existing.setPopupContent(label);
      } else {
        const marker = L.circleMarker(position, {
          radius: 9,
          color: colour,
          fillColor: colour,
          fillOpacity: 0.85,
          weight: 3,
        })
          .bindPopup(label)
          .addTo(map.current);
        marker.on("click", () => handlers.current.onSelectDriver?.(driver.id));
        driverMarkers.current.set(driver.id, marker);
      }
    }

    for (const [id, marker] of driverMarkers.current) {
      if (!seen.has(id)) {
        marker.remove();
        driverMarkers.current.delete(id);
      }
    }
  }, [drivers]);

  // ---------------------------------------------------------------- jobs ----
  useEffect(() => {
    if (!map.current) return;
    const seen = new Set<number>();

    for (const job of jobs) {
      const position = coords(job.latitude, job.longitude);
      if (!position) continue;
      seen.add(job.id);

      const tone = JOB_TONE[job.status] ?? MAP_MUTED;
      const icon = L.divIcon({
        className: "",
        html: platePin(job.plate, tone, job.status === "unclaimed"),
        iconSize: [0, 0],
        iconAnchor: [0, 0],
      });
      const label = `<strong>${escapeHtml(job.reference)}</strong> · ${escapeHtml(
        job.status_display,
      )}<br>${escapeHtml(job.location_text || "no address")}<br>${
        job.driver_name ? escapeHtml(job.driver_name) : "nobody assigned"
      }`;

      const existing = jobMarkers.current.get(job.id);
      if (existing) {
        existing.setLatLng(position).setIcon(icon);
        existing.setPopupContent(label);
      } else {
        const marker = L.marker(position, { icon }).bindPopup(label).addTo(map.current);
        marker.on("click", () => handlers.current.onSelectJob?.(job.id));
        jobMarkers.current.set(job.id, marker);
      }
    }

    for (const [id, marker] of jobMarkers.current) {
      if (!seen.has(id)) {
        marker.remove();
        jobMarkers.current.delete(id);
      }
    }
  }, [jobs]);

  // --------------------------------------------- the tracked pair's line ----
  useEffect(() => {
    if (!map.current) return;

    const job = focusJobId ? jobs.find((row) => row.id === focusJobId) : undefined;
    const from = job ? coords(job.driver_latitude, job.driver_longitude) : null;
    const to = job ? coords(job.latitude, job.longitude) : null;

    link.current?.remove();
    link.current = null;
    if (!from || !to) return;

    link.current = L.polyline([from, to], {
      color: MAP_BRAND,
      weight: 2.5,
      opacity: 0.85,
      dashArray: "7 6",
    }).addTo(map.current);
    map.current.fitBounds(L.latLngBounds([from, to]).pad(0.35), { animate: true });
  }, [focusJobId, jobs]);

  // ------------------------------------------------------ deep-link focus ----
  useEffect(() => {
    if (!map.current || !focusDriverId) return;
    const marker = driverMarkers.current.get(focusDriverId);
    if (!marker) return;
    map.current.flyTo(marker.getLatLng(), Math.max(map.current.getZoom(), 14), {
      duration: 0.75,
    });
    marker.openPopup();
  }, [focusDriverId, drivers]);

  return (
    <div className={`relative ${height} w-full`}>
      <div ref={container} className="h-full w-full rounded-lg border border-line" />
      {TILE_URL ? null : (
        <div className="pointer-events-none absolute inset-x-0 top-0 z-[400] m-3 rounded-md border border-warning/40 bg-surface/95 px-3 py-2 text-sm text-ink-muted shadow-sm">
          <strong className="text-warning">No map tiles configured.</strong> Pins are
          positioned correctly but there is nothing to draw them on. Set{" "}
          <code className="font-mono text-xs">NEXT_PUBLIC_MAP_TILE_URL</code> — section 10.1.
        </div>
      )}
    </div>
  );
}

/**
 * A job drawn as its registration rather than a dot.
 *
 * The plate is what a dispatcher is looking for — it is how they refer to the
 * car on the phone — so the pin is the plate, in the same black-on-gold as the
 * board. An unclaimed one wears the alarm tone and the halo from `globals.css`.
 */
function platePin(plate: string, tone: string, alarmed: boolean): string {
  const text = escapeHtml((plate || "no plate").toUpperCase());
  return `
    <div style="transform:translate(-50%,-100%);display:flex;flex-direction:column;align-items:center;">
      <span class="plate" style="white-space:nowrap;box-shadow:0 2px 6px rgba(0,0,0,.45)">${text}</span>
      <span class="${alarmed ? "alarm-ring" : ""}" style="width:11px;height:11px;margin-top:-2px;border-radius:9999px;background:${tone};border:2px solid rgba(0,0,0,.45)"></span>
    </div>`;
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character] ?? character,
  );
}
