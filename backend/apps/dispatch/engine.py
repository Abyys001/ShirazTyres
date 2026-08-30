"""Dispatch: choosing who gets the job, and what happens when they don't take it.

Specification section 6. Two modes share one code path; the only difference is how many
drivers a round is offered to and whether the job is assigned up front.

Three rules shape everything here:

* Candidates are ranked by **routing travel time**, never straight-line distance (6.4).
* **Rejection is a signal, not an error** (6.3) — it escalates immediately rather than
  waiting out the timeout.
* A driver who has already rejected a job is never offered it again.
"""

import logging
from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.bookings.models import Job, JobStatusEvent
from apps.bookings.services import set_eta, transition_job
from apps.configuration.catalogue import DISPATCH_MODE_AUTOMATIC, DISPATCH_MODE_SELECTION
from apps.drivers.models import Driver
from apps.drivers.services import dispatchable_queryset, has_capacity
from apps.geo.geometry import haversine_km
from apps.geo.routing import travel_times
from apps.geo import services as geo_services
from apps.geo.services import area_setting

from .models import DispatchAttempt, DispatchOffer

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Candidate:
    driver: Driver
    eta_seconds: int
    distance_metres: int


def _config(job: Job) -> dict:
    """Global settings, with this job's service area allowed to override them (section 12)."""
    area = job.service_area
    return {
        "mode": area_setting(area, "dispatch.mode"),
        "batch": max(1, int(area_setting(area, "dispatch.offer_batch_size"))),
        "initial_radius": Decimal(str(area_setting(area, "dispatch.initial_radius_km"))),
        "increment": Decimal(str(area_setting(area, "dispatch.radius_increment_km"))),
        "selection_timeout": int(area_setting(area, "dispatch.selection_timeout_seconds")),
        "automatic_timeout": int(area_setting(area, "dispatch.automatic_timeout_seconds")),
        "max_attempts": max(1, int(area_setting(area, "dispatch.max_attempts"))),
        "fallback": area_setting(area, "dispatch.escalation_fallback"),
        "pool_cap": max(1, int(area_setting(area, "dispatch.max_candidate_pool"))),
    }


def _exhausted_driver_ids(job: Job) -> set[int]:
    """Anyone who has already had this job and did not take it.

    Rejection is an explicit no; a timeout is a driver who could not be reached. Section
    6.5 sends both to the *next-best* driver, so neither is offered the job a second time.
    """
    return set(
        DispatchOffer.objects.filter(
            attempt__job=job,
            state__in=(DispatchOffer.State.REJECTED, DispatchOffer.State.TIMED_OUT),
        ).values_list("driver_id", flat=True)
    )


def rank_candidates(job: Job, *, radius_km: Decimal, limit: int) -> list[Candidate]:
    """Coarse radius filter, then the routing engine decides the order.

    The haversine step exists only to keep the routing matrix small; it never decides
    who is closer. Section 6.4 is explicit that in London it would pick the wrong driver.
    """
    destination = job.coordinates
    if destination is None:
        return []

    excluded = _exhausted_driver_ids(job)
    queryset = dispatchable_queryset().exclude(pk__in=excluded)
    if job.service_area_id:
        # A driver with no areas set is dispatchable everywhere; one with areas must match.
        queryset = queryset.filter(
            Q(service_areas__isnull=True) | Q(service_areas=job.service_area_id)
        )

    nearby: list[tuple[float, Driver]] = []
    for driver in queryset.distinct():
        origin = driver.coordinates
        if origin is None:
            continue
        crow_km = haversine_km(origin[0], origin[1], destination[0], destination[1])
        if crow_km > float(radius_km):
            continue
        if not has_capacity(driver):
            continue
        nearby.append((crow_km, driver))

    nearby.sort(key=lambda pair: pair[0])
    shortlist = [driver for _, driver in nearby[:limit]]
    if not shortlist:
        return []

    routes = travel_times([driver.coordinates for driver in shortlist], destination)
    candidates = [
        Candidate(driver, route.duration_seconds, route.distance_metres)
        for driver, route in zip(shortlist, routes)
        if route is not None
    ]
    candidates.sort(key=lambda candidate: candidate.eta_seconds)
    return candidates


