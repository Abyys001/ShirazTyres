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


def publish_offer_withdrawn(offer_id: int) -> None:
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
            "reason": "Another driver took this job.",
        },
    )
