from rest_framework import serializers

from .models import DriverVehicle, Vehicle
from .plate import normalise_plate


class PlateField(serializers.CharField):
    def to_internal_value(self, data):
        return normalise_plate(super().to_internal_value(data))


class VehicleSerializer(serializers.ModelSerializer):
    plate = PlateField(max_length=16)
    display_plate = serializers.CharField(read_only=True)
    description = serializers.CharField(read_only=True)

    class Meta:
        model = Vehicle
        fields = (
            "id", "plate", "display_plate", "description", "make", "model", "colour", "fuel_type",
            "engine_capacity", "year_of_manufacture", "co2_emissions", "tax_status", "tax_due_date",
            "mot_status", "mot_expiry_date", "tyre_size_front", "tyre_size_rear", "tyre_load_index",
            "tyre_speed_rating", "tyre_pressure_front_psi", "tyre_pressure_rear_psi",
            "tyre_size_options", "tyre_source", "dvla_fetched_at", "tyre_fetched_at",
            "lookup_error", "updated_at",
        )
        read_only_fields = fields


class TyreConfirmSerializer(serializers.Serializer):
    tyre_size = serializers.CharField(max_length=32)


class DriverVehicleSerializer(serializers.ModelSerializer):
    vehicle = VehicleSerializer(read_only=True)
    plate = PlateField(max_length=16, write_only=True)

    class Meta:
        model = DriverVehicle
        fields = ("id", "vehicle", "plate", "nickname", "is_primary", "created_at")
        read_only_fields = ("id", "vehicle", "created_at")
