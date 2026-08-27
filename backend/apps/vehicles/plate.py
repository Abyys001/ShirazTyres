import re

from rest_framework import serializers

_PLATE_RE = re.compile(r"^[A-Z0-9]{2,8}$")


def normalise_plate(raw: str) -> str:
    """DVLA expects the registration with no spaces, upper case."""
    value = re.sub(r"[^A-Za-z0-9]", "", (raw or "")).upper()
    if not _PLATE_RE.match(value):
        raise serializers.ValidationError("Enter a valid UK registration number.")
    return value


def format_plate(value: str) -> str:
    """Display form: current-style plates split AB12 CDE, anything else left alone."""
    if len(value) == 7 and value[:2].isalpha() and value[2:4].isdigit():
        return f"{value[:4]} {value[4:]}"
    return value