def dispatch_job(job: Job, *, note: str = "") -> DispatchAttempt | None:
    """Run one round. Returns the attempt, or None when the job was marked unclaimed."""
    from apps.dispatch.tasks import escalate_job, expire_attempt
    from apps.notifications.tasks import notify_driver_offer

    if not job.is_dispatchable:
        logger.info("dispatch.skipped reference=%s status=%s", job.reference, job.status)
        return None

    config = _config(job)
    round_number = job.dispatch_rounds + 1

    if round_number > config["max_attempts"]:
        _apply_fallback(job, config)
        return None

    if job.status != Job.Status.DISPATCHING:
        transition_job(job, Job.Status.DISPATCHING, note=note or "Looking for a driver.")

    radius = config["initial_radius"] + config["increment"] * (round_number - 1)
    timeout = config["selection_timeout"] if config["mode"] == DISPATCH_MODE_SELECTION else config["automatic_timeout"]
    batch = 1 if config["mode"] == DISPATCH_MODE_AUTOMATIC else config["batch"]

    candidates = rank_candidates(job, radius_km=radius, limit=config["pool_cap"])[:batch]

    with transaction.atomic():
        job.dispatch_rounds = round_number
        job.save(update_fields=["dispatch_rounds"])

        attempt = DispatchAttempt.objects.create(
            job=job,
            round_number=round_number,
            mode=config["mode"],
            radius_km=radius,
            timeout_seconds=timeout,
            service_area=job.service_area,
            candidates_considered=len(candidates),
            expires_at=timezone.now() + timedelta(seconds=timeout),
            note=note[:255],
        )

        if not candidates:
            attempt.outcome = DispatchAttempt.Outcome.NO_CANDIDATES
            attempt.resolved_at = timezone.now()
            attempt.save(update_fields=["outcome", "resolved_at"])
            logger.info("dispatch.no_candidates reference=%s round=%s radius=%s",
                        job.reference, round_number, radius)
            job_id = job.pk
            transaction.on_commit(lambda: escalate_job.delay(job_id))
            return attempt

        offers = [
            DispatchOffer.objects.create(
                attempt=attempt,
                driver=candidate.driver,
                rank=index,
                eta_seconds=candidate.eta_seconds,
                distance_metres=candidate.distance_metres,
            )
            for index, candidate in enumerate(candidates, start=1)
        ]

        if config["mode"] == DISPATCH_MODE_AUTOMATIC:
            best = candidates[0]
            transition_job(
                job,
                Job.Status.ASSIGNED,
                set_driver=best.driver,
                note=f"Assigned automatically (round {round_number}).",
            )
            set_eta(job, best.eta_seconds, best.distance_metres)

        attempt_id = attempt.pk
        offer_ids = [offer.pk for offer in offers]
        transaction.on_commit(lambda: [notify_driver_offer.delay(offer_id) for offer_id in offer_ids])
        transaction.on_commit(lambda: expire_attempt.apply_async((attempt_id,), countdown=timeout))

    logger.info(
        "dispatch.round reference=%s round=%s mode=%s radius=%s offers=%s",
        job.reference, round_number, config["mode"], radius, len(candidates),
    )
    return attempt


