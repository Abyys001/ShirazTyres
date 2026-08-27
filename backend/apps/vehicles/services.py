"""Plate lookup: DVLA + tyre fitment, cached in the Vehicle row.

A tyre failure never fails the whole lookup — the shop can still act on make/model, and
the driver can confirm the size by hand.
"""

import logging

from django.conf import settings
from django.utils import timezone

from .models import Vehicle
from .providers import VehicleLookupError, get_dvla_provider, get_tyre_provider

logger = logging.getLogger(__name__)


def lookup_plate(plate: str, *, force_refresh: bool = False) -> Vehicle:
    ttl = settings.VEHICLE_LOOKUP_TTL_DAYS
    vehicle, _ = Vehicle.objects.get_or_create(plate=plate)

    needs_dvla = force_refresh or not vehicle.is_dvla_fresh(ttl)
    needs_tyre = force_refresh or not vehicle.is_tyre_fresh(ttl)
    if not needs_dvla and not needs_tyre:
        return vehicle

    updates: list[str] = []
    errors: list[str] = []

    if needs_dvla:
        try:
            result = get_dvla_provider().fetch(plate)
        except VehicleLookupError as exc:
            if exc.not_found and not vehicle.dvla_fetched_at:
                vehicle.delete()  # Don't keep an empty shell for a plate DVLA doesn't know.
                raise
            errors.append(str(exc))
            logger.warning("vehicle.dvla_failed plate=%s error=%s", plate, exc)
        else:
            for source_field, value in (
                ("make", result.make), ("model", result.model), ("colour", result.colour),
                ("fuel_type", result.fuel_type), ("engine_capacity", result.engine_capacity),
                ("year_of_manufacture", result.year_of_manufacture), ("co2_emissions", result.co2_emissions),
                ("tax_status", result.tax_status), ("tax_due_date", result.tax_due_date),
                ("mot_status", result.mot_status), ("mot_expiry_date", result.mot_expiry_date),
            ):
                setattr(vehicle, source_field, value)
                updates.append(source_field)
            vehicle.raw_dvla = result.raw
            vehicle.dvla_fetched_at = timezone.now()
            updates += ["raw_dvla", "dvla_fetched_at"]

    if needs_tyre:
        try:
            result = get_tyre_provider().fetch(plate)
        except VehicleLookupError as exc:
            errors.append(str(exc))
            logger.warning("vehicle.tyre_failed plate=%s error=%s", plate, exc)
        else:
            vehicle.tyre_size_front = result.size_front
            vehicle.tyre_size_rear = result.size_rear
            vehicle.tyre_load_index = result.load_index
            vehicle.tyre_speed_rating = result.speed_rating
            vehicle.tyre_pressure_front_psi = result.pressure_front_psi
            vehicle.tyre_pressure_rear_psi = result.pressure_rear_psi
            vehicle.tyre_size_options = result.options
            vehicle.tyre_source = Vehicle.TyreSource.API
            vehicle.raw_tyre = result.raw
            vehicle.tyre_fetched_at = timezone.now()
            updates += [
                "tyre_size_front", "tyre_size_rear", "tyre_load_index", "tyre_speed_rating",
                "tyre_pressure_front_psi", "tyre_pressure_rear_psi", "tyre_size_options",
                "tyre_source", "raw_tyre", "tyre_fetched_at",
            ]

    vehicle.lookup_error = "; ".join(errors)[:255]
    updates.append("lookup_error")
    vehicle.save(update_fields=list(dict.fromkeys(updates)))
    return vehicle


def confirm_tyre_size(vehicle: Vehicle, size: str, *, by_staff: bool) -> Vehicle:
    """A human overrides the API when the trim is ambiguous — and it stops being refreshed."""
    vehicle.tyre_size_front = size
    vehicle.tyre_size_rear = size
    vehicle.tyre_source = Vehicle.TyreSource.STAFF if by_staff else Vehicle.TyreSource.DRIVER
    vehicle.tyre_fetched_at = timezone.now()
    vehicle.save(update_fields=["tyre_size_front", "tyre_size_rear", "tyre_source", "tyre_fetched_at"])
    return vehicle
