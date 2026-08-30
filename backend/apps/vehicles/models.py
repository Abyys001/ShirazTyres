from django.db import models
from django.utils import timezone

from apps.accounts.models import Customer

from .plate import format_plate


class ConfirmationPath(models.TextChoices):
    """Section 4.3. Which of the two paths the customer took, recorded on every job."""

    CONFIRMED = "confirmed", "Path A — customer confirmed the looked-up specification"
    OVERRIDDEN = "overridden", "Path B — customer supplied their own specification"


class Vehicle(models.Model):
    """One row per registration. DVLA and tyre data are cached here to keep lookups cheap.

    This is the *customer* vehicle cache. A technician's van lives in
    ``drivers.DriverVehicle`` and never touches this table — see specification section 2.
    """

    class TyreSource(models.TextChoices):
        API = "api", "Tyre data API"
        CUSTOMER = "customer", "Confirmed by customer"
        STAFF = "staff", "Entered by staff"
        DRIVER = "driver", "Corrected by driver on site"
        UNKNOWN = "unknown", "Unknown"

    plate = models.CharField(max_length=16, unique=True, db_index=True)
    make = models.CharField(max_length=64, blank=True)
    model = models.CharField(max_length=64, blank=True)
    colour = models.CharField(max_length=32, blank=True)
    fuel_type = models.CharField(max_length=32, blank=True)
    engine_capacity = models.PositiveIntegerField(null=True, blank=True, help_text="cc")
    year_of_manufacture = models.PositiveSmallIntegerField(null=True, blank=True)
    co2_emissions = models.PositiveIntegerField(null=True, blank=True)
    tax_status = models.CharField(max_length=32, blank=True)
    tax_due_date = models.DateField(null=True, blank=True)
    mot_status = models.CharField(max_length=32, blank=True)
    mot_expiry_date = models.DateField(null=True, blank=True)

    tyre_size_front = models.CharField(max_length=32, blank=True, help_text="e.g. 205/55R16")
    tyre_size_rear = models.CharField(max_length=32, blank=True)
    tyre_load_index = models.CharField(max_length=16, blank=True)
    tyre_speed_rating = models.CharField(max_length=8, blank=True)
    tyre_pressure_front_psi = models.PositiveSmallIntegerField(null=True, blank=True)
    tyre_pressure_rear_psi = models.PositiveSmallIntegerField(null=True, blank=True)
    tyre_size_options = models.JSONField(
        default=list, blank=True, help_text="Alternative fitments when the trim is ambiguous."
    )
    tyre_source = models.CharField(max_length=16, choices=TyreSource.choices, default=TyreSource.UNKNOWN)

    dvla_fetched_at = models.DateTimeField(null=True, blank=True)
    tyre_fetched_at = models.DateTimeField(null=True, blank=True)
    lookup_error = models.CharField(max_length=255, blank=True)
    raw_dvla = models.JSONField(default=dict, blank=True)
    raw_tyre = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    customers = models.ManyToManyField(Customer, through="CustomerVehicle", related_name="vehicles")

    class Meta:
        ordering = ("-updated_at",)

    def __str__(self):
        return f"{self.display_plate} {self.make} {self.model}".strip()

    @property
    def display_plate(self):
        return format_plate(self.plate)

    @property
    def description(self):
        parts = [str(self.year_of_manufacture or ""), self.colour, self.make, self.model]
        return " ".join(part for part in parts if part).strip()

    @property
    def has_tyre_data(self) -> bool:
        return bool(self.tyre_size_front)

    @property
    def is_fitment_ambiguous(self) -> bool:
        """More than one fitment on record is exactly the trim ambiguity section 4.3 exists for."""
        return len(self.tyre_size_options or []) > 1

    def is_dvla_fresh(self, ttl_days: int) -> bool:
        if not self.dvla_fetched_at:
            return False
        return (timezone.now() - self.dvla_fetched_at).days < ttl_days

    def is_tyre_fresh(self, ttl_days: int) -> bool:
        if self.tyre_source in {self.TyreSource.CUSTOMER, self.TyreSource.STAFF, self.TyreSource.DRIVER}:
            return True  # A human confirmed it; don't overwrite from the API.
        if not self.tyre_fetched_at:
            return False
        return (timezone.now() - self.tyre_fetched_at).days < ttl_days


class CustomerVehicle(models.Model):
    """A customer's saved car, plus whatever they decided about its tyre specification.

    Section 4.3 requires both figures to survive: what the lookup said, and what the
    customer typed instead. When a technician turns up with a tyre that does not fit,
    this record is what settles who accepted responsibility.
    """

    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name="vehicle_links")
    vehicle = models.ForeignKey(Vehicle, on_delete=models.CASCADE, related_name="customer_links")
    nickname = models.CharField(max_length=64, blank=True)
    is_primary = models.BooleanField(default=False)

    confirmation_path = models.CharField(
        max_length=16, choices=ConfirmationPath.choices, blank=True
    )
    looked_up_tyre_size = models.CharField(
        max_length=32, blank=True, help_text="What the lookup returned at the moment of confirmation."
    )
    customer_tyre_size = models.CharField(
        max_length=32, blank=True, help_text="What the customer entered instead, on path B."
    )
    customer_load_index = models.CharField(max_length=16, blank=True)
    customer_speed_rating = models.CharField(max_length=8, blank=True)
    disclaimer_accepted_at = models.DateTimeField(
        null=True, blank=True, help_text="Path B only: when the responsibility notice was acknowledged."
    )
    confirmed_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["customer", "vehicle"], name="unique_customer_vehicle")
        ]
        ordering = ("-is_primary", "-created_at")

    def __str__(self):
        return f"{self.customer} → {self.vehicle.display_plate}"

    @property
    def effective_tyre_size(self) -> str:
        return self.customer_tyre_size or self.looked_up_tyre_size or self.vehicle.tyre_size_front
