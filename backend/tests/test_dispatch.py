"""Specification section 6, end to end: both modes, rejection, timeout, escalation."""

import pytest

from apps.bookings.models import Job
from apps.dispatch.models import DispatchAttempt, DispatchOffer

pytestmark = pytest.mark.django_db


def _set(**values):
    from apps.configuration.services import set_setting

    for key, value in values.items():
        set_setting(key.replace("__", "."), value)


# --------------------------------------------------------- automatic mode ----


def test_automatic_mode_assigns_the_best_ranked_driver(make_job, driver, second_driver):
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    attempt = dispatch_job(job)
    job.refresh_from_db()

    assert attempt.mode == DispatchAttempt.Mode.AUTOMATIC
    assert attempt.offers.count() == 1
    assert job.status == Job.Status.ASSIGNED
    assert job.driver_id == driver.pk  # nearer by travel time
    assert job.eta_seconds is not None


def test_driver_accepts(make_job, driver, driver_client):
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    dispatch_job(job)

    response = driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")
    assert response.status_code == 200, response.data
    job.refresh_from_db()
    assert job.status == Job.Status.ACCEPTED
    assert job.accepted_at is not None
    assert DispatchAttempt.objects.get().outcome == DispatchAttempt.Outcome.ACCEPTED


def test_rejection_reassigns_immediately_to_the_next_best(
    make_job, driver, second_driver, driver_client
):
    """Section 6.3 — the whole point of allowing rejection is not waiting out the timeout."""
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    dispatch_job(job)
    job.refresh_from_db()
    assert job.driver_id == driver.pk

    response = driver_client.post(
        f"/api/v1/driver/jobs/{job.pk}/reject", {"reason": "Already loaded"}, format="json"
    )
    assert response.status_code == 200, response.data

    job.refresh_from_db()
    assert job.status == Job.Status.ASSIGNED
    assert job.driver_id == second_driver.pk
    assert job.dispatch_rounds == 2


def test_a_driver_who_rejected_is_never_offered_the_job_again(make_job, driver, driver_client):
    from apps.dispatch.engine import dispatch_job

    _set(dispatch__max_attempts=3)
    job = make_job()
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", format="json")

    job.refresh_from_db()
    assert job.status == Job.Status.UNCLAIMED
    assert DispatchOffer.objects.filter(driver=driver).count() == 1


def test_rejecting_a_job_you_were_not_offered_is_refused(make_job, driver, second_driver_client):
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    dispatch_job(job)
    response = second_driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", format="json")
    assert response.status_code == 400


def test_timeout_escalates_to_the_next_driver(make_job, driver, second_driver):
    """Section 6.5 — the dead-phone case, distinct from a rejection."""
    from apps.dispatch.engine import dispatch_job, expire_attempt_now

    job = make_job()
    attempt = dispatch_job(job)
    expire_attempt_now(attempt)

    job.refresh_from_db()
    attempt.refresh_from_db()
    assert attempt.outcome == DispatchAttempt.Outcome.TIMED_OUT
    assert attempt.offers.get().state == DispatchOffer.State.TIMED_OUT
    assert job.driver_id == second_driver.pk


def test_exhausting_the_attempts_marks_the_job_unclaimed(make_job, driver):
    from apps.dispatch.engine import dispatch_job, expire_attempt_now

    _set(dispatch__max_attempts=2)
    job = make_job()

    attempt = dispatch_job(job)
    expire_attempt_now(attempt)

    job.refresh_from_db()
    assert job.status == Job.Status.UNCLAIMED


def test_unclaimed_alerts_the_owner(make_job, driver, settings):
    from apps.dispatch.engine import dispatch_job, expire_attempt_now
    from apps.notifications.models import Notification

    settings.SHOP_NOTIFY_SMS = ["+447700900999"]
    _set(dispatch__max_attempts=1)

    job = make_job()
    expire_attempt_now(dispatch_job(job))

    assert Notification.objects.filter(event="unclaimed").exists()


