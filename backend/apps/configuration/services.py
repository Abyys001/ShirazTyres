"""Reading and writing owner settings.

Values are cached as one dict rather than per key: dispatch reads six or seven of
them per job, and a single cache round-trip beats seven.
"""

import logging
from decimal import Decimal, InvalidOperation
from typing import Any

from django.core.cache import cache
from rest_framework import serializers

from .catalogue import (
    BY_KEY,
    CATALOGUE,
    TYPE_BOOL,
    TYPE_CHOICE,
    TYPE_DECIMAL,
    TYPE_INT,
    TYPE_JSON,
    TYPE_STRING,
    TYPE_TEXT,
    SettingSpec,
)
from .models import Setting

logger = logging.getLogger(__name__)

_CACHE_KEY = "configuration:overrides:v1"
_CACHE_TTL = 300


def _overrides() -> dict[str, Any]:
    cached = cache.get(_CACHE_KEY)
    if cached is None:
        cached = dict(Setting.objects.values_list("key", "value"))
        cache.set(_CACHE_KEY, cached, _CACHE_TTL)
    return cached


def invalidate_cache() -> None:
    cache.delete(_CACHE_KEY)


def _coerce(spec: SettingSpec, raw: Any) -> Any:
    """JSON round-trips lose Decimal; the catalogue type is the authority on the way out."""
    if spec.type == TYPE_DECIMAL:
        try:
            return Decimal(str(raw))
        except (InvalidOperation, TypeError):
            return spec.default
    if spec.type == TYPE_INT:
        try:
            return int(raw)
        except (TypeError, ValueError):
            return spec.default
    if spec.type == TYPE_BOOL:
        return bool(raw)
    return raw


def get_setting(key: str) -> Any:
    spec = BY_KEY.get(key)
    if spec is None:
        raise KeyError(f"Unknown setting: {key}")
    overrides = _overrides()
    if key not in overrides:
        return spec.default
    return _coerce(spec, overrides[key])


def get_many(*keys: str) -> dict[str, Any]:
    return {key: get_setting(key) for key in keys}


def all_settings() -> dict[str, Any]:
    return {spec.key: get_setting(spec.key) for spec in CATALOGUE}


def validate_value(spec: SettingSpec, value: Any) -> Any:
    if spec.type == TYPE_BOOL:
        if isinstance(value, str):
            value = value.strip().lower() in {"1", "true", "yes", "on"}
        if not isinstance(value, bool):
            raise serializers.ValidationError(f"{spec.key} must be true or false.")
        return value

    if spec.type == TYPE_INT:
        try:
            value = int(value)
        except (TypeError, ValueError) as exc:
            raise serializers.ValidationError(f"{spec.key} must be a whole number.") from exc
        if value < 0:
            raise serializers.ValidationError(f"{spec.key} cannot be negative.")
        return value

    if spec.type == TYPE_DECIMAL:
        try:
            decimal_value = Decimal(str(value))
        except (InvalidOperation, TypeError) as exc:
            raise serializers.ValidationError(f"{spec.key} must be a number.") from exc
        if decimal_value < 0:
            raise serializers.ValidationError(f"{spec.key} cannot be negative.")
        return str(decimal_value)  # Stored as a string so JSON keeps the precision.

    if spec.type == TYPE_CHOICE:
        allowed = {choice for choice, _ in spec.choices}
        if value not in allowed:
            raise serializers.ValidationError(f"{spec.key} must be one of: {', '.join(sorted(allowed))}.")
        return value

    if spec.type in {TYPE_STRING, TYPE_TEXT}:
        if not isinstance(value, str):
            raise serializers.ValidationError(f"{spec.key} must be text.")
        return value

    if spec.type == TYPE_JSON:
        if not isinstance(value, (dict, list)):
            raise serializers.ValidationError(f"{spec.key} must be a JSON object or list.")
        return value

    raise serializers.ValidationError(f"{spec.key} has an unsupported type.")


def set_setting(key: str, value: Any, *, updated_by=None) -> Any:
    spec = BY_KEY.get(key)
    if spec is None:
        raise serializers.ValidationError({key: ["Unknown setting."]})
    stored = validate_value(spec, value)
    Setting.objects.update_or_create(key=key, defaults={"value": stored, "updated_by": updated_by})
    invalidate_cache()
    logger.info("setting.changed key=%s by=%s", key, getattr(updated_by, "email", "system"))
    return get_setting(key)


def set_many(values: dict[str, Any], *, updated_by=None) -> dict[str, Any]:
    errors: dict[str, list[str]] = {}
    for key, value in values.items():
        spec = BY_KEY.get(key)
        if spec is None:
            errors[key] = ["Unknown setting."]
            continue
        try:
            validate_value(spec, value)
        except serializers.ValidationError as exc:
            errors[key] = exc.detail if isinstance(exc.detail, list) else [str(exc.detail)]

    if errors:
        raise serializers.ValidationError(errors)

    for key, value in values.items():
        set_setting(key, value, updated_by=updated_by)
    return all_settings()
