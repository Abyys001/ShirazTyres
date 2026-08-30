"""JWT issuing/parsing for the three audiences: staff, customers and drivers.

Tokens are built by hand rather than via ``RefreshToken.for_user`` because neither
customers nor drivers are Django users; the ``scope`` claim is what keeps the three
audiences from crossing over.
"""

from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.tokens import RefreshToken

SCOPE_CLAIM = "scope"
SCOPE_STAFF = "staff"
SCOPE_CUSTOMER = "customer"
SCOPE_DRIVER = "driver"
SUBJECT_CLAIM = "sub_id"


def issue_pair(scope: str, subject_id: int, **claims) -> dict[str, str]:
    refresh = RefreshToken()
    refresh[SCOPE_CLAIM] = scope
    refresh[SUBJECT_CLAIM] = subject_id
    for key, value in claims.items():
        refresh[key] = value

    access = refresh.access_token
    access[SCOPE_CLAIM] = scope
    access[SUBJECT_CLAIM] = subject_id
    for key, value in claims.items():
        access[key] = value

    return {"access": str(access), "refresh": str(refresh)}


def refresh_pair(refresh_token: str, expected_scope: str) -> dict[str, str]:
    token = RefreshToken(refresh_token)
    if token.get(SCOPE_CLAIM) != expected_scope:
        raise InvalidToken("Token was issued for a different audience.")
    return issue_pair(expected_scope, token[SUBJECT_CLAIM])


def read_scoped_token(raw_token: str, expected_scope: str) -> int:
    """Used by the WebSocket layer, which has no DRF request to authenticate."""
    from rest_framework_simplejwt.tokens import AccessToken

    token = AccessToken(raw_token)
    if token.get(SCOPE_CLAIM) != expected_scope:
        raise InvalidToken("Token was issued for a different audience.")
    return int(token[SUBJECT_CLAIM])
