import secrets
import string

from django.db import models

from apps.accounts.models import Driver, StaffUser
from apps.vehicles.models import Vehicle

_REFERENCE_ALPHABET = string.ascii_uppercase + string.digits


def generate_reference() -> str:
    return "ST-" + "".join(secrets.choice(_REFERENCE_ALPHABET) for _ in range(6))


class Booking(models.Model):
    class Status(models.TextChoices):
        RECEIVED = "received", "Received"
        ASSIGNED = "assigned", "Assigned"
        IN_PROGRESS = "in_progress", "In progress"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    class Issue(models.TextChoices):
        PUNCTURE = "puncture", "Puncture"
        BLOWOUT = "blowout", "Blowout"
        TYRE_DAMAGE = "tyre_damage", "Tyre damage"
        WHEEL_CHANGE = "wheel_change", "Wheel change"
        OTHER = "other", "Other"

    class Source(models.TextChoices):
        WEBSITE = "website", "Website"
        APP = "app", "Mobile app"
        PANEL = "panel", "Admin panel"
        PHONE = "phone", "Phone call"

    TERMINAL_STATUSES = {Status.COMPLETED, Status.CANCELLED}
    ALLOWED_TRANSITIONS = {
        Status.RECEIVED: {Status.ASSIGNED, Status.IN_PROGRESS, Status.CANCELLED},
        Status.ASSIGNED: {Status.IN_PROGRESS, Status.RECEIVED, Status.CANCELLED},
        Status.IN_PROGRESS: {Status.COMPLETED, Status.CANCELLED},
        Status.COMPLETED: set(),
        Status.CANCELLED: set(),
    }

    reference = models.CharField(max_length=12, unique=True, default=generate_reference, editable=False)
    driver = models.ForeignKey(
        Driver, null=True, blank=True, on_delete=models.SET_NULL, related_name="bookings"
    )
    vehicle = models.ForeignKey(
        Vehicle, null=True, blank=True, on_delete=models.SET_NULL, related_name="bookings"
    )
    # Denormalised so a phone-in booking works with no Driver record at all.
    contact_name = models.CharField(max_length=120)
    contact_phone = models.CharField(max_length=20)
    contact_email = models.EmailField(blank=True)

    issue_type = models.CharField(max_length=24, choices=Issue.choices, default=Issue.TYRE_DAMAGE)
    description = models.TextField(blank=True)
    tyre_size = models.CharField(max_length=32, blank=True, help_text="Snapshot at the time of the call-out.")

    location_text = models.CharField(max_length=255)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    status = models.CharField(max_length=16, choices=Status.choices, default=Status.RECEIVED, db_index=True)
    source = models.CharField(max_length=16, choices=Source.choices, default=Source.WEBSITE)
    assigned_to = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="assigned_bookings"
    )
    created_by_staff = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="created_bookings"
    )
    internal_notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    assigned_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["status", "-created_at"])]

    def __str__(self):
        return f"{self.reference} — {self.get_issue_type_display()} ({self.get_status_display()})"

    @property
    def is_open(self):
        return self.status not in self.TERMINAL_STATUSES

    @property
    def plate(self):
        return self.vehicle.display_plate if self.vehicle else ""

    def can_transition_to(self, new_status: str) -> bool:
        return new_status in self.ALLOWED_TRANSITIONS[self.Status(self.status)]

    def maps_url(self) -> str:
        if self.latitude is not None and self.longitude is not None:
            return f"https://www.google.com/maps/search/?api=1&query={self.latitude},{self.longitude}"
        return f"https://www.google.com/maps/search/?api=1&query={self.location_text.replace(' ', '+')}"


class BookingStatusEvent(models.Model):
    booking = models.ForeignKey(Booking, on_delete=models.CASCADE, related_name="status_events")
    from_status = models.CharField(max_length=16, blank=True)
    to_status = models.CharField(max_length=16)
    note = models.CharField(max_length=255, blank=True)
    changed_by = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="booking_changes"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("created_at",)

    def __str__(self):
        return f"{self.booking.reference}: {self.from_status or '—'} → {self.to_status}"
