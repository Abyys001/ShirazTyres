from rest_framework import serializers

from .geometry import validate_geojson_polygon
from .models import ServiceArea
from .services import DISPATCH_OVERRIDABLE


class ServiceAreaSerializer(serializers.ModelSerializer):
    centre = serializers.JSONField(read_only=True)
    driver_count = serializers.IntegerField(read_only=True, default=0)

    class Meta:
        model = ServiceArea
        fields = (
            "id", "name", "boundary", "centre", "is_active", "priority",
            "dispatch_overrides", "notes", "driver_count", "created_at", "updated_at",
        )
        read_only_fields = ("id", "centre", "driver_count", "created_at", "updated_at")

    def validate_boundary(self, value):
        try:
            return validate_geojson_polygon(value)
        except ValueError as exc:
            raise serializers.ValidationError(str(exc)) from exc

    def validate_dispatch_overrides(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError("Overrides must be an object of setting keys.")
        unknown = set(value) - DISPATCH_OVERRIDABLE
        if unknown:
            raise serializers.ValidationError(
                f"These settings cannot be overridden per area: {', '.join(sorted(unknown))}."
            )
        return value


class CoverageCheckSerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)


class CoverageResultSerializer(serializers.Serializer):
    covered = serializers.BooleanField()
    area = serializers.CharField(allow_null=True)
    message = serializers.CharField(allow_blank=True)