def test_no_eligible_driver_goes_straight_to_unclaimed(make_job):
    from apps.dispatch.engine import dispatch_job

    _set(dispatch__max_attempts=1)
    job = make_job()
    attempt = dispatch_job(job)

    job.refresh_from_db()
    assert attempt.outcome == DispatchAttempt.Outcome.NO_CANDIDATES
    assert job.status == Job.Status.UNCLAIMED


# --------------------------------------------------- driver selection mode ----


def test_selection_mode_offers_to_several_drivers(make_job, driver, second_driver):
    from apps.dispatch.engine import dispatch_job

    _set(dispatch__mode="selection", dispatch__offer_batch_size=5)
    job = make_job()
    attempt = dispatch_job(job)
    job.refresh_from_db()

    assert attempt.offers.count() == 2
    assert job.status == Job.Status.DISPATCHING  # nobody has it yet
    assert job.driver_id is None


def test_first_acceptance_withdraws_the_job_from_everyone_else(
    make_job, driver, second_driver, second_driver_client, driver_client
):
    from apps.dispatch.engine import dispatch_job

    _set(dispatch__mode="selection")
    job = make_job()
    dispatch_job(job)

    assert second_driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept").status_code == 200
    job.refresh_from_db()
    assert job.driver_id == second_driver.pk
    assert job.status == Job.Status.ACCEPTED

    assert DispatchOffer.objects.get(driver=driver).state == DispatchOffer.State.WITHDRAWN
    assert driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept").status_code == 400


def test_one_rejection_leaves_the_offer_standing_with_the_others(
    make_job, driver, second_driver, driver_client
):
    """Section 6.2 — reject removes the job from that driver's list only."""
    from apps.dispatch.engine import dispatch_job

    _set(dispatch__mode="selection")
    job = make_job()
    dispatch_job(job)

    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", format="json")

    job.refresh_from_db()
    assert job.status == Job.Status.DISPATCHING
    assert job.dispatch_rounds == 1
    assert DispatchOffer.objects.get(driver=second_driver).state == DispatchOffer.State.OFFERED


def test_every_driver_rejecting_widens_the_search(make_job, driver, second_driver, make_driver,
                                                  driver_client, second_driver_client):
    from apps.dispatch.engine import dispatch_job

    _set(dispatch__mode="selection", dispatch__initial_radius_km="2", dispatch__radius_increment_km="20")
    far_driver = make_driver("+447700900209", "Far Driver", "51.6200", "-0.1900")
    job = make_job()
    dispatch_job(job)

    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", format="json")
    second_driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", format="json")

    job.refresh_from_db()
    assert job.dispatch_rounds == 2
    assert DispatchOffer.objects.filter(driver=far_driver, state=DispatchOffer.State.OFFERED).exists()


# ------------------------------------------------------------ eligibility ----


def test_only_approved_online_drivers_with_capacity_are_candidates(make_job, driver, make_driver):
    from apps.drivers.models import Driver

    pending = make_driver("+447700900211", "Pending", "51.5080", "-0.1290")
    pending.verification_status = Driver.Verification.PENDING
    pending.save()

    offline = make_driver("+447700900212", "Offline", "51.5080", "-0.1290")
    offline.is_online = False
    offline.save()

    from apps.dispatch.engine import rank_candidates

    job = make_job()
    candidates = rank_candidates(job, radius_km=10, limit=25)
    assert [candidate.driver.pk for candidate in candidates] == [driver.pk]


def test_a_driver_at_the_concurrency_cap_is_skipped(make_job, driver, second_driver):
    from apps.dispatch.engine import dispatch_job, rank_candidates

    _set(drivers__max_concurrent_jobs=1)
    dispatch_job(make_job())  # driver is now busy

    candidates = rank_candidates(make_job(), radius_km=10, limit=25)
    assert [candidate.driver.pk for candidate in candidates] == [second_driver.pk]


