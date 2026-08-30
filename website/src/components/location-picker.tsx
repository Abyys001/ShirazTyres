"use client";

import "leaflet/dist/leaflet.css";

import L from "leaflet";
import { useEffect, useRef, useState } from "react";

import { Button, Notice } from "@/components/ui";

const TILE_URL = process.env.NEXT_PUBLIC_MAP_TILE_URL || "";
const ATTRIBUTION = process.env.NEXT_PUBLIC_MAP_ATTRIBUTION || "© OpenStreetMap contributors";
const LONDON: [number, number] = [51.5074, -0.1278];

export interface Position {
  latitude: number;
  longitude: number;
  accuracy: number | null;
  source: "browser" | "map_pin";
}

/**
 * Location capture (specification 4.4).
 *
 * Browser geolocation first, with a map pin for anyone who declines the permission or
 * whose fix is too coarse. There is deliberately no postcode box: a postcode is not
 * precise enough on a dual carriageway or in a multi-storey car park.
 */
export function LocationPicker({
  value,
  onChange,
}: {
  value: Position | null;
  onChange: (position: Position) => void;
}) {
  const [state, setState] = useState<"idle" | "asking" | "denied">("idle");
  const [pinning, setPinning] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const marker = useRef<L.Marker | null>(null);

  function ask() {
    if (!("geolocation" in navigator)) {
      setState("denied");
      setPinning(true);
      return;
    }
    setState("asking");
    navigator.geolocation.getCurrentPosition(
      (fix) => {
        setState("idle");
        onChange({
          latitude: fix.coords.latitude,
          longitude: fix.coords.longitude,
          accuracy: Math.round(fix.coords.accuracy),
          source: "browser",
        });
      },
      () => {
        setState("denied");
        setPinning(true);
      },
      { enableHighAccuracy: true, timeout: 15_000, maximumAge: 0 },
    );
  }

  useEffect(() => {
    if (!pinning || !container.current || map.current) return;

    const centre: [number, number] = value ? [value.latitude, value.longitude] : LONDON;
    map.current = L.map(container.current).setView(centre, value ? 16 : 11);
    if (TILE_URL) {
      L.tileLayer(TILE_URL, { attribution: ATTRIBUTION, maxZoom: 19 }).addTo(map.current);
    } else {
      L.control.attribution({ prefix: false }).addAttribution(ATTRIBUTION).addTo(map.current);
    }

    const place = (latlng: L.LatLng) => {
      if (marker.current) {
        marker.current.setLatLng(latlng);
      } else if (map.current) {
        marker.current = L.circleMarker(latlng, {
          radius: 9,
          color: "#0B1315",
          fillColor: "#FFD700",
          fillOpacity: 0.95,
          weight: 2,
        }).addTo(map.current) as unknown as L.Marker;
      }
      onChange({
        latitude: Number(latlng.lat.toFixed(6)),
        longitude: Number(latlng.lng.toFixed(6)),
        accuracy: null,
        source: "map_pin",
      });
    };

    if (value) place(L.latLng(value.latitude, value.longitude));
    map.current.on("click", (event: L.LeafletMouseEvent) => place(event.latlng));

    return () => {
      map.current?.remove();
      map.current = null;
      marker.current = null;
    };
    // The map is created once when the fallback opens; updates go through `place`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pinning]);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <Button type="button" onClick={ask} disabled={state === "asking"}>
          {state === "asking" ? "Finding you…" : value?.source === "browser" ? "Update my location" : "Use my location"}
        </Button>
        <Button type="button" variant="secondary" onClick={() => setPinning((open) => !open)}>
          {pinning ? "Hide the map" : "Put a pin on the map instead"}
        </Button>
      </div>

      {state === "denied" ? (
        <Notice tone="warning">
          We could not read your position. Drop a pin on the map as close as you can to where the car is.
        </Notice>
      ) : null}

      {pinning ? (
        <div>
          <div ref={container} className="h-72 w-full rounded-lg border border-line" />
          <p className="mt-1 text-xs text-ink-subtle">Tap the map where your car is.</p>
        </div>
      ) : null}

      {value ? (
        <Notice>
          Location set: {value.latitude.toFixed(5)}, {value.longitude.toFixed(5)}
          {value.accuracy ? ` (to about ${value.accuracy} m)` : " (from the map)"}
        </Notice>
      ) : (
        <p className="text-sm text-ink-muted">
          We need your position, not a postcode — a postcode will not find you on a dual carriageway.
        </p>
      )}
    </div>
  );
}
