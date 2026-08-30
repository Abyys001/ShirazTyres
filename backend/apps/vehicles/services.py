"""Plate lookup: DVLA + tyre fitment, cached in the Vehicle row.

A tyre failure never fails the whole lookup — the shop can still act on make/model, and
section 4.3's confirmation step lets the customer supply the size by hand.
"""

import logging

from django.conf import settings
from django.utils import timezone

from .models import ConfirmationPath, CustomerVehicle, Vehicle
from .providers import DvlaResult, VehicleLookupError, get_dvla_provider, get_tyre_provider

logger = logging.getLogger(__name__)


def fetch_dvla_only(plate: str) -> DvlaResult:
    """Straight to DVLA with no ``Vehicle`` row created.

    Used when registering a technician's van: section 2 keeps driver vehicles out of the
    customer vehicle table, and a van is registered once, so caching buys nothing.
    """
    return get_dvla_provider().fetch(plate)


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


def confirm_tyre_size(vehicle: Vehicle, size: str, *, source: str) -> Vehicle:
    """A human overrides the API when the trim is ambiguous — and it stops being refreshed."""
    if source not in Vehicle.TyreSource.values:
        raise ValueError(f"Unknown tyre source: {source}")
    vehicle.tyre_size_front = size
    vehicle.tyre_size_rear = size
    vehicle.tyre_source = source
    vehicle.tyre_fetched_at = timezone.now()
    vehicle.save(update_fields=["tyre_size_front", "tyre_size_rear", "tyre_source", "tyre_fetched_at"])
    return vehicle


def record_confirmation(
    link: CustomerVehicle,
    *,
    path: str,
    looked_up_size: str,
    customer_size: str = "",
    load_index: str = "",
    speed_rating: str = "",
    disclaimer_accepted: bool = False,
) -> CustomerVehicle:
    """Section 4.3, written down. Path B without the acknowledgement is not a valid path B."""
    from rest_framework.exceptions import ValidationError

    if path not in ConfirmationPath.values:
        raise ValidationError({"confirmation_path": ["Unknown confirmation path."]})

    now = timezone.now()
    link.confirmation_path = path
    link.looked_up_tyre_size = looked_up_size
    link.confirmed_at = now

    if path == ConfirmationPath.OVERRIDDEN:
        if not disclaimer_accepted:
            raise ValidationError(
                {"disclaimer_accepted": ["Acknowledge the responsibility notice to continue."]}
            )
        if not customer_size:
            raise ValidationError({"customer_tyre_size": ["Enter the tyre size fitted to your car."]})
        link.customer_tyre_size = customer_size
        link.customer_load_index = load_index
        link.customer_speed_rating = speed_rating
        link.disclaimer_accepted_at = now
        confirm_tyre_size(link.vehicle, customer_size, source=Vehicle.TyreSource.CUSTOMER)
    else:
        link.customer_tyre_size = ""
        link.customer_load_index = ""
        link.customer_speed_rating = ""
        link.disclaimer_accepted_at = None

    link.save(
        update_fields=[
            "confirmation_path", "looked_up_tyre_size", "customer_tyre_size",
            "customer_load_index", "customer_speed_rating", "disclaimer_accepted_at", "confirmed_at",
        ]
    )
    return link
