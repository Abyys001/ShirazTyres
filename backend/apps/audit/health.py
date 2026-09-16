"""
Is this system actually working right now?

Every check here does the cheapest real operation against the dependency rather
than reporting what the settings file hopes is true. A Redis URL in the
environment says nothing about whether Redis is answering, and on a dispatch
system the gap between those two is the whole question — the panel looks fine
while offers silently fail to reach anybody.
"""

import time
from typing import Any

from django.conf import settings
from django.db import connection


def _timed(probe) -> dict[str, Any]:
    started = time.monotonic()
    try:
        detail = probe()
        return {
            "ok": True,
            "detail": detail or "",
            "ms": round((time.monotonic() - started) * 1000, 1),
        }
    except Exception as exc:  # noqa: BLE001 — a health check reports faults, it does not raise them.
        return {
            "ok": False,
            "detail": f"{type(exc).__name__}: {exc}"[:200],
            "ms": round((time.monotonic() - started) * 1000, 1),
        }


def _database() -> str:
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
        cursor.fetchone()
    return connection.vendor


def _cache() -> str:
    """
    Round-trip a value through the cache the application actually uses.

    Not a bare Redis ping: Redis reaches this project as Django's cache backend
    (and as LocMem under ``USE_SQLITE``), and settings resolution, key prefixing
    and serialisation all sit between the app and the server. A write followed by
    a read proves the path the settings cache and the vehicle lookup depend on,
    which is the thing worth knowing.
    """
    from django.core.cache import caches

    # `django.core.cache.cache` is a lazy proxy, so its type name is always
    # "ConnectionProxy" and says nothing. Reach the configured backend itself.
    backend_cache = caches["default"]
    backend = type(backend_cache).__name__
    backend_cache.set("health:probe", "ok", 10)
    if backend_cache.get("health:probe") != "ok":
        raise RuntimeError(f"{backend} accepted a write but did not return it.")
    return backend


def _channel_layer() -> str:
    from channels.layers import get_channel_layer

    layer = get_channel_layer()
    if layer is None:
        raise RuntimeError("No channel layer configured — realtime is off.")
    return type(layer).__name__


def _celery() -> str:
    """
    Ask the workers to identify themselves.

    ``ping`` round-trips through the broker to every live worker, so a reply
    proves the broker is reachable *and* that something is on the other end of
    it. An empty reply means jobs are being queued into silence.
    """
    if getattr(settings, "CELERY_TASK_ALWAYS_EAGER", False):
        return "eager (tasks run inline)"

    from config.celery import app

    replies = app.control.ping(timeout=1.5) or []
    if not replies:
        raise RuntimeError("No workers answered — queued tasks will not run.")
    names = [name for reply in replies for name in reply]
    return f"{len(names)} worker(s): {', '.join(names)[:120]}"


def _providers() -> dict[str, Any]:
    """
    Which integrations are live and which are pretending.

    This is the one that catches a launch: everything mocked looks identical to
    everything working right up until a real customer is waiting for a real text
    message. Anything on a mock is reported as a warning rather than as healthy.
    """
    email_configured = bool(getattr(settings, "EMAIL_HOST", ""))
    rows = {
        "sms": {"mode": settings.SMS_PROVIDER, "live": settings.SMS_PROVIDER != "mock"},
        "push": {"mode": settings.PUSH_PROVIDER, "live": settings.PUSH_PROVIDER != "mock"},
        "email": {
            "mode": settings.EMAIL_HOST or "not configured",
            "live": email_configured,
        },
        "routing": {"mode": settings.ROUTING_PROVIDER, "live": settings.ROUTING_PROVIDER != "mock"},
        "vehicle_lookup": {
            "mode": "mock" if settings.VEHICLE_LOOKUP_MOCK else "dvla",
            "live": not settings.VEHICLE_LOOKUP_MOCK,
        },
        "google_oauth": {
            "mode": "mock" if settings.GOOGLE_OAUTH_MOCK else "live",
            "live": not settings.GOOGLE_OAUTH_MOCK,
        },
        "stripe": {
            "mode": getattr(settings, "STRIPE_MODE", "mock"),
            "live": getattr(settings, "STRIPE_MODE", "mock") == "live",
        },
        "map_tiles": {
            "mode": settings.MAP_TILE_URL or "not configured",
            "live": bool(settings.MAP_TILE_URL),
        },
    }
    return rows


def snapshot() -> dict[str, Any]:
    checks = {
        "database": _timed(_database),
        "cache": _timed(_cache),
        "channel_layer": _timed(_channel_layer),
        "celery": _timed(_celery),
    }
    providers = _providers()
    mocked = sorted(name for name, row in providers.items() if not row["live"])

    return {
        "ok": all(check["ok"] for check in checks.values()),
        "debug": settings.DEBUG,
        "checks": checks,
        "providers": providers,
        "mocked": mocked,
    }
