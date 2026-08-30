"""Google sign-in. The client sends an ID token; we verify the signature ourselves.

Never trust the ``sub``/``email`` a client claims — an unverified ID token is just a
string the caller made up, and it would hand over any account whose email it names.
"""

import logging
from dataclasses import dataclass

from django.conf import settings
from rest_framework import serializers

logger = logging.getLogger(__name__)

_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


@dataclass(frozen=True)
class GoogleProfile:
    subject: str
    email: str
    email_verified: bool
    name: str
    picture: str


class GoogleAuthError(serializers.ValidationError):
    pass


def _mock_profile(id_token: str) -> GoogleProfile:
    """Dev/CI: ``mock:someone@example.com`` stands in for a real ID token."""
    email = id_token.split(":", 1)[1] if id_token.startswith("mock:") else "demo@example.com"
    return GoogleProfile(
        subject=f"mock-{email}", email=email, email_verified=True,
        name=email.split("@")[0].replace(".", " ").title(), picture="",
    )


def verify_id_token(id_token: str) -> GoogleProfile:
    if settings.GOOGLE_OAUTH_MOCK:
        return _mock_profile(id_token)

    if not settings.GOOGLE_OAUTH_CLIENT_IDS:
        raise GoogleAuthError({"id_token": ["Google sign-in is not configured."]})

    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token
    except ImportError as exc:  # pragma: no cover - dependency is pinned in requirements
        raise GoogleAuthError({"id_token": ["Google sign-in is unavailable."]}) from exc

    request = google_requests.Request()
    claims = None
    for client_id in settings.GOOGLE_OAUTH_CLIENT_IDS:
        try:
            claims = google_id_token.verify_oauth2_token(id_token, request, client_id)
            break
        except ValueError:
            continue

    if claims is None:
        logger.warning("google.token_rejected")
        raise GoogleAuthError({"id_token": ["That Google sign-in could not be verified."]})

    if claims.get("iss") not in _ISSUERS:
        raise GoogleAuthError({"id_token": ["Unexpected token issuer."]})

    return GoogleProfile(
        subject=str(claims["sub"]),
        email=claims.get("email", "") or "",
        email_verified=bool(claims.get("email_verified")),
        name=claims.get("name", "") or "",
        picture=claims.get("picture", "") or "",
    )