def test_ranking_uses_travel_time_not_straight_line(make_job, driver, second_driver, monkeypatch):
    """Section 6.4 — the driver across the river is not the nearest driver."""
    from apps.dispatch import engine
    from apps.geo.routing import Route

    def fake_matrix(origins, destination):
        # The closest driver as the crow flies is deliberately given the longer drive.
        return [Route(1800, 900), Route(300, 4000)]

    monkeypatch.setattr(engine, "travel_times", fake_matrix)

    job = make_job()
    candidates = engine.rank_candidates(job, radius_km=10, limit=25)
    assert candidates[0].driver.pk == second_driver.pk
    assert candidates[0].eta_seconds == 300


def test_drivers_outside_the_jobs_service_area_are_excluded(
    make_job, driver, second_driver, service_area
):
    from apps.geo.models import ServiceArea
    from apps.geo.services import invalidate_cache

    other = ServiceArea.objects.create(
        name="Elsewhere",
        boundary={"type": "Polygon", "coordinates": [[[10, 10], [11, 10], [11, 11], [10, 11], [10, 10]]]},
    )
    invalidate_cache()
    second_driver.service_areas.set([other])

    from apps.dispatch.engine import rank_candidates

    job = make_job()
    assert job.service_area_id == service_area.pk
    candidates = rank_candidates(job, radius_km=10, limit=25)
    assert [candidate.driver.pk for candidate in candidates] == [driver.pk]


# ---------------------------------------------------- staff intervention ----


def test_staff_can_assign_an_unclaimed_job_by_hand(staff_client, make_job, driver):
    from apps.dispatch.engine import dispatch_job, expire_attempt_now

    _set(dispatch__max_attempts=1)
    job = make_job()
    expire_attempt_now(dispatch_job(job))
    job.refresh_from_db()
    assert job.status == Job.Status.UNCLAIMED

    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/assign", {"driver_id": driver.pk}, format="json"
    )
    assert response.status_code == 200, response.data
    assert response.data["status"] == "assigned"
    assert response.data["driver"] == driver.pk


def test_staff_cannot_assign_an_unapproved_driver(staff_client, make_job, make_driver):
    from apps.drivers.models import Driver

    unapproved = make_driver("+447700900215", "Nope", "51.5080", "-0.1290")
    unapproved.verification_status = Driver.Verification.PENDING
    unapproved.save()

    job = make_job()
    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/assign", {"driver_id": unapproved.pk}, format="json"
    )
    assert response.status_code == 400


def test_staff_can_preview_the_candidate_list(staff_client, make_job, driver, second_driver):
    job = make_job()
    response = staff_client.get(f"/api/v1/jobs/{job.pk}/candidates")
    assert response.status_code == 200
    assert {row["driver_id"] for row in response.data} == {driver.pk, second_driver.pk}
    assert all(row["eta_minutes"] >= 1 for row in response.data)


def test_the_dispatch_trail_records_who_was_contacted_and_what_they_said(
    staff_client, make_job, driver, driver_client
):
    """Section 13 — 'which drivers were contacted, and did each reject or never respond?'"""
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", {"reason": "Too far"}, format="json")

    response = staff_client.get(f"/api/v1/jobs/{job.pk}")
    attempt = response.data["dispatch_attempts"][-1]
    offer = attempt["offers"][0]
    assert offer["driver_name"] == "Amir Hosseini"
    assert offer["state"] == "rejected"
    assert offer["reason"] == "Too far"


def test_per_area_overrides_beat_the_global_setting(make_job, driver, second_driver, service_area):
    from apps.geo.services import invalidate_cache

    _set(dispatch__mode="automatic")
    service_area.dispatch_overrides = {"dispatch.mode": "selection"}
    service_area.save()
    invalidate_cache()

    from apps.dispatch.engine import dispatch_job

    attempt = dispatch_job(make_job())
    assert attempt.mode == DispatchAttempt.Mode.SELECTION
    assert attempt.offers.count() == 2
