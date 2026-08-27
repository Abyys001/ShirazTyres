from django.db import models
from django.utils import timezone

from apps.accounts.models import Driver

from .plate import format_plate


class Vehicle(models.Model):
    """One row per registration. DVLA and tyre data are cached here to keep lookups cheap."""

    class TyreSource(models.TextChoices):
        API = "api", "Tyre data API"
        DRIVER = "driver", "Confirmed by driver"
        STAFF = "staff", "Entered by staff"
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

    drivers = models.ManyToManyField(Driver, through="DriverVehicle", related_name="vehicles")

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

    def is_dvla_fresh(self, ttl_days: int) -> bool:
        if not self.dvla_fetched_at:
            return False
        return (timezone.now() - self.dvla_fetched_at).days < ttl_days

    def is_tyre_fresh(self, ttl_days: int) -> bool:
        if self.tyre_source in {self.TyreSource.DRIVER, self.TyreSource.STAFF}:
            return True  # A human confirmed it; don't overwrite from the API.
        if not self.tyre_fetched_at:
            return False
        return (timezone.now() - self.tyre_fetched_at).days < ttl_days


class DriverVehicle(models.Model):
    driver = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name="vehicle_links")
    vehicle = models.ForeignKey(Vehicle, on_delete=models.CASCADE, related_name="driver_links")
    nickname = models.CharField(max_length=64, blank=True)
    is_primary = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["driver", "vehicle"], name="unique_driver_vehicle")]
        ordering = ("-is_primary", "-created_at")

    def __str__(self):
        return f"{self.driver} → {self.vehicle.display_plate}"
