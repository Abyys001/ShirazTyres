"""Which area is a point in, and what does dispatch look like there."""

import logging

from django.core.cache import cache

from apps.configuration.services import get_setting

from .models import ServiceArea

logger = logging.getLogger(__name__)

_CACHE_KEY = "geo:active_areas:v1"
_CACHE_TTL = 300

DISPATCH_OVERRIDABLE = {
    "dispatch.mode",
    "dispatch.offer_batch_size",
    "dispatch.initial_radius_km",
    "dispatch.radius_increment_km",
    "dispatch.selection_timeout_seconds",
    "dispatch.automatic_timeout_seconds",
    "dispatch.max_attempts",
    "dispatch.escalation_fallback",
}


def invalidate_cache() -> None:
    cache.delete(_CACHE_KEY)


def active_areas() -> list[ServiceArea]:
    areas = cache.get(_CACHE_KEY)
    if areas is None:
        areas = list(ServiceArea.objects.filter(is_active=True))
        cache.set(_CACHE_KEY, areas, _CACHE_TTL)
    return areas


def find_area(latitude, longitude) -> ServiceArea | None:
    """Highest-priority active area containing the point, or None."""
    if latitude is None or longitude is None:
        return None
    for area in active_areas():
        if area.contains(latitude, longitude):
            return area
    return None


def is_covered(latitude, longitude) -> bool:
    """A location with no areas configured is covered — an empty table must not
    silently refuse every request during setup."""
    if not get_setting("service_areas.enforce"):
        return True
    if not active_areas():
        return True
    return find_area(latitude, longitude) is not None


def area_setting(area: ServiceArea | None, key: str):
    """Per-area dispatch override, falling back to the global setting."""
    if area is not None and key in DISPATCH_OVERRIDABLE:
        override = (area.dispatch_overrides or {}).get(key)
        if override is not None:
            from apps.configuration.catalogue import BY_KEY
            from apps.configuration.services import _coerce

            spec = BY_KEY.get(key)
            if spec is not None:
                return _coerce(spec, override)
    return get_setting(key)


def service_area_summary() -> list[dict]:
    """Enough for a customer surface to draw coverage, without shipping full polygons."""
    return [
        {"id": area.pk, "name": area.name, "centre": area.centre}
        for area in active_areas()
    ]
