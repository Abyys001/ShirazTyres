"""Job lifecycle. Status changes go through here so history, notifications, the live
panel and the customer's ETA never drift apart."""

import logging

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.accounts.models import StaffUser
from apps.configuration.services import get_setting
from apps.drivers.models import Driver
from apps.geo.services import find_area, is_covered

from .models import Job, JobStatusEvent

logger = logging.getLogger(__name__)

_STATUS_TIMESTAMPS = {
    Job.Status.DISPATCHING: "dispatch_started_at",
    Job.Status.ASSIGNED: "assigned_at",
    Job.Status.ACCEPTED: "accepted_at",
    Job.Status.EN_ROUTE: "en_route_at",
    Job.Status.ARRIVED: "arrived_at",
    Job.Status.IN_PROGRESS: "started_at",
    Job.Status.COMPLETED: "completed_at",
    Job.Status.CANCELLED: "cancelled_at",
}


class OutOfServiceArea(ValidationError):
    pass


def resolve_issue_label(issue_type: str) -> str:
    for entry in get_setting("operational.issue_types") or []:
        if entry.get("value") == issue_type:
            return entry.get("label", issue_type)
    return issue_type


def validate_issue_type(issue_type: str) -> str:
    values = {entry.get("value") for entry in get_setting("operational.issue_types") or []}
    if values and issue_type not in values:
        raise ValidationError({"issue_type": ["Choose one of the listed problems."]})
    return issue_type


def check_coverage(latitude, longitude):
    """Section 4.4 — a location nobody can reach is refused, not accepted as a job."""
    if latitude is None or longitude is None:
        return None
    if not is_covered(latitude, longitude):
        raise OutOfServiceArea(
            {"location": [get_setting("service_areas.out_of_area_message")], "out_of_area": True}
        )
    return find_area(latitude, longitude)


def create_job(*, created_by_staff: StaffUser | None = None, auto_dispatch: bool = True, **fields) -> Job:
    from apps.billing.services import create_invoice_for_job
    from apps.dispatch.tasks import run_dispatch
    from apps.notifications.tasks import notify_new_job
    from apps.realtime.publish import publish_job_event

    fields.setdefault("issue_label", resolve_issue_label(fields.get("issue_type", "")))
    fields["service_area"] = check_coverage(fields.get("latitude"), fields.get("longitude"))

    with transaction.atomic():
        job = Job.objects.create(created_by_staff=created_by_staff, **fields)
        JobStatusEvent.objects.create(
            job=job,
            from_status="",
            to_status=job.status,
            actor_type=JobStatusEvent.Actor.STAFF if created_by_staff else JobStatusEvent.Actor.CUSTOMER,
            changed_by_staff=created_by_staff,
        )
        # Section 7.1 step 2: the call-out fee is the invoice's first line, from the start.
        create_invoice_for_job(job)

        # After commit: nobody is told about, or dispatched to, a job that got rolled back.
        transaction.on_commit(lambda: notify_new_job.delay(job.pk))
        transaction.on_commit(lambda: publish_job_event(job, "created"))
        if auto_dispatch:
            transaction.on_commit(lambda: run_dispatch.delay(job.pk))

    logger.info("job.created reference=%s source=%s area=%s", job.reference, job.source, job.service_area_id)
    return job