def accept_offer(driver: Driver, job: Job) -> Job:
    """First acceptance wins; the job is withdrawn from every other driver at once."""
    from apps.realtime.publish import publish_offer_withdrawn

    withdrawn: list[int] = []

    with transaction.atomic():
        locked = Job.objects.select_for_update().get(pk=job.pk)
        offer = (
            DispatchOffer.objects.select_for_update()
            .filter(attempt__job=locked, driver=driver, state=DispatchOffer.State.OFFERED)
            .order_by("-attempt__round_number")
            .first()
        )
        if offer is None:
            raise ValidationError({"detail": ["This job is no longer available to you."]})
        if locked.driver_id not in (None, driver.pk):
            raise ValidationError({"detail": ["Another driver has already taken this job."]})

        now = timezone.now()
        offer.state = DispatchOffer.State.ACCEPTED
        offer.responded_at = now
        offer.save(update_fields=["state", "responded_at"])

        siblings = DispatchOffer.objects.filter(
            attempt=offer.attempt, state=DispatchOffer.State.OFFERED
        ).exclude(pk=offer.pk)
        withdrawn = list(siblings.values_list("pk", flat=True))
        siblings.update(state=DispatchOffer.State.WITHDRAWN, responded_at=now)

        DispatchAttempt.objects.filter(pk=offer.attempt_id).update(
            outcome=DispatchAttempt.Outcome.ACCEPTED, resolved_at=now
        )
        DispatchAttempt.objects.filter(
            job=locked, outcome=DispatchAttempt.Outcome.PENDING
        ).exclude(pk=offer.attempt_id).update(
            outcome=DispatchAttempt.Outcome.SUPERSEDED, resolved_at=now
        )

        if locked.status == Job.Status.DISPATCHING:
            transition_job(
                locked, Job.Status.ASSIGNED, set_driver=driver,
                driver=driver, actor_type=JobStatusEvent.Actor.DRIVER,
                note="Taken by the driver.",
            )
        job = transition_job(
            locked, Job.Status.ACCEPTED, driver=driver,
            actor_type=JobStatusEvent.Actor.DRIVER, set_driver=driver,
        )
        set_eta(job, offer.eta_seconds, offer.distance_metres)

    for offer_id in withdrawn:
        publish_offer_withdrawn(offer_id)

    logger.info("dispatch.accepted reference=%s driver=%s", job.reference, driver.pk)
    return job


def reject_offer(driver: Driver, job: Job, *, reason: str = "") -> Job:
    """Section 6.3. A rejection escalates now rather than burning the timeout."""
    escalate_now = False

    with transaction.atomic():
        locked = Job.objects.select_for_update().get(pk=job.pk)
        offer = (
            DispatchOffer.objects.select_for_update()
            .filter(attempt__job=locked, driver=driver, state=DispatchOffer.State.OFFERED)
            .order_by("-attempt__round_number")
            .first()
        )
        if offer is None:
            raise ValidationError({"detail": ["This job is no longer available to you."]})

        now = timezone.now()
        offer.state = DispatchOffer.State.REJECTED
        offer.reason = reason[:255]
        offer.responded_at = now
        offer.save(update_fields=["state", "reason", "responded_at"])

        attempt = offer.attempt
        remaining = DispatchOffer.objects.filter(
            attempt=attempt, state=DispatchOffer.State.OFFERED
        ).exists()

        if attempt.mode == DispatchAttempt.Mode.AUTOMATIC or not remaining:
            # Automatic: the one assignee said no. Selection: the pool is exhausted.
            attempt.outcome = DispatchAttempt.Outcome.REJECTED
            attempt.resolved_at = now
            attempt.save(update_fields=["outcome", "resolved_at"])
            escalate_now = True

            if locked.status in {Job.Status.ASSIGNED, Job.Status.ACCEPTED}:
                transition_job(
                    locked, Job.Status.DISPATCHING, driver=driver,
                    actor_type=JobStatusEvent.Actor.DRIVER, clear_driver=True,
                    note=f"Rejected by the driver. {reason}".strip(),
                )

        job = Job.objects.get(pk=locked.pk)

    logger.info("dispatch.rejected reference=%s driver=%s escalating=%s",
                job.reference, driver.pk, escalate_now)
    if escalate_now:
        _escalate_async(job.pk)
    return job


def expire_attempt_now(attempt: DispatchAttempt) -> None:
    """Section 6.5 — the dead-phone case. Silence is not the same signal as rejection,
    but the escalation it triggers is."""
    if not attempt.is_live:
        return

    now = timezone.now()
    with transaction.atomic():
        locked = DispatchAttempt.objects.select_for_update().get(pk=attempt.pk)
        if not locked.is_live:
            return

        DispatchOffer.objects.filter(attempt=locked, state=DispatchOffer.State.OFFERED).update(
            state=DispatchOffer.State.TIMED_OUT, responded_at=now
        )
        locked.outcome = DispatchAttempt.Outcome.TIMED_OUT
        locked.resolved_at = now
        locked.save(update_fields=["outcome", "resolved_at"])

        job = Job.objects.select_for_update().get(pk=locked.job_id)
        if job.status == Job.Status.ASSIGNED:
            transition_job(
                job, Job.Status.DISPATCHING, clear_driver=True,
                note="No response within the timeout.",
            )

    logger.info("dispatch.timed_out reference=%s round=%s", attempt.job.reference, attempt.round_number)
    _escalate_async(attempt.job_id)


