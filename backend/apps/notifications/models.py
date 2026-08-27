from django.db import models

from apps.accounts.models import Driver, StaffUser


class DeviceToken(models.Model):
    """Push targets. A device belongs to a driver (app) or a staff user (panel/web push)."""

    class Platform(models.TextChoices):
        ANDROID = "android", "Android"
        IOS = "ios", "iOS"
        WEB = "web", "Web"

    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=16, choices=Platform.choices)
    driver = models.ForeignKey(Driver, null=True, blank=True, on_delete=models.CASCADE, related_name="devices")
    staff = models.ForeignKey(StaffUser, null=True, blank=True, on_delete=models.CASCADE, related_name="devices")
    is_active = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-last_seen_at",)
        constraints = [
            models.CheckConstraint(
                condition=models.Q(driver__isnull=False) | models.Q(staff__isnull=False),
                name="device_token_has_owner",
            )
        ]

    def __str__(self):
        return f"{self.platform} device for {self.driver or self.staff}"


class Notification(models.Model):
    """An audit trail — 'was the owner actually told?' has to be answerable after the fact."""

    class Channel(models.TextChoices):
        SMS = "sms", "SMS"
        EMAIL = "email", "Email"
        PUSH = "push", "Push"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        SENT = "sent", "Sent"
        FAILED = "failed", "Failed"

    booking = models.ForeignKey(
        "bookings.Booking", null=True, blank=True, on_delete=models.CASCADE, related_name="notifications"
    )
    channel = models.CharField(max_length=16, choices=Channel.choices)
    recipient = models.CharField(max_length=255)
    subject = models.CharField(max_length=255, blank=True)
    body = models.TextField()
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    provider_message_id = models.CharField(max_length=128, blank=True)
    error = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    sent_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["status", "-created_at"])]

    def __str__(self):
        return f"{self.channel} → {self.recipient} ({self.status})"
