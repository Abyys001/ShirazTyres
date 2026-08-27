from rest_framework import serializers

from .models import DeviceToken, Notification


class DeviceTokenSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceToken
        fields = ("id", "token", "platform", "is_active", "created_at")
        read_only_fields = ("id", "is_active", "created_at")


class NotificationSerializer(serializers.ModelSerializer):
    booking_reference = serializers.CharField(source="booking.reference", read_only=True, default="")

    class Meta:
        model = Notification
        fields = (
            "id", "booking", "booking_reference", "channel", "recipient", "subject",
            "status", "error", "created_at", "sent_at",
        )
        read_only_fields = fields
