"""UK-first phone normalisation. Everything is stored E.164."""

import re

from rest_framework import serializers

_NON_DIGITS = re.compile(r"[^\d+]")


def normalise_phone(raw: str, default_region_prefix: str = "+44") -> str:
    if not raw:
        raise serializers.ValidationError("Phone number is required.")

    value = _NON_DIGITS.sub("", raw.strip())

    if value.startswith("00"):
        value = "+" + value[2:]
    elif value.startswith("0"):
        value = default_region_prefix + value[1:]
    elif not value.startswith("+"):
        value = default_region_prefix + value

    digits = value[1:]
    if not digits.isdigit() or not (8 <= len(digits) <= 15):
        raise serializers.ValidationError("Enter a valid phone number.")
    return value
