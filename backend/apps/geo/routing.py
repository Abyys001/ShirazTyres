"""Travel time between two points, and from many drivers to one job.

Section 6.4 is explicit: candidates are ranked by routing-engine travel time, never by
straight-line distance. Section 10.2 is equally explicit that a stock OSRM profile is
optimistic in central London, so every provider's answer passes through a configurable
time-of-day correction before anyone sees it.
"""

import logging
from dataclasses import dataclass

import requests
from django.conf import settings
from django.utils import timezone

from .geometry import haversine_km

logger = logging.getLogger(__name__)


class RoutingError(Exception):
    pass


@dataclass(frozen=True)
class Route:
    duration_seconds: int
    distance_metres: int

    @property
    def duration_minutes(self) -> int:
        return max(1, round(self.duration_seconds / 60))


def traffic_factor(moment=None) -> float:
    """A blunt but honest correction. Calibrate against observed journeys before launch."""
    moment = timezone.localtime(moment or timezone.now())
    factors = settings.ROUTING_TRAFFIC_FACTORS
    if moment.weekday() >= 5:
        return float(factors.get("weekend", 1.0))
    hour = moment.hour
    if 7 <= hour < 10:
        return float(factors.get("morning_peak", 1.0))
    if 16 <= hour < 19:
        return float(factors.get("evening_peak", 1.0))
    if 22 <= hour or hour < 6:
        return float(factors.get("overnight", 1.0))
    return float(factors.get("default", 1.0))


def _corrected(seconds: float) -> int:
    return int(round(seconds * traffic_factor()))


class MockRoutingProvider:
    """Straight-line distance at a plausible urban speed. Development and CI only —
    it is deliberately *not* the fallback for production, see ``get_routing_provider``."""

    URBAN_KPH = 24.0

    def route(self, origin: tuple[float, float], destination: tuple[float, float]) -> Route:
        km = haversine_km(origin[0], origin[1], destination[0], destination[1]) * 1.35
        return Route(_corrected(km / self.URBAN_KPH * 3600), int(km * 1000))

    def matrix(self, origins: list[tuple[float, float]], destination: tuple[float, float]) -> list[Route | None]:
        return [self.route(origin, destination) for origin in origins]


class OsrmRoutingProvider:
    """Self-hosted OSRM or Valhalla behind an OSRM-compatible route/table API."""

    def _get(self, path: str, params: dict) -> dict:
        url = f"{settings.ROUTING_BASE_URL.rstrip('/')}{path}"
        try:
            response = requests.get(url, params=params, timeout=settings.ROUTING_TIMEOUT)
        except requests.RequestException as exc:
            raise RoutingError(f"Routing service unreachable: {exc}") from exc
        if response.status_code >= 400:
            raise RoutingError(f"Routing service returned {response.status_code}.")
        payload = response.json()
        if payload.get("code") not in (None, "Ok"):
            raise RoutingError(payload.get("message") or "Routing service rejected the request.")
        return payload

    def route(self, origin, destination) -> Route:
        coords = f"{origin[1]},{origin[0]};{destination[1]},{destination[0]}"
        payload = self._get(f"/route/v1/driving/{coords}", {"overview": "false"})
        routes = payload.get("routes") or []
        if not routes:
            raise RoutingError("No route between those points.")
        return Route(_corrected(routes[0]["duration"]), int(routes[0]["distance"]))

    def matrix(self, origins, destination) -> list[Route | None]:
        if not origins:
            return []
        points = list(origins) + [destination]
        coords = ";".join(f"{lng},{lat}" for lat, lng in points)
        sources = ";".join(str(index) for index in range(len(origins)))
        payload = self._get(
            f"/table/v1/driving/{coords}",
            {"sources": sources, "destinations": str(len(origins)), "annotations": "duration,distance"},
        )
        durations = payload.get("durations") or []
        distances = payload.get("distances") or []

        results: list[Route | None] = []
        for index in range(len(origins)):
            duration = (durations[index] or [None])[0] if index < len(durations) else None
            distance = (distances[index] or [0])[0] if index < len(distances) else 0
            results.append(None if duration is None else Route(_corrected(duration), int(distance or 0)))
        return results


class GraphHopperRoutingProvider:
    """Traffic-aware hosted routing. The Matrix API is a paid add-on, so a missing
    matrix endpoint degrades to sequential point-to-point calls rather than failing."""

    def route(self, origin, destination) -> Route:
        try:
            response = requests.get(
                f"{settings.ROUTING_BASE_URL.rstrip('/')}/route",
                params=[
                    ("point", f"{origin[0]},{origin[1]}"),
                    ("point", f"{destination[0]},{destination[1]}"),
                    ("profile", "car"),
                    ("calc_points", "false"),
                    ("key", settings.ROUTING_API_KEY),
                ],
                timeout=settings.ROUTING_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise RoutingError(f"Routing service unreachable: {exc}") from exc
        if response.status_code >= 400:
            raise RoutingError(f"Routing service returned {response.status_code}.")

        paths = response.json().get("paths") or []
        if not paths:
            raise RoutingError("No route between those points.")
        return Route(_corrected(paths[0]["time"] / 1000), int(paths[0]["distance"]))

    def matrix(self, origins, destination) -> list[Route | None]:
        results: list[Route | None] = []
        for origin in origins:
            try:
                results.append(self.route(origin, destination))
            except RoutingError as exc:
                logger.warning("routing.leg_failed origin=%s error=%s", origin, exc)
                results.append(None)
        return results


_PROVIDERS = {
    "mock": MockRoutingProvider,
    "osrm": OsrmRoutingProvider,
    "valhalla": OsrmRoutingProvider,
    "graphhopper": GraphHopperRoutingProvider,
}


def get_routing_provider():
    try:
        return _PROVIDERS[settings.ROUTING_PROVIDER]()
    except KeyError as exc:
        raise RoutingError(f"Unknown routing provider: {settings.ROUTING_PROVIDER}") from exc


def travel_time(origin: tuple[float, float], destination: tuple[float, float]) -> Route | None:
    try:
        return get_routing_provider().route(origin, destination)
    except RoutingError as exc:
        logger.warning("routing.failed origin=%s destination=%s error=%s", origin, destination, exc)
        return None


def travel_times(origins: list[tuple[float, float]], destination: tuple[float, float]) -> list[Route | None]:
    """One matrix call for the whole candidate pool — N round trips would blow the
    dispatch timeout long before the drivers did."""
    if not origins:
        return []
    try:
        return get_routing_provider().matrix(origins, destination)
    except RoutingError as exc:
        logger.warning("routing.matrix_failed count=%s error=%s", len(origins), exc)
        return [None] * len(origins)
