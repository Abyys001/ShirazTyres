from rest_framework import serializers

from .models import ConfirmationPath, CustomerVehicle, Vehicle
from .plate import normalise_plate


class PlateField(serializers.CharField):
    def to_internal_value(self, data):
        return normalise_plate(super().to_internal_value(data))


class VehicleSerializer(serializers.ModelSerializer):
    plate = PlateField(max_length=16)
    display_plate = serializers.CharField(read_only=True)
    description = serializers.CharField(read_only=True)
    has_tyre_data = serializers.BooleanField(read_only=True)
    is_fitment_ambiguous = serializers.BooleanField(read_only=True)

    class Meta:
        model = Vehicle
        fields = (
            "id", "plate", "display_plate", "description", "make", "model", "colour", "fuel_type",
            "engine_capacity", "year_of_manufacture", "co2_emissions", "tax_status", "tax_due_date",
            "mot_status", "mot_expiry_date", "tyre_size_front", "tyre_size_rear", "tyre_load_index",
            "tyre_speed_rating", "tyre_pressure_front_psi", "tyre_pressure_rear_psi",
            "tyre_size_options", "tyre_source", "has_tyre_data", "is_fitment_ambiguous",
            "dvla_fetched_at", "tyre_fetched_at", "lookup_error", "updated_at",
        )
        read_only_fields = fields


class TyreConfirmationSerializer(serializers.Serializer):
    """The section 4.3 decision, in the shape both customer surfaces post it."""

    confirmation_path = serializers.ChoiceField(choices=ConfirmationPath.choices)
    tyre_size = serializers.CharField(max_length=32, required=False, allow_blank=True)
    load_index = serializers.CharField(max_length=16, required=False, allow_blank=True)
    speed_rating = serializers.CharField(max_length=8, required=False, allow_blank=True)
    disclaimer_accepted = serializers.BooleanField(default=False)

    def validate(self, attrs):
        if attrs["confirmation_path"] == ConfirmationPath.OVERRIDDEN:
            if not attrs.get("disclaimer_accepted"):
                raise serializers.ValidationError(
                    {"disclaimer_accepted": ["Acknowledge the responsibility notice to continue."]}
                )
            if not attrs.get("tyre_size"):
                raise serializers.ValidationError(
                    {"tyre_size": ["Enter the tyre size fitted to your car."]}
                )
        return attrs


class StaffTyreOverrideSerializer(serializers.Serializer):
    tyre_size = serializers.CharField(max_length=32)


class CustomerVehicleSerializer(serializers.ModelSerializer):
    vehicle = VehicleSerializer(read_only=True)
    plate = PlateField(max_length=16, write_only=True)
    effective_tyre_size = serializers.CharField(read_only=True)

    class Meta:
        model = CustomerVehicle
        fields = (
            "id", "vehicle", "plate", "nickname", "is_primary", "confirmation_path",
            "looked_up_tyre_size", "customer_tyre_size", "customer_load_index",
            "customer_speed_rating", "disclaimer_accepted_at", "confirmed_at",
            "effective_tyre_size", "created_at",
        )
        read_only_fields = (
            "id", "vehicle", "confirmation_path", "looked_up_tyre_size", "customer_tyre_size",
            "customer_load_index", "customer_speed_rating", "disclaimer_accepted_at",
            "confirmed_at", "effective_tyre_size", "created_at",
        )
