from rest_framework import serializers

from apps.drivers.serializers import DriverPublicSerializer

from .models import DispatchAttempt, DispatchOffer


class DispatchOfferSerializer(serializers.ModelSerializer):
    driver_name = serializers.CharField(source="driver.name", read_only=True)
    driver_phone = serializers.CharField(source="driver.phone", read_only=True)
    eta_minutes = serializers.SerializerMethodField()

    class Meta:
        model = DispatchOffer
        fields = (
            "id", "driver", "driver_name", "driver_phone", "rank", "eta_seconds",
            "eta_minutes", "distance_metres", "state", "reason", "offered_at", "responded_at",
        )
        read_only_fields = fields

    def get_eta_minutes(self, offer) -> int | None:
        return None if offer.eta_seconds is None else max(1, round(offer.eta_seconds / 60))


class DispatchAttemptSerializer(serializers.ModelSerializer):
    offers = DispatchOfferSerializer(many=True, read_only=True)
    mode_display = serializers.CharField(source="get_mode_display", read_only=True)
    outcome_display = serializers.CharField(source="get_outcome_display", read_only=True)

    class Meta:
        model = DispatchAttempt
        fields = (
            "id", "round_number", "mode", "mode_display", "outcome", "outcome_display",
            "radius_km", "timeout_seconds", "candidates_considered", "note",
            "started_at", "expires_at", "resolved_at", "offers",
        )
        read_only_fields = fields


class DriverOfferSerializer(serializers.ModelSerializer):
    """What the driver app shows in its offer list. The job payload is attached by the view."""

    eta_minutes = serializers.SerializerMethodField()
    expires_at = serializers.DateTimeField(source="attempt.expires_at", read_only=True)
    mode = serializers.CharField(source="attempt.mode", read_only=True)

    class Meta:
        model = DispatchOffer
        fields = ("id", "rank", "eta_seconds", "eta_minutes", "distance_metres", "state",
                  "mode", "offered_at", "expires_at")
        read_only_fields = fields

    def get_eta_minutes(self, offer) -> int | None:
        return None if offer.eta_seconds is None else max(1, round(offer.eta_seconds / 60))


class RejectSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=255, required=False, allow_blank=True)


class ManualAssignSerializer(serializers.Serializer):
    driver_id = serializers.IntegerField()


class CandidatePreviewSerializer(serializers.Serializer):
    """The panel's 'who would get this?' view, without actually dispatching."""

    driver_id = serializers.IntegerField()
    name = serializers.CharField()
    phone = serializers.CharField()
    eta_seconds = serializers.IntegerField()
    eta_minutes = serializers.IntegerField()
    distance_metres = serializers.IntegerField()


class AssignedDriverSerializer(DriverPublicSerializer):
    """Alias kept so the customer-facing job serializer reads plainly."""