def transition_job(
    job: Job,
    new_status: str,
    *,
    staff: StaffUser | None = None,
    driver: Driver | None = None,
    actor_type: str = JobStatusEvent.Actor.SYSTEM,
    note: str = "",
    assigned_staff: StaffUser | None = None,
    set_driver: Driver | None = None,
    clear_driver: bool = False,
    force: bool = False,
) -> Job:
    """
    Move a job to ``new_status``, recording who did it and why.

    ``force`` is the office's override of the section 5 lifecycle, and exists
    because reality does not always take the transitions the graph allows — a
    driver's phone dies mid-job, a call-out is finished on paper, a job is
    resurrected after being cancelled in error. Refusing those left staff
    editing rows in the database, which is worse than allowing it and writing
    down what happened.

    It bypasses the transition check and nothing else: the event, the actor, the
    timestamps, the notification and the realtime publish are all identical, so
    a forced move is as auditable as any other. Callers must supply a note; the
    serializer enforces that, and an override with no reason on the record is
    the thing this is meant to prevent.
    """
    from apps.notifications.tasks import notify_job_status_change
    from apps.realtime.publish import publish_job_event

    if new_status == job.status:
        raise ValidationError({"status": [f"This job is already {job.get_status_display().lower()}."]})
    if not force and not job.can_transition_to(new_status):
        raise ValidationError(
            {"status": [
                f"Cannot move a {job.get_status_display().lower()} job to "
                f"{Job.Status(new_status).label.lower()}."
            ]}
        )

    previous = job.status
    now = timezone.now()

    with transaction.atomic():
        job.status = new_status
        updates = ["status"]

        timestamp_field = _STATUS_TIMESTAMPS.get(new_status)
        if timestamp_field and getattr(job, timestamp_field) is None:
            setattr(job, timestamp_field, now)
            updates.append(timestamp_field)

        if set_driver is not None:
            job.driver = set_driver
            updates.append("driver")
        elif clear_driver:
            job.driver = None
            job.eta_seconds = None
            job.eta_updated_at = None
            updates += ["driver", "eta_seconds", "eta_updated_at"]

        if assigned_staff is not None:
            job.assigned_staff = assigned_staff
            updates.append("assigned_staff")

        if new_status == Job.Status.CANCELLED and note:
            job.cancellation_reason = note[:255]
            updates.append("cancellation_reason")

        job.save(update_fields=list(dict.fromkeys(updates)))
        JobStatusEvent.objects.create(
            job=job,
            from_status=previous,
            to_status=new_status,
            # Marked on the event itself, so a move the lifecycle would not have
            # allowed is identifiable in the timeline long after the fact.
            note=f"Override: {note}"[:255] if force else note,
            actor_type=actor_type,
            changed_by_staff=staff,
            changed_by_driver=driver,
        )
        transaction.on_commit(lambda: notify_job_status_change.delay(job.pk, previous, new_status))
        transaction.on_commit(lambda: publish_job_event(job, "status"))

    logger.info("job.transition reference=%s %s->%s", job.reference, previous, new_status)

    # JobStatusEvent stays the authority on a job's own history. This puts the
    # same move on the one timeline that also carries the OTP, the email and the
    # Stripe callback, which is where somebody goes when the question spans more
    # than one job.
    from apps.audit.models import AuditEvent
    from apps.audit.services import record

    record(
        "job",
        f"{job.reference}: {previous} to {new_status}" + (" (override)" if force else ""),
        severity=AuditEvent.Severity.WARNING if force else AuditEvent.Severity.INFO,
        actor=(
            getattr(staff, "name", "")
            or getattr(driver, "name", "")
            or actor_type
        ),
        subject_type="job",
        subject_id=job.pk,
        reference=job.reference,
        from_status=previous,
        to_status=new_status,
        note=note,
        forced=force,
    )
    return job


def set_eta(job: Job, seconds: int | None, distance_metres: int | None = None) -> Job:
    """Section 4.6 — only the resulting figure ever reaches the customer, never the position."""
    from apps.realtime.publish import publish_job_event

    job.eta_seconds = seconds
    job.eta_distance_metres = distance_metres
    job.eta_updated_at = timezone.now() if seconds is not None else None
    job.save(update_fields=["eta_seconds", "eta_distance_metres", "eta_updated_at"])
    publish_job_event(job, "eta")
    return job


def correct_tyre_on_site(job: Job, size: str, *, driver: Driver, note: str = "") -> Job:
    """Section 9.3 — the driver overrides the specification when the car does not match."""
    from apps.realtime.publish import publish_job_event
    from apps.vehicles.models import Vehicle
    from apps.vehicles.services import confirm_tyre_size

    job.tyre_size = size
    job.tyre_corrected_on_site = True
    job.tyre_correction_note = note[:255]
    job.save(update_fields=["tyre_size", "tyre_corrected_on_site", "tyre_correction_note"])

    if job.vehicle:
        confirm_tyre_size(job.vehicle, size, source=Vehicle.TyreSource.DRIVER)

    JobStatusEvent.objects.create(
        job=job,
        from_status=job.status,
        to_status=job.status,
        note=f"Tyre specification corrected on site to {size}. {note}".strip(),
        actor_type=JobStatusEvent.Actor.DRIVER,
        changed_by_driver=driver,
    )
    logger.info("job.tyre_corrected reference=%s size=%s", job.reference, size)
    publish_job_event(job, "tyre")
    return job


def customer_may_cancel(job: Job) -> bool:
    """How far into the call-out the customer keeps the cancel button.

    The default runs to ``in_progress``: a job is only settled once the technician
    takes payment, and until then a customer who no longer needs us should be able
    to say so from the app rather than by telephone. An unclaimed job is still the
    customer's to drop — nobody is on their way.
    """
    limit = get_setting("operational.customer_cancel_until")
    if limit == "never":
        return False
    order = [
        Job.Status.SUBMITTED, Job.Status.DISPATCHING, Job.Status.UNCLAIMED, Job.Status.ASSIGNED,
        Job.Status.ACCEPTED, Job.Status.EN_ROUTE, Job.Status.ARRIVED, Job.Status.IN_PROGRESS,
    ]
    if job.status not in order:
        return False
    boundaries = {
        "accepted": Job.Status.ACCEPTED,
        "en_route": Job.Status.EN_ROUTE,
        "arrived": Job.Status.ARRIVED,
        "in_progress": Job.Status.IN_PROGRESS,
    }
    boundary = boundaries.get(limit, Job.Status.IN_PROGRESS)
    return order.index(job.status) <= order.index(boundary)
