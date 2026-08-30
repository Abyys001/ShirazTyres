"use client";

import "leaflet/dist/leaflet.css";

import L from "leaflet";
import { useEffect, useRef } from "react";

import type { DriverMapRow } from "@/types/api";

const TILE_URL = process.env.NEXT_PUBLIC_MAP_TILE_URL || "";
const ATTRIBUTION =
  process.env.NEXT_PUBLIC_MAP_ATTRIBUTION || "© OpenStreetMap contributors";

const LONDON: [number, number] = [51.5074, -0.1278];

/**
 * The panel's live driver map (specification 11.1).
 *
 * Section 10.1: production must not point at OSM's own tile server, so the tile URL is
 * configuration. With none set the map still works — markers on a plain background —
 * rather than quietly borrowing tiles we are not entitled to.
 */
export function DriverMap({ drivers }: { drivers: DriverMapRow[] }) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const markers = useRef<Map<number, L.CircleMarker>>(new Map());

  useEffect(() => {
    if (!container.current || map.current) return;
    const placed = markers.current;

    map.current = L.map(container.current).setView(LONDON, 11);
    if (TILE_URL) {
      L.tileLayer(TILE_URL, { attribution: ATTRIBUTION, maxZoom: 19 }).addTo(map.current);
    } else {
      // Attribution still belongs on screen the moment real tiles are configured.
      L.control.attribution({ prefix: false }).addAttribution(ATTRIBUTION).addTo(map.current);
    }

    return () => {
      map.current?.remove();
      map.current = null;
      placed.clear();
    };
  }, []);

  useEffect(() => {
    if (!map.current) return;
    const seen = new Set<number>();

    for (const driver of drivers) {
      if (!driver.latitude || !driver.longitude) continue;
      seen.add(driver.id);

      const position: [number, number] = [Number(driver.latitude), Number(driver.longitude)];
      const colour = driver.active_jobs > 0 ? "#2563eb" : "#059669";
      const label = `${driver.name} · ${driver.vehicle_plate || "no van"}${
        driver.active_jobs > 0 ? " · on a job" : " · free"
      }`;

      const existing = markers.current.get(driver.id);
      if (existing) {
        existing.setLatLng(position).setStyle({ color: colour, fillColor: colour });
        existing.setPopupContent(label);
      } else {
        const marker = L.circleMarker(position, {
          radius: 8,
          color: colour,
          fillColor: colour,
          fillOpacity: 0.85,
          weight: 2,
        })
          .bindPopup(label)
          .addTo(map.current);
        markers.current.set(driver.id, marker);
      }
    }

    for (const [id, marker] of markers.current) {
      if (!seen.has(id)) {
        marker.remove();
        markers.current.delete(id);
      }
    }
  }, [drivers]);

  return <div ref={container} className="h-[70vh] w-full rounded-lg border border-line" />;
}
