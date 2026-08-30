"""Who gets told what, and through which channel.

Section 12 makes both the event list and the channel list the owner's to change, so
nothing here hard-codes an audience. Templates come from the same catalogue.
"""

import logging

from celery import shared_task
from django.conf import settings

from apps.configuration.services import get_setting

from .models import DeviceToken, Notification
from .services import send_email, send_push, send_sms

logger = logging.getLogger(__name__)


def _owner_channels() -> set[str]:
    return set(get_setting("notifications.owner_channels") or [])


def _customer_channels() -> set[str]:
    return set(get_setting("notifications.customer_channels") or [])


def _template(event: str) -> str:
    return (get_setting("notifications.templates") or {}).get(event, "")


def _render(event: str, job) -> str:
    template = _template(event)
    if not template:
        return ""
    driver = job.driver
    vehicle = driver.primary_vehicle if driver else None
    invoice = getattr(job, "invoice", None)
    try:
        return template.format(
            reference=job.reference,
            driver_name=driver.first_name if driver else "your technician",
            driver_vehicle=vehicle.description if vehicle else "our van",
            driver_plate=vehicle.display_plate if vehicle else "",
            eta_minutes=job.eta_minutes if job.eta_minutes is not None else "a few",
            total=f"£{invoice.total}" if invoice else "",
        )
    except (KeyError, IndexError):
        logger.warning("notifications.bad_template event=%s", event)
        return ""


def _job_summary(job) -> str:
    parts = [
        f"New tyre call-out {job.reference}",
        f"{job.issue_label or job.issue_type} — {job.contact_name} {job.contact_phone}",
    ]
    if job.plate:
        parts.append(f"Vehicle: {job.plate} {job.vehicle.description}".strip())
    if job.tyre_size:
        suffix = " (customer-supplied)" if job.customer_tyre_size else ""
        parts.append(f"Tyre: {job.tyre_size}{suffix}")
    if job.location_text:
        parts.append(f"Location: {job.location_text}")
    return "\n".join(parts)


def _get_job(job_id: int):
    from apps.bookings.models import Job

    return Job.objects.select_related("vehicle", "driver", "customer", "invoice").filter(pk=job_id).first()


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def notify_new_job(self, job_id: int) -> None:
    job = _get_job(job_id)
    if job is None:
        logger.warning("notify_new_job.missing job_id=%s", job_id)
        return
    if "submitted" not in (get_setting("notifications.owner_events") or []):
        return

    channels = _owner_channels()
    summary = _job_summary(job)
    detail_url = f"{settings.PANEL_BASE_URL}/jobs/{job.pk}"

    if "push" in channels:
        for device in DeviceToken.objects.filter(staff__isnull=False, is_active=True):
            send_push(
                device,
                "New emergency tyre request",
                f"{job.reference} · {job.issue_label} · {job.location_text}",
                {"job_id": job.pk, "reference": job.reference},
                job=job, event="submitted",
            )

    if "sms" in channels:
        for number in settings.SHOP_NOTIFY_SMS:
            send_sms(number, f"{summary}\n{job.maps_url()}", job=job, event="submitted")

    if "email" in channels:
        for address in settings.SHOP_NOTIFY_EMAIL:
            send_email(
                address,
                f"[ShirazTyres] New call-out {job.reference}",
                f"{summary}\n\nMap: {job.maps_url()}\nOpen in panel: {detail_url}\n",
                job=job, event="submitted",
            )

    if not (settings.SHOP_NOTIFY_SMS or settings.SHOP_NOTIFY_EMAIL) and "push" not in channels:
        logger.warning("notify_new_job.no_targets job=%s", job.reference)


@shared_task
def notify_job_status_change(job_id: int, previous: str, new_status: str) -> None:
    job = _get_job(job_id)
    if job is None:
        return

    if new_status in (get_setting("notifications.customer_events") or []):
        _notify_customer(job, new_status)

    if new_status in (get_setting("notifications.owner_events") or []) and new_status != "submitted":
        _notify_owner(job, new_status)

    if job.driver_id and new_status in {"assigned", "cancelled"}:
        push_title = "Job assigned to you" if new_status == "assigned" else "Job cancelled"
        for device in DeviceToken.objects.filter(driver_id=job.driver_id, is_active=True):
            send_push(
                device, push_title, f"{job.reference} · {job.location_text}",
                {"job_id": job.pk, "status": new_status}, job=job, event=new_status,
            )


def _notify_customer(job, event: str) -> None:
    message = _render(event, job)
    if not message:
        return
    channels = _customer_channels()

    if "sms" in channels and job.contact_phone:
        send_sms(job.contact_phone, message, job=job, event=event)

    if "push" in channels and job.customer_id:
        for device in DeviceToken.objects.filter(customer_id=job.customer_id, is_active=True):
            send_push(
                device, f"Call-out {job.reference}", message,
                {"job_id": job.pk, "status": event}, job=job, event=event,
            )

    if "email" in channels and job.contact_email:
        send_email(
            job.contact_email, f"[ShirazTyres] {job.reference}", message, job=job, event=event
        )


