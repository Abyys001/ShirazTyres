"""Driver onboarding, verification, availability and location.

Everything that can take a driver in or out of the dispatch pool lives here, so
"why did this driver not get offered the job?" has exactly one place to look.
"""

import logging

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.configuration.services import get_setting

from .models import Driver, DriverDocument, DriverLocation

logger = logging.getLogger(__name__)


def get_or_create_driver(phone: str, name: str = "") -> tuple[Driver, bool]:
    driver, created = Driver.objects.get_or_create(phone=phone, defaults={"name": name})
    updates = []
    if name and not driver.name:
        driver.name = name
        updates.append("name")
    driver.last_login_at = timezone.now()
    updates.append("last_login_at")
    driver.save(update_fields=updates)
    return driver, created


def set_verification(
    driver: Driver, status: str, *, by=None, note: str = ""
) -> Driver:
    from apps.notifications.tasks import notify_driver_verification

    if status not in Driver.Verification.values:
        raise ValidationError({"verification_status": ["Unknown verification status."]})

    if status == Driver.Verification.APPROVED:
        missing = driver.missing_documents()
        if missing:
            raise ValidationError(
                {"verification_status": [
                    "Approve the required documents first — still outstanding: "
                    + ", ".join(missing) + "."
                ]}
            )

    previous = driver.verification_status
    driver.verification_status = status
    driver.verification_note = note
    updates = ["verification_status", "verification_note"]

    if status == Driver.Verification.APPROVED:
        driver.approved_at = timezone.now()
        driver.approved_by = by
        updates += ["approved_at", "approved_by"]
    if status in {Driver.Verification.SUSPENDED, Driver.Verification.REJECTED}:
        driver.is_online = False
        updates.append("is_online")

    driver.save(update_fields=updates)
    logger.info("driver.verification driver=%s %s->%s", driver.pk, previous, status)
    transaction.on_commit(lambda: notify_driver_verification.delay(driver.pk, status, note))
    return driver


def set_online(driver: Driver, online: bool) -> Driver:
    """Section 11.1: tracking runs only while the driver is toggled online."""
    if online and not driver.is_approved:
        raise ValidationError({"is_online": ["Your account is not approved for dispatch yet."]})

    if online and not driver.is_online:
        driver.went_online_at = timezone.now()
    if not online:
        # The last known position is not kept once the shift ends.
        driver.latitude = None
        driver.longitude = None
        driver.location_accuracy_m = None
        driver.location_updated_at = None

    driver.is_online = online
    driver.save(
        update_fields=[
            "is_online", "went_online_at", "latitude", "longitude",
            "location_accuracy_m", "location_updated_at",
        ]
    )
    logger.info("driver.online driver=%s online=%s", driver.pk, online)
    return driver


def record_location(
    driver: Driver,
    *,
    latitude,
    longitude,
    accuracy_m=None,
    speed_kph=None,
    heading_deg=None,
    recorded_at=None,
) -> DriverLocation:
    """Appends to the time series and denormalises the latest fix onto the driver."""
    if not driver.is_online:
        raise ValidationError({"is_online": ["Go online before sending location updates."]})

    recorded_at = recorded_at or timezone.now()
    point = DriverLocation.objects.create(
        driver=driver,
        latitude=latitude,
        longitude=longitude,
        accuracy_m=accuracy_m,
        speed_kph=speed_kph,
        heading_deg=heading_deg,
        recorded_at=recorded_at,
    )

    # An out-of-order fix must not overwrite a newer one.
    if driver.location_updated_at is None or recorded_at >= driver.location_updated_at:
        driver.latitude = latitude
        driver.longitude = longitude
        driver.location_accuracy_m = accuracy_m
        driver.location_updated_at = recorded_at
        driver.save(
            update_fields=["latitude", "longitude", "location_accuracy_m", "location_updated_at"]
        )
        transaction.on_commit(lambda: _publish_location(driver))

    return point


def _publish_location(driver: Driver) -> None:
    """Panel live map, then every ETA that depends on where this driver now is."""
    from apps.dispatch.tasks import refresh_etas_for_driver
    from apps.realtime.publish import publish_driver_location

    publish_driver_location(driver)
    refresh_etas_for_driver.delay(driver.pk)


def review_document(document: DriverDocument, status: str, *, by=None, note: str = "") -> DriverDocument:
    if status not in DriverDocument.Status.values:
        raise ValidationError({"status": ["Unknown document status."]})

    document.status = status
    document.review_note = note
    document.reviewed_by = by
    document.reviewed_at = timezone.now()
    document.save(update_fields=["status", "review_note", "reviewed_by", "reviewed_at"])

    # An approval can complete the required set, but never auto-approves the driver —
    # section 8.2 keeps that an administrator's decision.
    logger.info("driver.document_reviewed document=%s status=%s", document.pk, status)
    return document


def suspend_for_expired_documents(driver: Driver, expired: list[str]) -> Driver:
    return set_verification(
        driver,
        Driver.Verification.SUSPENDED,
        note="Automatically suspended — expired: " + ", ".join(expired) + ".",
    )


def dispatchable_queryset():
    """Section 6.4: online, verified, not already on a job, in an active service area.

    The concurrency cap is applied by the caller against ``active_job_count`` because it
    is a configurable number, not a fixed 'not already on a job'.
    """
    return Driver.objects.filter(
        is_active=True,
        is_online=True,
        verification_status=Driver.Verification.APPROVED,
        latitude__isnull=False,
        longitude__isnull=False,
    )


def has_capacity(driver: Driver) -> bool:
    return driver.active_job_count() < max(1, int(get_setting("drivers.max_concurrent_jobs")))
