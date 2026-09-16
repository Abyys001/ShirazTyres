"""The field technician and everything that decides whether they may be dispatched."""

from django.db import models
from django.utils import timezone

from apps.accounts.models import StaffUser
from apps.geo.models import ServiceArea
from apps.vehicles.plate import format_plate


def driver_photo_path(instance, filename: str) -> str:
    return f"drivers/{instance.pk or 'new'}/photo/{filename}"


def document_path(instance, filename: str) -> str:
    return f"drivers/{instance.driver_id}/documents/{instance.document_type}/{filename}"


class Driver(models.Model):
    """A ShirazTyres employee technician. Never the motorist — see specification section 2."""

    class Verification(models.TextChoices):
        PENDING = "pending", "Pending review"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"
        SUSPENDED = "suspended", "Suspended"

    phone = models.CharField(max_length=20, unique=True, db_index=True)
    name = models.CharField(max_length=120, blank=True)
    email = models.EmailField(blank=True)
    photo = models.ImageField(upload_to=driver_photo_path, blank=True)
    employment_reference = models.CharField(
        max_length=64, blank=True, help_text="The business's own staff reference."
    )

    verification_status = models.CharField(
        max_length=16, choices=Verification.choices, default=Verification.PENDING, db_index=True
    )
    verification_note = models.CharField(max_length=255, blank=True)
    approved_at = models.DateTimeField(null=True, blank=True)
    approved_by = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="approved_drivers"
    )

    is_active = models.BooleanField(default=True)
    is_online = models.BooleanField(
        default=False, db_index=True, help_text="Set by the driver app. Tracking runs only while true."
    )
    went_online_at = models.DateTimeField(null=True, blank=True)

    service_areas = models.ManyToManyField(ServiceArea, blank=True, related_name="drivers")

    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_accuracy_m = models.PositiveIntegerField(null=True, blank=True)
    location_updated_at = models.DateTimeField(null=True, blank=True)

    notes = models.TextField(blank=True, help_text="Internal notes, never shown to a customer.")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_login_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("name", "phone")

    def __str__(self):
        return f"{self.name or 'Driver'} ({self.phone})"

    @property
    def is_authenticated(self):
        """Lets DRF permission classes treat a Driver like an authenticated principal."""
        return True

    @property
    def is_approved(self) -> bool:
        return self.verification_status == self.Verification.APPROVED

    @property
    def first_name(self) -> str:
        """All the customer is given — section 4.6."""
        return (self.name or "").split(" ")[0]

    @property
    def has_location(self) -> bool:
        return self.latitude is not None and self.longitude is not None

    @property
    def coordinates(self) -> tuple[float, float] | None:
        return (float(self.latitude), float(self.longitude)) if self.has_location else None

    @property
    def primary_vehicle(self):
        return self.vehicles.filter(is_primary=True).first() or self.vehicles.first()

    def active_job_count(self) -> int:
        from apps.bookings.models import Job

        return Job.objects.filter(driver=self, status__in=Job.DRIVER_BUSY_STATUSES).count()

    def missing_documents(self) -> list[str]:
        from apps.configuration.services import get_setting

        required = set(get_setting("drivers.required_documents") or [])
        approved = set(
            self.documents.filter(status=DriverDocument.Status.APPROVED).values_list(
                "document_type", flat=True
            )
        )
        return sorted(required - approved)

    def expired_documents(self) -> list[str]:
        today = timezone.localdate()
        return sorted(
            self.documents.filter(expiry_date__lt=today).values_list("document_type", flat=True)
        )


class DriverVehicle(models.Model):
    """The technician's service van.

    Deliberately its own table with its own make/model/colour rather than a link to
    ``vehicles.Vehicle``: specification section 2 requires the two vehicle concepts stay
    apart, and a van's details are tied to this driver's insurance, not to a plate cache
    shared with customers.
    """

    driver = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name="vehicles")
    plate = models.CharField(max_length=16, db_index=True)
    make = models.CharField(max_length=64, blank=True)
    model = models.CharField(max_length=64, blank=True)
    colour = models.CharField(max_length=32, blank=True)
    year_of_manufacture = models.PositiveSmallIntegerField(null=True, blank=True)
    is_primary = models.BooleanField(default=True)

    # Kept on the van rather than looked up on every screen: a technician in a
    # basement car park still gets to see when their MOT runs out.
    fuel_type = models.CharField(max_length=32, blank=True)
    engine_capacity = models.PositiveIntegerField(null=True, blank=True, help_text="cc")
    co2_emissions = models.PositiveIntegerField(null=True, blank=True)
    tax_status = models.CharField(max_length=32, blank=True)
    tax_due_date = models.DateField(null=True, blank=True)
    mot_status = models.CharField(max_length=32, blank=True)
    mot_expiry_date = models.DateField(null=True, blank=True)
    dvla_fetched_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-is_primary", "-created_at")
        constraints = [
            models.UniqueConstraint(fields=["driver", "plate"], name="unique_driver_vehicle_plate")
        ]

    def __str__(self):
        return f"{self.display_plate} ({self.driver})"

    @property
    def display_plate(self) -> str:
        return format_plate(self.plate)

    @property
    def description(self) -> str:
        return " ".join(part for part in (self.colour, self.make, self.model) if part)

    @property
    def mot_days_remaining(self) -> int | None:
        """Negative once it has lapsed, which is the number that matters."""
        if not self.mot_expiry_date:
            return None
        return (self.mot_expiry_date - timezone.localdate()).days

    @property
    def tax_days_remaining(self) -> int | None:
        if not self.tax_due_date:
            return None
        return (self.tax_due_date - timezone.localdate()).days


class DriverDocument(models.Model):
    """Insurance, licence and MOT. Never visible to a customer — section 4.7."""

    class DocumentType(models.TextChoices):
        INSURANCE = "insurance", "Insurance certificate"
        LICENCE = "licence", "Driving licence"
        MOT = "mot", "MOT certificate"
        RIGHT_TO_WORK = "right_to_work", "Right to work"
        OTHER = "other", "Other"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending review"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"

    driver = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name="documents")
    document_type = models.CharField(max_length=24, choices=DocumentType.choices)
    file = models.FileField(upload_to=document_path)
    reference = models.CharField(
        max_length=64, blank=True, help_text="Policy or certificate number. Staff-only."
    )
    expiry_date = models.DateField(db_index=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    review_note = models.CharField(max_length=255, blank=True)
    reviewed_by = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="reviewed_documents"
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    expiry_warned_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("driver", "document_type", "-created_at")
        indexes = [models.Index(fields=["status", "expiry_date"])]

    def __str__(self):
        return f"{self.get_document_type_display()} for {self.driver} (expires {self.expiry_date})"

    @property
    def is_expired(self) -> bool:
        return self.expiry_date < timezone.localdate()

    @property
    def days_to_expiry(self) -> int:
        return (self.expiry_date - timezone.localdate()).days


class DriverLocation(models.Model):
    """Time-series positions. Written only while the driver is online, and purged on the
    configured retention schedule — see the compliance note in section 18."""

    driver = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name="locations")
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    accuracy_m = models.PositiveIntegerField(null=True, blank=True)
    speed_kph = models.PositiveSmallIntegerField(null=True, blank=True)
    heading_deg = models.PositiveSmallIntegerField(null=True, blank=True)
    recorded_at = models.DateTimeField(db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-recorded_at",)
        indexes = [models.Index(fields=["driver", "-recorded_at"])]

    def __str__(self):
        return f"{self.driver} @ {self.latitude},{self.longitude}"
