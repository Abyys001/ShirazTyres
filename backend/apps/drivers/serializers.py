from rest_framework import serializers

from apps.accounts.serializers import PhoneField
from apps.geo.models import ServiceArea
from apps.vehicles.plate import normalise_plate

from .models import Driver, DriverDocument, DriverLocation, DriverVehicle


class DriverVehicleSerializer(serializers.ModelSerializer):
    display_plate = serializers.CharField(read_only=True)
    description = serializers.CharField(read_only=True)

    class Meta:
        model = DriverVehicle
        fields = (
            "id", "plate", "display_plate", "description", "make", "model", "colour",
            "year_of_manufacture", "is_primary", "created_at", "updated_at",
        )
        read_only_fields = ("id", "display_plate", "description", "created_at", "updated_at")

    def validate_plate(self, value):
        return normalise_plate(value)


class DriverDocumentSerializer(serializers.ModelSerializer):
    is_expired = serializers.BooleanField(read_only=True)
    days_to_expiry = serializers.IntegerField(read_only=True)
    type_display = serializers.CharField(source="get_document_type_display", read_only=True)

    class Meta:
        model = DriverDocument
        fields = (
            "id", "document_type", "type_display", "file", "reference", "expiry_date",
            "status", "review_note", "reviewed_at", "is_expired", "days_to_expiry",
            "created_at", "updated_at",
        )
        read_only_fields = ("id", "status", "review_note", "reviewed_at", "created_at", "updated_at")


class DriverDocumentSelfSerializer(DriverDocumentSerializer):
    """The driver uploads and sees status, but never edits the outcome or the staff note."""

    class Meta(DriverDocumentSerializer.Meta):
        fields = tuple(f for f in DriverDocumentSerializer.Meta.fields if f != "reference")


class DriverSerializer(serializers.ModelSerializer):
    """Full staff-side view, including everything section 4.7 keeps from customers."""

    phone = PhoneField(max_length=32)
    vehicles = DriverVehicleSerializer(many=True, read_only=True)
    documents = DriverDocumentSerializer(many=True, read_only=True)
    service_area_ids = serializers.PrimaryKeyRelatedField(
        source="service_areas", many=True, queryset=ServiceArea.objects.all(), required=False
    )
    missing_documents = serializers.ListField(child=serializers.CharField(), read_only=True)
    expired_documents = serializers.ListField(child=serializers.CharField(), read_only=True)
    active_jobs = serializers.SerializerMethodField()
    status_display = serializers.CharField(source="get_verification_status_display", read_only=True)

    class Meta:
        model = Driver
        fields = (
            "id", "name", "phone", "email", "photo", "employment_reference",
            "verification_status", "status_display", "verification_note", "approved_at",
            "is_active", "is_online", "went_online_at", "service_area_ids",
            "latitude", "longitude", "location_accuracy_m", "location_updated_at",
            "notes", "vehicles", "documents", "missing_documents", "expired_documents",
            "active_jobs", "created_at", "updated_at", "last_login_at",
        )
        read_only_fields = (
            "id", "verification_status", "approved_at", "is_online", "went_online_at",
            "latitude", "longitude", "location_accuracy_m", "location_updated_at",
            "created_at", "updated_at", "last_login_at",
        )

    def get_active_jobs(self, driver) -> int:
        return driver.active_job_count()

    def validate_phone(self, value):
        queryset = Driver.objects.filter(phone=value)
        if self.instance:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError("A driver with this phone number already exists.")
        return value


class DriverSelfSerializer(serializers.ModelSerializer):
    """What the driver app may read and write about itself."""

    vehicles = DriverVehicleSerializer(many=True, read_only=True)
    documents = DriverDocumentSelfSerializer(many=True, read_only=True)
    missing_documents = serializers.ListField(child=serializers.CharField(), read_only=True)
    status_display = serializers.CharField(source="get_verification_status_display", read_only=True)

    class Meta:
        model = Driver
        fields = (
            "id", "name", "phone", "email", "photo", "verification_status", "status_display",
            "verification_note", "is_online", "vehicles", "documents", "missing_documents",
            "created_at", "last_login_at",
        )
        read_only_fields = (
            "id", "phone", "verification_status", "status_display", "verification_note",
            "is_online", "created_at", "last_login_at",
        )


