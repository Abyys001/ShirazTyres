from rest_framework import serializers

from .catalogue import CATALOGUE
from .services import all_settings


class SettingSpecSerializer(serializers.Serializer):
    key = serializers.CharField()
    group = serializers.CharField()
    type = serializers.CharField()
    label = serializers.CharField()
    help_text = serializers.CharField()
    choices = serializers.ListField(child=serializers.DictField(), default=list)
    default = serializers.JSONField()
    value = serializers.JSONField()


class SettingsDocumentSerializer(serializers.Serializer):
    """One payload the panel can render a whole settings screen from."""

    values = serializers.DictField()
    specs = SettingSpecSerializer(many=True)

    @classmethod
    def build(cls) -> dict:
        values = all_settings()
        return {
            "values": {key: _jsonable(value) for key, value in values.items()},
            "specs": [
                {
                    "key": spec.key,
                    "group": spec.group,
                    "type": spec.type,
                    "label": spec.label,
                    "help_text": spec.help_text,
                    "choices": [{"value": value, "label": label} for value, label in spec.choices],
                    "default": _jsonable(spec.default),
                    "value": _jsonable(values[spec.key]),
                }
                for spec in CATALOGUE
            ],
        }


class SettingsUpdateSerializer(serializers.Serializer):
    values = serializers.DictField()


def _jsonable(value):
    from decimal import Decimal

    return str(value) if isinstance(value, Decimal) else value
