"""Booking lifecycle. Status changes go through here so history and notifications never drift."""

import logging

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.accounts.models import StaffUser

from .models import Booking, BookingStatusEvent

logger = logging.getLogger(__name__)


def create_booking(*, created_by_staff: StaffUser | None = None, **fields) -> Booking:
    from apps.notifications.tasks import notify_new_booking

    with transaction.atomic():
        booking = Booking.objects.create(created_by_staff=created_by_staff, **fields)
        BookingStatusEvent.objects.create(
            booking=booking, from_status="", to_status=booking.status, changed_by=created_by_staff
        )
        # After commit: the shop must never be told about a booking that got rolled back.
        transaction.on_commit(lambda: notify_new_booking.delay(booking.pk))

    logger.info("booking.created reference=%s source=%s", booking.reference, booking.source)
    return booking


def transition_booking(
    booking: Booking,
    new_status: str,
    *,
    changed_by: StaffUser | None = None,
    note: str = "",
    assigned_to: StaffUser | None = None,
) -> Booking:
    from apps.notifications.tasks import notify_driver_status_change

    if new_status == booking.status:
        raise ValidationError({"status": [f"Booking is already {booking.get_status_display().lower()}."]})
    if not booking.can_transition_to(new_status):
        raise ValidationError(
            {"status": [f"Cannot move a {booking.get_status_display().lower()} booking to {new_status}."]}
        )

    previous = booking.status
    with transaction.atomic():
        booking.status = new_status
        updates = ["status"]

        if new_status == Booking.Status.ASSIGNED:
            booking.assigned_to = assigned_to or booking.assigned_to or changed_by
            booking.assigned_at = timezone.now()
            updates += ["assigned_to", "assigned_at"]
        elif assigned_to is not None:
            booking.assigned_to = assigned_to
            updates.append("assigned_to")

        if new_status == Booking.Status.COMPLETED:
            booking.completed_at = timezone.now()
            updates.append("completed_at")

        booking.save(update_fields=updates)
        BookingStatusEvent.objects.create(
            booking=booking, from_status=previous, to_status=new_status, note=note, changed_by=changed_by
        )
        transaction.on_commit(lambda: notify_driver_status_change.delay(booking.pk, previous, new_status))

    logger.info("booking.transition reference=%s %s->%s", booking.reference, previous, new_status)
    return booking
