"""Scheduled compliance work: expiry warnings, automatic suspension, location retention."""

import logging
from datetime import timedelta

from celery import shared_task
from django.utils import timezone

from apps.configuration.services import get_setting

from .models import Driver, DriverDocument, DriverLocation
from .services import suspend_for_expired_documents

logger = logging.getLogger(__name__)


@shared_task
def warn_expiring_documents() -> int:
    """Section 8.3 — the owner is warned before a document lapses, once per document."""
    from apps.notifications.tasks import notify_document_expiring

    warn_days = int(get_setting("drivers.expiry_warning_days"))
    today = timezone.localdate()
    horizon = today + timedelta(days=warn_days)

    documents = DriverDocument.objects.filter(
        expiry_date__lte=horizon,
        expiry_date__gte=today,
        expiry_warned_at__isnull=True,
        status=DriverDocument.Status.APPROVED,
    ).select_related("driver")

    warned = 0
    for document in documents:
        notify_document_expiring.delay(document.pk)
        document.expiry_warned_at = timezone.now()
        document.save(update_fields=["expiry_warned_at"])
        warned += 1

    if warned:
        logger.info("drivers.expiry_warnings sent=%s", warned)
    return warned


@shared_task
def suspend_drivers_with_expired_documents() -> int:
    """Section 8.3 — insurance lapsing takes a driver out of the pool automatically."""
    if not get_setting("drivers.suspend_on_expiry"):
        return 0

    today = timezone.localdate()
    required = set(get_setting("drivers.required_documents") or [])
    driver_ids = set(
        DriverDocument.objects.filter(expiry_date__lt=today, document_type__in=required)
        .values_list("driver_id", flat=True)
    )

    suspended = 0
    for driver in Driver.objects.filter(
        pk__in=driver_ids, verification_status=Driver.Verification.APPROVED
    ):
        expired = driver.expired_documents()
        if not expired:
            continue
        suspend_for_expired_documents(driver, expired)
        suspended += 1

    if suspended:
        logger.warning("drivers.auto_suspended count=%s", suspended)
    return suspended


@shared_task
def purge_driver_locations() -> int:
    """UK GDPR: employee tracking data is kept for the configured period and no longer."""
    days = int(get_setting("drivers.location_retention_days"))
    cutoff = timezone.now() - timedelta(days=days)
    deleted, _ = DriverLocation.objects.filter(recorded_at__lt=cutoff).delete()
    if deleted:
        logger.info("drivers.locations_purged deleted=%s older_than_days=%s", deleted, days)
    return deleted
