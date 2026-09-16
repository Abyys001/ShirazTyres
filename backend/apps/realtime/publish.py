"""Pushing state to whoever is entitled to see it.

The audience boundary from section 4.6 is enforced here, not in the client: driver
positions go to the panel group only. A customer receives status and an ETA figure,
never a coordinate.
"""

import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from . import groups

logger = logging.getLogger(__name__)


def _send(group: str, payload: dict) -> None:
    layer = get_channel_layer()
    if layer is None:  # No channel layer configured — realtime is optional, the API is not.
        return
    try:
        async_to_sync(layer.group_send)(group, {"type": "broadcast", "payload": payload})
    except Exception as exc:  # noqa: BLE001 — a broker hiccup must never fail a request.
        logger.warning("realtime.send_failed group=%s error=%s", group, exc)


def publish_driver_location(driver) -> None:
    """Panel only. Section 4.6 keeps an employee's live position off customer surfaces."""
    _send(
        groups.PANEL,
        {
            "event": "driver.location",
            "driver_id": driver.pk,
            "name": driver.name,
            "latitude": str(driver.latitude),
            "longitude": str(driver.longitude),
            "accuracy_m": driver.location_accuracy_m,
            "recorded_at": driver.location_updated_at.isoformat() if driver.location_updated_at else None,
        },
    )


def publish_job_event(job, kind: str) -> None:
    from apps.bookings.serializers import CustomerJobSerializer, JobSerializer

    _send(groups.PANEL, {"event": f"job.{kind}", "job": JobSerializer(job).data})

    if job.customer_id and job.status in job.CUSTOMER_VISIBLE_STATUSES:
        _send(
            groups.customer_group(job.customer_id),
            {"event": f"job.{kind}", "job": CustomerJobSerializer(job).data},
        )

    if job.driver_id:
        from apps.bookings.serializers import DriverJobSerializer

        _send(
            groups.driver_group(job.driver_id),
            {"event": f"job.{kind}", "job": DriverJobSerializer(job).data},
        )


def publish_offer(offer) -> None:
    from apps.bookings.serializers import DriverJobSerializer
    from apps.dispatch.serializers import DriverOfferSerializer

    _send(
        groups.driver_group(offer.driver_id),
        {
            "event": "offer.new",
            "offer": DriverOfferSerializer(offer).data,
            "job": DriverJobSerializer(offer.attempt.job).data,
        },
    )
    publish_dispatch_event(offer.attempt.job, "offered")


def publish_offer_withdrawn(offer_id: int, reason: str = "Another driver took this job.") -> None:
    """The reason is shown to the technician, so it has to be the true one: a job the
    office assigned by hand did not go to a faster driver."""
    from apps.dispatch.models import DispatchOffer

    offer = DispatchOffer.objects.select_related("attempt__job").filter(pk=offer_id).first()
    if offer is None:
        return
    _send(
        groups.driver_group(offer.driver_id),
        {
            "event": "offer.withdrawn",
            "offer_id": offer.pk,
            "job_id": offer.attempt.job_id,
            "reason": reason,
        },
    )
    publish_dispatch_event(offer.attempt.job, "withdrawn")


def publish_driver_event(driver, kind: str) -> None:
    """Panel and the driver's own app.

    The panel keeps a roster and a map that both have to move without a reload, so
    every change to a driver's shift or standing is announced rather than polled for.
    The driver's own copy goes to their private group: it is the same record the
    office sees, and it is already theirs.
    """
    from apps.drivers.serializers import DriverSerializer, DriverSelfSerializer

    _send(
        groups.PANEL,
        {"event": f"driver.{kind}", "driver": DriverSerializer(driver).data},
    )
    _send(
        groups.driver_group(driver.pk),
        {"event": f"driver.{kind}", "driver": DriverSelfSerializer(driver).data},
    )


def publish_invoice_event(invoice, kind: str) -> None:
    """Panel only. Money is an office concern; the customer sees a total on the job."""
    from apps.billing.serializers import InvoiceSerializer

    _send(
        groups.PANEL,
        {"event": f"invoice.{kind}", "invoice": InvoiceSerializer(invoice).data},
    )


def publish_dispatch_event(job, kind: str) -> None:
    """Where a job is in the dispatch round, for the panel's dispatch card.

    Section 6: the worst failure this system has is a job sitting with nobody
    waiting on it, so the office watches the rounds happen rather than finding out
    on the next poll.
    """
    from apps.dispatch.models import DispatchAttempt
    from apps.dispatch.serializers import DispatchAttemptSerializer

    attempt = (
        DispatchAttempt.objects.filter(job=job)
        .prefetch_related("offers__driver")
        .order_by("-round_number")
        .first()
    )
    _send(
        groups.PANEL,
        {
            "event": f"dispatch.{kind}",
            "job_id": job.pk,
            "attempt": DispatchAttemptSerializer(attempt).data if attempt else None,
        },
    )


def publish_config_event(kind: str) -> None:
    """A change to the catalogue the office works from — the settings, the price
    list, the service areas, the staff accounts.

    Only the kind travels. These change rarely and feed several panel queries at
    once, so the useful message is "go and look again", not a payload each screen
    would have to merge into its own shape.
    """
    _send(groups.PANEL, {"event": f"config.{kind}"})
