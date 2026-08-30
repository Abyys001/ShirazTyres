"""The job: one motorist, one damaged tyre, one technician.

The app package is still called ``bookings`` for migration continuity; everything the
specification names a *job* is a ``Job`` here.
"""

import secrets
import string

from django.db import models

from apps.accounts.models import Customer, StaffUser
from apps.drivers.models import Driver
from apps.geo.models import ServiceArea
from apps.vehicles.models import ConfirmationPath, CustomerVehicle, Vehicle

_REFERENCE_ALPHABET = string.ascii_uppercase + string.digits


def generate_reference() -> str:
    return "ST-" + "".join(secrets.choice(_REFERENCE_ALPHABET) for _ in range(6))


class Job(models.Model):
    """Specification section 5. Every status change goes through
    ``apps.bookings.services.transition_job`` so history and notifications never drift."""

    class Status(models.TextChoices):
        SUBMITTED = "submitted", "Submitted"
        DISPATCHING = "dispatching", "Dispatching"
        ASSIGNED = "assigned", "Assigned"
        ACCEPTED = "accepted", "Accepted"
        EN_ROUTE = "en_route", "En route"
        ARRIVED = "arrived", "Arrived"
        IN_PROGRESS = "in_progress", "In progress"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"
        UNCLAIMED = "unclaimed", "Unclaimed"

    class Source(models.TextChoices):
        WEBSITE = "website", "Customer website"
        APP = "app", "Customer app"
        PANEL = "panel", "Owner panel"
        PHONE = "phone", "Phone call"

    class LocationSource(models.TextChoices):
        DEVICE = "device", "Native device location"
        BROWSER = "browser", "Browser geolocation"
        PIN = "pin", "Map pin"
        STAFF = "staff", "Entered by staff"

    TERMINAL_STATUSES = frozenset({Status.COMPLETED, Status.CANCELLED})

    #: Statuses in which a driver counts against the concurrency cap.
    DRIVER_BUSY_STATUSES = frozenset(
        {Status.ASSIGNED, Status.ACCEPTED, Status.EN_ROUTE, Status.ARRIVED, Status.IN_PROGRESS}
    )

    #: Statuses the customer surfaces are allowed to render — section 5's visibility column.
    CUSTOMER_VISIBLE_STATUSES = frozenset(
        {
            Status.SUBMITTED, Status.DISPATCHING, Status.ACCEPTED, Status.EN_ROUTE,
            Status.ARRIVED, Status.IN_PROGRESS, Status.COMPLETED, Status.CANCELLED,
        }
    )

    ALLOWED_TRANSITIONS: dict[str, set[str]] = {
        Status.SUBMITTED: {Status.DISPATCHING, Status.ASSIGNED, Status.CANCELLED},
        Status.DISPATCHING: {Status.ASSIGNED, Status.UNCLAIMED, Status.CANCELLED},
        # Back to dispatching is the rejection path — section 6.3.
        Status.ASSIGNED: {Status.ACCEPTED, Status.DISPATCHING, Status.UNCLAIMED, Status.CANCELLED},
        Status.ACCEPTED: {Status.EN_ROUTE, Status.DISPATCHING, Status.CANCELLED},
        Status.EN_ROUTE: {Status.ARRIVED, Status.DISPATCHING, Status.CANCELLED},
        Status.ARRIVED: {Status.IN_PROGRESS, Status.CANCELLED},
        Status.IN_PROGRESS: {Status.COMPLETED, Status.CANCELLED},
        Status.COMPLETED: set(),
        Status.CANCELLED: set(),
        Status.UNCLAIMED: {Status.DISPATCHING, Status.ASSIGNED, Status.CANCELLED},
    }

    reference = models.CharField(max_length=12, unique=True, default=generate_reference, editable=False)

    customer = models.ForeignKey(
        Customer, null=True, blank=True, on_delete=models.SET_NULL, related_name="jobs"
    )
    vehicle = models.ForeignKey(
        Vehicle, null=True, blank=True, on_delete=models.SET_NULL, related_name="jobs"
    )
    customer_vehicle = models.ForeignKey(
        CustomerVehicle, null=True, blank=True, on_delete=models.SET_NULL, related_name="jobs"
    )

    # Denormalised so a phone-in job works with no Customer record at all.
    contact_name = models.CharField(max_length=120)
    contact_phone = models.CharField(max_length=20)
    contact_email = models.EmailField(blank=True)

    issue_type = models.CharField(max_length=32, help_text="A value from the configured issue list.")
    issue_label = models.CharField(max_length=64, blank=True, help_text="Label at the time of submission.")
    description = models.TextField(blank=True)

    # --- Tyre specification, section 4.3 -----------------------------------
    tyre_size = models.CharField(max_length=32, blank=True, help_text="The figure the van is loaded from.")
    looked_up_tyre_size = models.CharField(max_length=32, blank=True)
    customer_tyre_size = models.CharField(max_length=32, blank=True)
    tyre_confirmation_path = models.CharField(
        max_length=16, choices=ConfirmationPath.choices, blank=True
    )
    disclaimer_accepted_at = models.DateTimeField(null=True, blank=True)
    tyre_corrected_on_site = models.BooleanField(default=False)
    tyre_correction_note = models.CharField(max_length=255, blank=True)

    # --- Location, section 4.4 ---------------------------------------------
    location_text = models.CharField(max_length=255, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_accuracy_m = models.PositiveIntegerField(null=True, blank=True)
    location_source = models.CharField(
        max_length=16, choices=LocationSource.choices, default=LocationSource.BROWSER
    )
    service_area = models.ForeignKey(
        ServiceArea, null=True, blank=True, on_delete=models.SET_NULL, related_name="jobs"
    )

    status = models.CharField(max_length=16, choices=Status.choices, default=Status.SUBMITTED, db_index=True)
    source = models.CharField(max_length=16, choices=Source.choices, default=Source.WEBSITE)

    driver = models.ForeignKey(
        Driver, null=True, blank=True, on_delete=models.SET_NULL, related_name="jobs"
    )
    assigned_staff = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="assigned_jobs"
    )
    created_by_staff = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="created_jobs"
    )

    dispatch_rounds = models.PositiveSmallIntegerField(default=0)
    internal_notes = models.TextField(blank=True)
    cancellation_reason = models.CharField(max_length=255, blank=True)

    # --- ETA, section 4.6 ---------------------------------------------------
    eta_seconds = models.PositiveIntegerField(null=True, blank=True)
    eta_distance_metres = models.PositiveIntegerField(null=True, blank=True)
    eta_updated_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    dispatch_started_at = models.DateTimeField(null=True, blank=True)
    assigned_at = models.DateTimeField(null=True, blank=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    en_route_at = models.DateTimeField(null=True, blank=True)
    arrived_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            models.Index(fields=["status", "-created_at"]),
            models.Index(fields=["driver", "status"]),
        ]

    def __str__(self):
        return f"{self.reference} — {self.issue_label or self.issue_type} ({self.get_status_display()})"

    @property
    def is_open(self) -> bool:
        return self.status not in self.TERMINAL_STATUSES

    @property
    def is_dispatchable(self) -> bool:
        return self.status in {self.Status.SUBMITTED, self.Status.DISPATCHING, self.Status.UNCLAIMED}

    @property
    def plate(self) -> str:
        return self.vehicle.display_plate if self.vehicle else ""

    @property
    def coordinates(self) -> tuple[float, float] | None:
        if self.latitude is None or self.longitude is None:
            return None
        return float(self.latitude), float(self.longitude)

    @property
    def eta_minutes(self) -> int | None:
        return None if self.eta_seconds is None else max(1, round(self.eta_seconds / 60))

    def can_transition_to(self, new_status: str) -> bool:
        return new_status in self.ALLOWED_TRANSITIONS[self.Status(self.status)]

    def maps_url(self) -> str:
        if self.latitude is not None and self.longitude is not None:
            return f"https://www.google.com/maps/search/?api=1&query={self.latitude},{self.longitude}"
        return f"https://www.google.com/maps/search/?api=1&query={self.location_text.replace(' ', '+')}"


class JobStatusEvent(models.Model):
    """Why a job is where it is. Written by ``transition_job``, never by hand."""

    class Actor(models.TextChoices):
        CUSTOMER = "customer", "Customer"
        DRIVER = "driver", "Driver"
        STAFF = "staff", "Staff"
        SYSTEM = "system", "System"

    job = models.ForeignKey(Job, on_delete=models.CASCADE, related_name="status_events")
    from_status = models.CharField(max_length=16, blank=True)
    to_status = models.CharField(max_length=16)
    note = models.CharField(max_length=255, blank=True)
    actor_type = models.CharField(max_length=16, choices=Actor.choices, default=Actor.SYSTEM)
    changed_by_staff = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="job_changes"
    )
    changed_by_driver = models.ForeignKey(
        Driver, null=True, blank=True, on_delete=models.SET_NULL, related_name="job_changes"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("created_at",)

    def __str__(self):
        return f"{self.job.reference}: {self.from_status or '—'} → {self.to_status}"

    @property
    def actor_name(self) -> str:
        if self.changed_by_staff:
            return self.changed_by_staff.name
        if self.changed_by_driver:
            return self.changed_by_driver.name
        return self.get_actor_type_display()