def escalate(job: Job) -> None:
    """Widen and try again, or give up in the way the owner configured."""
    job.refresh_from_db()
    if not job.is_dispatchable:
        return

    config = _config(job)
    if job.dispatch_rounds >= config["max_attempts"]:
        _apply_fallback(job, config)
        return
    dispatch_job(job, note="Escalated after the previous round.")


def _apply_fallback(job: Job, config: dict) -> None:
    from apps.configuration.catalogue import FALLBACK_RETRY, FALLBACK_SWITCH_MODE

    fallback = config["fallback"]

    if fallback == FALLBACK_RETRY:
        job.dispatch_rounds = 0
        job.save(update_fields=["dispatch_rounds"])
        dispatch_job(job, note="Attempts exhausted — retrying from the first round.")
        return

    if fallback == FALLBACK_SWITCH_MODE and job.service_area_id:
        # Switching mode is a per-area override so the global default is left alone.
        other = (
            DISPATCH_MODE_SELECTION
            if config["mode"] == DISPATCH_MODE_AUTOMATIC
            else DISPATCH_MODE_AUTOMATIC
        )
        area = job.service_area
        area.dispatch_overrides = {**(area.dispatch_overrides or {}), "dispatch.mode": other}
        area.save(update_fields=["dispatch_overrides"])
        geo_services.invalidate_cache()
        job.dispatch_rounds = 0
        job.save(update_fields=["dispatch_rounds"])
        dispatch_job(job, note=f"Attempts exhausted — switching to {other} mode.")
        return

    if fallback == FALLBACK_SWITCH_MODE:
        # No area to scope the override to. Falling through to unclaimed is safer than
        # silently rewriting the business's global dispatch mode for every future job.
        logger.warning("dispatch.switch_mode_unavailable reference=%s", job.reference)

    mark_unclaimed(job)


def mark_unclaimed(job: Job) -> Job:
    from apps.notifications.tasks import notify_job_unclaimed

    job = transition_job(
        job, Job.Status.UNCLAIMED,
        note="Escalation exhausted without securing a driver.",
    )
    notify_job_unclaimed.delay(job.pk)
    logger.warning("dispatch.unclaimed reference=%s rounds=%s", job.reference, job.dispatch_rounds)
    return job


def assign_manually(job: Job, driver: Driver, *, staff=None) -> Job:
    """Staff intervention — the unclaimed queue's way out, and the phone-in override."""
    if not driver.is_approved:
        raise ValidationError({"driver": ["That driver is not approved for dispatch."]})
    if not driver.is_active:
        raise ValidationError({"driver": ["That driver's account is disabled."]})

    now = timezone.now()
    with transaction.atomic():
        DispatchAttempt.objects.filter(job=job, outcome=DispatchAttempt.Outcome.PENDING).update(
            outcome=DispatchAttempt.Outcome.SUPERSEDED, resolved_at=now
        )
        DispatchOffer.objects.filter(
            attempt__job=job, state=DispatchOffer.State.OFFERED
        ).update(state=DispatchOffer.State.WITHDRAWN, responded_at=now)

        job = transition_job(
            job, Job.Status.ASSIGNED, set_driver=driver, staff=staff,
            actor_type=JobStatusEvent.Actor.STAFF, note="Assigned by staff.",
        )

    refresh_eta(job)
    logger.info("dispatch.manual_assign reference=%s driver=%s", job.reference, driver.pk)
    return job


def refresh_eta(job: Job) -> Job:
    """Recomputed on the backend from the driver's position; only the figure is published."""
    from apps.geo.routing import travel_time

    if job.driver is None or job.status not in Job.DRIVER_BUSY_STATUSES:
        return job
    origin = job.driver.coordinates
    destination = job.coordinates
    if origin is None or destination is None:
        return job

    route = travel_time(origin, destination)
    if route is None:
        return job
    return set_eta(job, route.duration_seconds, route.distance_metres)


def _escalate_async(job_id: int) -> None:
    from apps.dispatch.tasks import escalate_job

    transaction.on_commit(lambda: escalate_job.delay(job_id))
