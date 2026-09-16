"""Sending + audit. Every send is recorded before it leaves, so failures are visible."""

import logging

from django.conf import settings
from django.core.mail import send_mail
from django.utils import timezone

from .models import DeviceToken, Notification
from .providers import ProviderError, get_push_provider, get_sms_provider

logger = logging.getLogger(__name__)


#: Which log category each channel writes under, so the panel can filter to
#: "show me the email" without knowing anything about Notification.Channel.
_AUDIT_CATEGORY = {
    Notification.Channel.SMS: "sms",
    Notification.Channel.EMAIL: "email",
    Notification.Channel.PUSH: "push",
}


def _finish(notification: Notification, *, message_id: str = "", error: str = "") -> Notification:
    notification.status = Notification.Status.FAILED if error else Notification.Status.SENT
    notification.provider_message_id = message_id
    notification.error = error[:255]
    notification.sent_at = timezone.now()
    notification.save(update_fields=["status", "provider_message_id", "error", "sent_at"])

    # Every channel funnels through here, so one hook logs the lot. The
    # Notification row remains the record of *what was sent*; this is the
    # operational trail of whether the send actually worked.
    from apps.audit.models import AuditEvent
    from apps.audit.services import record

    record(
        _AUDIT_CATEGORY.get(notification.channel, "system"),
        f"{notification.get_channel_display()} to {notification.recipient} "
        f"{'failed' if error else 'sent'}",
        severity=AuditEvent.Severity.ERROR if error else AuditEvent.Severity.INFO,
        actor="system",
        subject_type="notification",
        subject_id=notification.pk,
        recipient=notification.recipient,
        event=notification.event,
        subject=notification.subject,
        provider_message_id=message_id,
        error=error,
        job_id=notification.job_id,
    )
    return notification


def send_sms(to: str, body: str, *, job=None, event: str = "") -> Notification:
    notification = Notification.objects.create(
        job=job, event=event, channel=Notification.Channel.SMS, recipient=to, body=body
    )
    try:
        result = get_sms_provider().send(to, body)
    except ProviderError as exc:
        logger.error("sms.failed to=%s error=%s", to, exc)
        return _finish(notification, error=str(exc))
    return _finish(notification, message_id=result.message_id)


def send_email(to: str, subject: str, body: str, *, job=None, event: str = "") -> Notification:
    notification = Notification.objects.create(
        job=job, event=event, channel=Notification.Channel.EMAIL,
        recipient=to, subject=subject, body=body,
    )
    try:
        send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [to], fail_silently=False)
    except Exception as exc:  # noqa: BLE001 — any backend failure must be recorded, not raised.
        logger.error("email.failed to=%s error=%s", to, exc)
        return _finish(notification, error=str(exc))
    return _finish(notification)


def send_push(
    token_row: DeviceToken, title: str, body: str, data: dict | None = None, *, job=None, event: str = ""
) -> Notification:
    notification = Notification.objects.create(
        job=job,
        event=event,
        channel=Notification.Channel.PUSH,
        recipient=token_row.token[:255],
        subject=title,
        body=body,
    )
    try:
        result = get_push_provider().send(token_row.token, title, body, data)
    except ProviderError as exc:
        logger.error("push.failed token=%s error=%s", token_row.pk, exc)
        return _finish(notification, error=str(exc))
    return _finish(notification, message_id=result.message_id)


def push_to(queryset, title: str, body: str, data: dict | None = None, *, job=None, event: str = "") -> int:
    sent = 0
    for device in queryset.filter(is_active=True):
        send_push(device, title, body, data, job=job, event=event)
        sent += 1
    return sent