class DriverPublicSerializer(serializers.ModelSerializer):
    """Exactly what a customer is allowed to see — section 4.6 and 4.7.

    First name, photo and van only. No surname, no phone number, no position.
    """

    first_name = serializers.CharField(read_only=True)
    vehicle_make = serializers.SerializerMethodField()
    vehicle_model = serializers.SerializerMethodField()
    vehicle_colour = serializers.SerializerMethodField()
    vehicle_plate = serializers.SerializerMethodField()

    class Meta:
        model = Driver
        fields = ("first_name", "photo", "vehicle_make", "vehicle_model", "vehicle_colour", "vehicle_plate")
        read_only_fields = fields

    def _vehicle(self, driver):
        if not hasattr(self, "_vehicle_cache"):
            self._vehicle_cache = {}
        if driver.pk not in self._vehicle_cache:
            self._vehicle_cache[driver.pk] = driver.primary_vehicle
        return self._vehicle_cache[driver.pk]

    def get_vehicle_make(self, driver) -> str:
        vehicle = self._vehicle(driver)
        return vehicle.make if vehicle else ""

    def get_vehicle_model(self, driver) -> str:
        vehicle = self._vehicle(driver)
        return vehicle.model if vehicle else ""

    def get_vehicle_colour(self, driver) -> str:
        vehicle = self._vehicle(driver)
        return vehicle.colour if vehicle else ""

    def get_vehicle_plate(self, driver) -> str:
        vehicle = self._vehicle(driver)
        return vehicle.display_plate if vehicle else ""


class DriverOtpVerifySerializer(serializers.Serializer):
    phone = PhoneField(max_length=32)
    code = serializers.CharField(max_length=12)
    name = serializers.CharField(max_length=120, required=False, allow_blank=True)


class OnlineToggleSerializer(serializers.Serializer):
    is_online = serializers.BooleanField()


class LocationPingSerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    accuracy_m = serializers.IntegerField(required=False, allow_null=True, min_value=0)
    speed_kph = serializers.IntegerField(required=False, allow_null=True, min_value=0, max_value=400)
    heading_deg = serializers.IntegerField(required=False, allow_null=True, min_value=0, max_value=359)
    recorded_at = serializers.DateTimeField(required=False)


class LocationBatchSerializer(serializers.Serializer):
    """The app buffers fixes while offline and flushes them when signal returns."""

    points = LocationPingSerializer(many=True, allow_empty=False)


class DriverLocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = DriverLocation
        fields = ("id", "latitude", "longitude", "accuracy_m", "speed_kph", "heading_deg", "recorded_at")
        read_only_fields = fields


class VerificationUpdateSerializer(serializers.Serializer):
    verification_status = serializers.ChoiceField(choices=Driver.Verification.choices)
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)


class DocumentReviewSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=DriverDocument.Status.choices)
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)


class DriverMapSerializer(serializers.ModelSerializer):
    """The panel's live map row — staff may see position, customers may not."""

    vehicle_plate = serializers.SerializerMethodField()
    active_jobs = serializers.SerializerMethodField()

    class Meta:
        model = Driver
        fields = (
            "id", "name", "phone", "is_online", "verification_status", "latitude", "longitude",
            "location_accuracy_m", "location_updated_at", "vehicle_plate", "active_jobs",
        )
        read_only_fields = fields

    def get_vehicle_plate(self, driver) -> str:
        vehicle = driver.primary_vehicle
        return vehicle.display_plate if vehicle else ""

    def get_active_jobs(self, driver) -> int:
        return driver.active_job_count()
