from rest_framework import serializers

from apps.accounts.phone import normalise_phone
from apps.accounts.serializers import StaffUserSerializer
from apps.vehicles.models import Vehicle
from apps.vehicles.plate import normalise_plate
from apps.vehicles.providers import VehicleLookupError
from apps.vehicles.serializers import VehicleSerializer
from apps.vehicles.services import lookup_plate

from .models import Booking, BookingStatusEvent


class BookingStatusEventSerializer(serializers.ModelSerializer):
    changed_by_name = serializers.CharField(source="changed_by.name", read_only=True, default="")

    class Meta:
        model = BookingStatusEvent
        fields = ("id", "from_status", "to_status", "note", "changed_by_name", "created_at")


class BookingSerializer(serializers.ModelSerializer):
    vehicle = VehicleSerializer(read_only=True)
    assigned_to = StaffUserSerializer(read_only=True)
    driver_id = serializers.IntegerField(source="driver.id", read_only=True, default=None)
    plate = serializers.CharField(read_only=True)
    maps_url = serializers.CharField(read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    issue_display = serializers.CharField(source="get_issue_type_display", read_only=True)

    class Meta:
        model = Booking
        fields = (
            "id", "reference", "driver_id", "vehicle", "plate", "contact_name", "contact_phone",
            "contact_email", "issue_type", "issue_display", "description", "tyre_size",
            "location_text", "latitude", "longitude", "status", "status_display", "source",
            "assigned_to", "internal_notes", "created_at", "updated_at", "assigned_at",
            "completed_at", "maps_url",
        )
        read_only_fields = fields


class BookingDetailSerializer(BookingSerializer):
    status_events = BookingStatusEventSerializer(many=True, read_only=True)

    class Meta(BookingSerializer.Meta):
        fields = BookingSerializer.Meta.fields + ("status_events",)
        read_only_fields = fields


class DriverBookingSerializer(BookingSerializer):
    """What the driver's own app may see — internal notes and staff assignment stay in the panel."""

    class Meta(BookingSerializer.Meta):
        fields = tuple(
            f for f in BookingSerializer.Meta.fields if f not in ("internal_notes", "assigned_to")
        )
        read_only_fields = fields


class DriverBookingDetailSerializer(DriverBookingSerializer):
    status_events = BookingStatusEventSerializer(many=True, read_only=True)

    class Meta(DriverBookingSerializer.Meta):
        fields = DriverBookingSerializer.Meta.fields + ("status_events",)
        read_only_fields = fields


class BookingCreateSerializer(serializers.ModelSerializer):
    """Shared by website, app and panel — ``source`` and the actor differ, the payload doesn't."""

    plate = serializers.CharField(max_length=16, required=False, allow_blank=True)

    class Meta:
        model = Booking
        fields = (
            "plate", "contact_name", "contact_phone", "contact_email", "issue_type",
            "description", "tyre_size", "location_text", "latitude", "longitude",
        )

    def validate_contact_phone(self, value):
        return normalise_phone(value)

    def validate_plate(self, value):
        return normalise_plate(value) if value else ""

    def validate(self, attrs):
        if not attrs.get("location_text") and attrs.get("latitude") is None:
            raise serializers.ValidationError(
                {"location_text": ["Give an address or share your location so we can find you."]}
            )
        return attrs

    def resolve_vehicle(self, plate: str) -> Vehicle | None:
        """A failed lookup must not block an emergency call-out — keep the plate, skip the data."""
        if not plate:
            return None
        try:
            return lookup_plate(plate)
        except VehicleLookupError:
            vehicle, _ = Vehicle.objects.get_or_create(plate=plate)
            return vehicle


class BookingStatusUpdateSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=Booking.Status.choices)
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)
    assigned_to_id = serializers.IntegerField(required=False, allow_null=True)


class BookingStaffUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Booking
        fields = ("contact_name", "contact_phone", "contact_email", "issue_type",
                  "description", "tyre_size", "location_text", "latitude", "longitude", "internal_notes")

    def validate_contact_phone(self, value):
        return normalise_phone(value)


class BookingStatsSerializer(serializers.Serializer):
    received = serializers.IntegerField()
    assigned = serializers.IntegerField()
    in_progress = serializers.IntegerField()
    completed_today = serializers.IntegerField()
    open_total = serializers.IntegerField()
