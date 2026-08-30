from rest_framework import serializers

from apps.accounts.phone import normalise_phone
from apps.accounts.serializers import StaffUserSerializer
from apps.billing.serializers import InvoiceSerializer
from apps.drivers.serializers import DriverPublicSerializer
from apps.vehicles.models import ConfirmationPath, Vehicle
from apps.vehicles.plate import normalise_plate
from apps.vehicles.providers import VehicleLookupError
from apps.vehicles.serializers import VehicleSerializer
from apps.vehicles.services import lookup_plate

from .models import Job, JobStatusEvent


class JobStatusEventSerializer(serializers.ModelSerializer):
    actor_name = serializers.CharField(read_only=True)

    class Meta:
        model = JobStatusEvent
        fields = ("id", "from_status", "to_status", "note", "actor_type", "actor_name", "created_at")
        read_only_fields = fields


class _JobBase(serializers.ModelSerializer):
    vehicle = VehicleSerializer(read_only=True)
    plate = serializers.CharField(read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    eta_minutes = serializers.IntegerField(read_only=True)


class JobSerializer(_JobBase):
    """The panel's view. Everything, including what section 4.7 keeps from customers."""

    assigned_staff = StaffUserSerializer(read_only=True)
    driver_name = serializers.CharField(source="driver.name", read_only=True, default="")
    driver_phone = serializers.CharField(source="driver.phone", read_only=True, default="")
    service_area_name = serializers.CharField(source="service_area.name", read_only=True, default="")
    maps_url = serializers.CharField(read_only=True)
    invoice_total = serializers.DecimalField(
        source="invoice.total", max_digits=10, decimal_places=2, read_only=True, default=None
    )

    class Meta:
        model = Job
        fields = (
            "id", "reference", "customer", "vehicle", "plate", "contact_name", "contact_phone",
            "contact_email", "issue_type", "issue_label", "description",
            "tyre_size", "looked_up_tyre_size", "customer_tyre_size", "tyre_confirmation_path",
            "disclaimer_accepted_at", "tyre_corrected_on_site", "tyre_correction_note",
            "location_text", "latitude", "longitude", "location_accuracy_m", "location_source",
            "service_area", "service_area_name", "status", "status_display", "source",
            "driver", "driver_name", "driver_phone", "assigned_staff", "dispatch_rounds",
            "internal_notes", "cancellation_reason", "eta_seconds", "eta_minutes",
            "eta_distance_metres", "eta_updated_at", "invoice_total", "maps_url",
            "created_at", "updated_at", "dispatch_started_at", "assigned_at", "accepted_at",
            "en_route_at", "arrived_at", "started_at", "completed_at", "cancelled_at",
        )
        read_only_fields = fields


class JobDetailSerializer(JobSerializer):
    status_events = JobStatusEventSerializer(many=True, read_only=True)
    invoice = InvoiceSerializer(read_only=True)
    dispatch_attempts = serializers.SerializerMethodField()

    class Meta(JobSerializer.Meta):
        fields = JobSerializer.Meta.fields + ("status_events", "invoice", "dispatch_attempts")
        read_only_fields = fields

    def get_dispatch_attempts(self, job) -> list[dict]:
        from apps.dispatch.serializers import DispatchAttemptSerializer

        return DispatchAttemptSerializer(job.dispatch_attempts.all(), many=True).data


class CustomerJobSerializer(_JobBase):
    """Section 4.6 and 4.7, enforced by omission.

    The customer gets status, an ETA figure, and the driver's first name, photo and van.
    No coordinates for the driver, no phone number, no internal notes, no dispatch history.
    """

    driver = DriverPublicSerializer(read_only=True)
    can_cancel = serializers.SerializerMethodField()
    invoice = InvoiceSerializer(read_only=True)

    class Meta:
        model = Job
        fields = (
            "id", "reference", "vehicle", "plate", "issue_type", "issue_label", "description",
            "tyre_size", "looked_up_tyre_size", "customer_tyre_size", "tyre_confirmation_path",
            "location_text", "latitude", "longitude", "status", "status_display",
            "driver", "eta_seconds", "eta_minutes", "eta_updated_at", "can_cancel", "invoice",
            "created_at", "accepted_at", "en_route_at", "arrived_at", "completed_at", "cancelled_at",
        )
        read_only_fields = fields

    def get_can_cancel(self, job) -> bool:
        from .services import customer_may_cancel

        return customer_may_cancel(job)


class CustomerJobDetailSerializer(CustomerJobSerializer):
    """Progress the customer may see. Dispatching detail is deliberately not in it."""

    timeline = serializers.SerializerMethodField()

    class Meta(CustomerJobSerializer.Meta):
        fields = CustomerJobSerializer.Meta.fields + ("timeline",)
        read_only_fields = fields

    def get_timeline(self, job) -> list[dict]:
        events = [
            event for event in job.status_events.all()
            if event.to_status in Job.CUSTOMER_VISIBLE_STATUSES and event.to_status != event.from_status
        ]
        return [
            {"status": event.to_status, "label": Job.Status(event.to_status).label, "at": event.created_at}
            for event in events
        ]


class DriverJobSerializer(_JobBase):
    """What the technician needs on the road: who, where, and which tyre."""

    maps_url = serializers.CharField(read_only=True)
    invoice = InvoiceSerializer(read_only=True)

    class Meta:
        model = Job
        fields = (
            "id", "reference", "vehicle", "plate", "contact_name", "contact_phone",
            "issue_type", "issue_label", "description", "tyre_size", "looked_up_tyre_size",
            "customer_tyre_size", "tyre_confirmation_path", "tyre_corrected_on_site",
            "location_text", "latitude", "longitude", "location_accuracy_m",
            "status", "status_display", "eta_seconds", "eta_minutes", "maps_url", "invoice",
            "created_at", "assigned_at", "accepted_at", "en_route_at", "arrived_at",
            "started_at", "completed_at",
        )
        read_only_fields = fields


class TyreConfirmationInputSerializer(serializers.Serializer):
    confirmation_path = serializers.ChoiceField(choices=ConfirmationPath.choices)
    tyre_size = serializers.CharField(max_length=32, required=False, allow_blank=True)
    load_index = serializers.CharField(max_length=16, required=False, allow_blank=True)
    speed_rating = serializers.CharField(max_length=8, required=False, allow_blank=True)
    disclaimer_accepted = serializers.BooleanField(default=False)


class JobCreateSerializer(serializers.ModelSerializer):
    """One payload for every surface. The actor and ``source`` differ; the fields do not."""

    plate = serializers.CharField(max_length=16, required=False, allow_blank=True)
    tyre_confirmation = TyreConfirmationInputSerializer(required=False)

    class Meta:
        model = Job
        fields = (
            "plate", "contact_name", "contact_phone", "contact_email", "issue_type",
            "description", "location_text", "latitude", "longitude", "location_accuracy_m",
            "location_source", "tyre_confirmation",
        )

    def validate_contact_phone(self, value):
        return normalise_phone(value)

    def validate_plate(self, value):
        return normalise_plate(value) if value else ""

    def validate_issue_type(self, value):
        from .services import validate_issue_type

        return validate_issue_type(value)

    def validate(self, attrs):
        # Section 4.4: a postcode is not accepted as a substitute for a real position.
        if attrs.get("latitude") is None or attrs.get("longitude") is None:
            raise serializers.ValidationError(
                {"location": ["Share your location so the technician can find you."]}
            )

        confirmation = attrs.get("tyre_confirmation")
        if confirmation and confirmation["confirmation_path"] == ConfirmationPath.OVERRIDDEN:
            if not confirmation.get("disclaimer_accepted"):
                raise serializers.ValidationError(
                    {"tyre_confirmation": {"disclaimer_accepted": [
                        "Acknowledge the responsibility notice to continue."
                    ]}}
                )
            if not confirmation.get("tyre_size"):
                raise serializers.ValidationError(
                    {"tyre_confirmation": {"tyre_size": ["Enter the tyre size fitted to your car."]}}
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


class JobStatusUpdateSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=Job.Status.choices)
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)
    assigned_staff_id = serializers.IntegerField(required=False, allow_null=True)


class JobStaffUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Job
        fields = (
            "contact_name", "contact_phone", "contact_email", "issue_type", "description",
            "tyre_size", "location_text", "latitude", "longitude", "internal_notes",
        )

    def validate_contact_phone(self, value):
        return normalise_phone(value)


class CancelSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=255, required=False, allow_blank=True)


class TyreCorrectionSerializer(serializers.Serializer):
    tyre_size = serializers.CharField(max_length=32)
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)


class JobStatsSerializer(serializers.Serializer):
    submitted = serializers.IntegerField()
    dispatching = serializers.IntegerField()
    assigned = serializers.IntegerField()
    accepted = serializers.IntegerField()
    en_route = serializers.IntegerField()
    arrived = serializers.IntegerField()
    in_progress = serializers.IntegerField()
    unclaimed = serializers.IntegerField()
    completed_today = serializers.IntegerField()
    open_total = serializers.IntegerField()
    drivers_online = serializers.IntegerField()
