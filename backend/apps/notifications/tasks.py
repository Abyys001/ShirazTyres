"""Alerting the shop. An emergency must not depend on someone watching a browser tab,
so the owner gets push *and* SMS/email."""

import logging

from celery import shared_task
from django.conf import settings

from .models import DeviceToken, Notification
from .services import send_email, send_push, send_sms

logger = logging.getLogger(__name__)


def _booking_summary(booking) -> str:
    parts = [
        f"New tyre call-out {booking.reference}",
        f"{booking.get_issue_type_display()} — {booking.contact_name} {booking.contact_phone}",
    ]
    if booking.plate:
        parts.append(f"Vehicle: {booking.plate} {booking.vehicle.description}".strip())
    if booking.tyre_size:
        parts.append(f"Tyre: {booking.tyre_size}")
    parts.append(f"Location: {booking.location_text}")
    return "\n".join(parts)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def notify_new_booking(self, booking_id: int) -> None:
    from apps.bookings.models import Booking

    booking = Booking.objects.select_related("vehicle").filter(pk=booking_id).first()
    if booking is None:
        logger.warning("notify_new_booking.missing booking_id=%s", booking_id)
        return

    summary = _booking_summary(booking)
    detail_url = f"{settings.PANEL_BASE_URL}/bookings/{booking.pk}"

    for device in DeviceToken.objects.filter(staff__isnull=False, is_active=True):
        send_push(
            device,
            "New emergency tyre request",
            f"{booking.reference} · {booking.get_issue_type_display()} · {booking.location_text}",
            {"booking_id": booking.pk, "reference": booking.reference},
            booking=booking,
        )

    for number in settings.SHOP_NOTIFY_SMS:
        send_sms(number, f"{summary}\n{booking.maps_url()}", booking=booking)

    for address in settings.SHOP_NOTIFY_EMAIL:
        send_email(
            address,
            f"[ShirazTyres] New call-out {booking.reference}",
            f"{summary}\n\nMap: {booking.maps_url()}\nOpen in panel: {detail_url}\n",
            booking=booking,
        )

    if not (settings.SHOP_NOTIFY_SMS or settings.SHOP_NOTIFY_EMAIL):
        logger.warning("notify_new_booking.no_targets booking=%s", booking.reference)


@shared_task
def notify_driver_status_change(booking_id: int, previous: str, new_status: str) -> None:
    from apps.bookings.models import Booking

    booking = Booking.objects.filter(pk=booking_id).first()
    if booking is None or not booking.contact_phone:
        return

    messages = {
        Booking.Status.ASSIGNED: "we're on our way to you",
        Booking.Status.IN_PROGRESS: "our technician has started work",
        Booking.Status.COMPLETED: "your call-out is complete. Thanks for choosing ShirazTyres",
        Booking.Status.CANCELLED: "your call-out has been cancelled. Call us if this is wrong",
    }
    if new_status not in messages:
        return

    send_sms(
        booking.contact_phone,
        f"ShirazTyres {booking.reference}: {messages[new_status]}.",
        booking=booking,
    )

    for device in DeviceToken.objects.filter(driver=booking.driver, is_active=True) if booking.driver else []:
        send_push(
            device,
            f"Call-out {booking.reference}",
            messages[new_status].capitalize() + ".",
            {"booking_id": booking.pk, "status": new_status},
            booking=booking,
        )


@shared_task
def purge_expired_otps(days: int = 7) -> int:
    """Data-retention hygiene: consumed/expired codes are worthless after a week."""
    from datetime import timedelta

    from django.utils import timezone

    from apps.accounts.models import OtpCode

    cutoff = timezone.now() - timedelta(days=days)
    deleted, _ = OtpCode.objects.filter(created_at__lt=cutoff).delete()
    return deleted


@shared_task
def purge_old_notifications(days: int = 180) -> int:
    from datetime import timedelta

    from django.utils import timezone

    cutoff = timezone.now() - timedelta(days=days)
    deleted, _ = Notification.objects.filter(created_at__lt=cutoff).delete()
    return deleted
