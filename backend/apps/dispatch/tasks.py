"""Celery entry points for dispatch. Everything that decides anything lives in ``engine``."""

import logging

from celery import shared_task

from apps.bookings.models import Job

from .models import DispatchAttempt

logger = logging.getLogger(__name__)


@shared_task
def run_dispatch(job_id: int) -> None:
    from .engine import dispatch_job

    job = Job.objects.select_related("service_area").filter(pk=job_id).first()
    if job is None:
        logger.warning("dispatch.run_missing job_id=%s", job_id)
        return
    dispatch_job(job)


@shared_task
def escalate_job(job_id: int) -> None:
    from .engine import escalate

    job = Job.objects.select_related("service_area").filter(pk=job_id).first()
    if job is None:
        return
    escalate(job)


@shared_task
def expire_attempt(attempt_id: int) -> None:
    from .engine import expire_attempt_now

    attempt = DispatchAttempt.objects.select_related("job").filter(pk=attempt_id).first()
    if attempt is None:
        return
    expire_attempt_now(attempt)


@shared_task
def sweep_expired_attempts() -> int:
    """Belt and braces: a worker restart can lose a countdown task, and a job stuck in
    ``dispatching`` with nobody waiting on it is the worst failure this system has."""
    from django.utils import timezone

    from .engine import expire_attempt_now

    stale = DispatchAttempt.objects.filter(
        outcome=DispatchAttempt.Outcome.PENDING, expires_at__lt=timezone.now()
    ).select_related("job")

    count = 0
    for attempt in stale:
        expire_attempt_now(attempt)
        count += 1
    if count:
        logger.warning("dispatch.swept_expired count=%s", count)
    return count


@shared_task
def refresh_etas_for_driver(driver_id: int) -> int:
    """Section 4.6 — recalculated on the backend each time the driver's location updates."""
    from .engine import refresh_eta

    jobs = Job.objects.filter(driver_id=driver_id, status__in=Job.DRIVER_BUSY_STATUSES)
    for job in jobs:
        refresh_eta(job)
    return len(jobs)
