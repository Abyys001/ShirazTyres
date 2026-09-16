import logging
from typing import Any

from django.conf import settings

from .models import AuditEvent

logger = logging.getLogger(__name__)

#: Payload keys that must never reach the log, whatever a caller passes.
#: Matched case-insensitively against the end of the key, so ``api_token`` and
#: ``stripe_secret_key`` are caught as readily as ``token`` and ``secret``.
_REDACT_SUFFIXES = (
    "password", "secret", "token", "key", "authorization", "signature",
    "card", "cvc", "pan", "api_key",
)

_REDACTED = "[redacted]"


def _clean(value: Any, *, depth: int = 0) -> Any:
    """Strip anything secret out of a payload before it is written down."""
    if depth > 4:
        return "[too deep]"
    if isinstance(value, dict):
        cleaned = {}
        for key, item in value.items():
            name = str(key)
            if any(name.lower().endswith(suffix) for suffix in _REDACT_SUFFIXES):
                cleaned[name] = _REDACTED
            else:
                cleaned[name] = _clean(item, depth=depth + 1)
        return cleaned
    if isinstance(value, (list, tuple)):
        return [_clean(item, depth=depth + 1) for item in value[:50]]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def record(
    category: str,
    message: str,
    *,
    severity: str = AuditEvent.Severity.INFO,
    actor: str = "",
    subject_type: str = "",
    subject_id: Any = "",
    **payload: Any,
) -> AuditEvent | None:
    """
    Write one event to the operational log.

    **This must never be the reason a request fails.** The log exists to explain
    what the system did; a log that can break the thing it is observing is worse
    than no log at all. Every failure here is swallowed and reported to stdout,
    exactly as ``realtime.publish._send`` treats a broker hiccup.

    Payloads are scrubbed by ``_clean`` on the way in, so a caller that passes a
    whole request body cannot accidentally persist a password or a Stripe key.
    """
    try:
        return AuditEvent.objects.create(
            category=category,
            severity=severity,
            message=message[:255],
            actor=str(actor)[:120],
            subject_type=str(subject_type)[:40],
            subject_id=str(subject_id)[:64] if subject_id != "" else "",
            payload=_clean(payload),
        )
    except Exception as exc:  # noqa: BLE001 — logging must not break the caller.
        logger.warning("audit.record_failed category=%s message=%s error=%s", category, message, exc)
        return None


def otp_is_visible() -> bool:
    """
    Whether a verification code may be written into the log.

    The same rule the API already applies to ``debug_code``: with the mock SMS
    provider there is no text message to read the code out of, so it is returned
    in the response and shown on the sign-in screens. Anywhere a real provider is
    configured the code is a live credential and never gets recorded.
    """
    return settings.DEBUG and getattr(settings, "SMS_PROVIDER", "mock") == "mock"