def _notify_owner(job, event: str) -> None:
    channels = _owner_channels()
    line = f"{job.reference}: {job.get_status_display()}."

    if "push" in channels:
        for device in DeviceToken.objects.filter(staff__isnull=False, is_active=True):
            send_push(device, "Job update", line, {"job_id": job.pk}, job=job, event=event)
    if "sms" in channels:
        for number in settings.SHOP_NOTIFY_SMS:
            send_sms(number, line, job=job, event=event)
    if "email" in channels:
        for address in settings.SHOP_NOTIFY_EMAIL:
            send_email(address, f"[ShirazTyres] {job.reference}", line, job=job, event=event)


@shared_task
def notify_driver_offer(offer_id: int) -> None:
    """The offer itself. Push is the only channel that reaches a driver mid-shift."""
    from apps.dispatch.models import DispatchOffer
    from apps.realtime.publish import publish_offer

    offer = (
        DispatchOffer.objects.select_related("attempt__job__vehicle", "driver")
        .filter(pk=offer_id)
        .first()
    )
    if offer is None:
        return

    job = offer.attempt.job
    publish_offer(offer)

    minutes = max(1, round(offer.eta_seconds / 60)) if offer.eta_seconds else None
    body = f"{job.issue_label} · {job.location_text or 'roadside'}"
    if minutes:
        body += f" · about {minutes} min away"

    for device in DeviceToken.objects.filter(driver=offer.driver, is_active=True):
        send_push(
            device,
            "New job available" if offer.attempt.mode == "selection" else "Job assigned to you",
            body,
            {"job_id": job.pk, "offer_id": offer.pk, "mode": offer.attempt.mode},
            job=job, event="offer",
        )


@shared_task
def notify_job_unclaimed(job_id: int) -> None:
    """Section 5: this row requires staff intervention, so it is always loud."""
    job = _get_job(job_id)
    if job is None:
        return

    message = _render("unclaimed", job) or f"{job.reference} could not be assigned and needs attention."
    detail_url = f"{settings.PANEL_BASE_URL}/jobs/{job.pk}"

    for device in DeviceToken.objects.filter(staff__isnull=False, is_active=True):
        send_push(device, "Job unclaimed", message, {"job_id": job.pk}, job=job, event="unclaimed")
    for number in settings.SHOP_NOTIFY_SMS:
        send_sms(number, message, job=job, event="unclaimed")
    for address in settings.SHOP_NOTIFY_EMAIL:
        send_email(
            address, f"[ShirazTyres] UNCLAIMED {job.reference}",
            f"{message}\n\n{_job_summary(job)}\n\nOpen in panel: {detail_url}\n",
            job=job, event="unclaimed",
        )


@shared_task
def notify_driver_verification(driver_id: int, status: str, note: str = "") -> None:
    from apps.drivers.models import Driver

    driver = Driver.objects.filter(pk=driver_id).first()
    if driver is None:
        return

    messages = {
        Driver.Verification.APPROVED: "Your ShirazTyres driver account is approved. Go online to start receiving jobs.",
        Driver.Verification.REJECTED: "Your ShirazTyres driver application was not approved.",
        Driver.Verification.SUSPENDED: "Your ShirazTyres driver account has been suspended.",
    }
    message = messages.get(status)
    if not message:
        return
    if note:
        message = f"{message} {note}"

    send_sms(driver.phone, message, event="driver_verification")
    for device in DeviceToken.objects.filter(driver=driver, is_active=True):
        send_push(device, "Account update", message, {"verification_status": status}, event="driver_verification")


@shared_task
def notify_document_expiring(document_id: int) -> None:
    """Section 8.3 — the owner is warned before the document lapses, and so is the driver."""
    from apps.drivers.models import DriverDocument

    document = DriverDocument.objects.select_related("driver").filter(pk=document_id).first()
    if document is None:
        return

    days = document.days_to_expiry
    label = document.get_document_type_display()
    driver_message = (
        f"Your {label.lower()} on file with ShirazTyres expires in {days} day(s). "
        "Upload a new one in the app to stay available for jobs."
    )
    owner_message = f"{document.driver.name or document.driver.phone}: {label} expires in {days} day(s)."

    send_sms(document.driver.phone, driver_message, event="document_expiring")
    for device in DeviceToken.objects.filter(driver=document.driver, is_active=True):
        send_push(device, "Document expiring", driver_message, event="document_expiring")
    for address in settings.SHOP_NOTIFY_EMAIL:
        send_email(address, "[ShirazTyres] Driver document expiring", owner_message, event="document_expiring")


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
