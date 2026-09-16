"""Submitting a job, and the parts of it the customer is and is not allowed to see."""

import pytest

pytestmark = pytest.mark.django_db


def test_customer_submits_a_job(customer_client, service_area, job_payload):
    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")
    assert response.status_code == 201, response.data
    assert response.data["status"] == "submitted"
    assert response.data["tyre_size"] == "205/55R16"
    assert response.data["tyre_confirmation_path"] == "confirmed"
    assert response.data["reference"].startswith("ST-")


def test_a_location_is_required(customer_client, service_area, job_payload):
    """Section 4.4 — a postcode is not accepted as a substitute for a position."""
    job_payload.pop("latitude")
    job_payload.pop("longitude")
    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")
    assert response.status_code == 400
    assert "location" in response.data["errors"]


def test_out_of_area_is_refused_with_the_configured_message(customer_client, service_area, job_payload):
    from apps.configuration.services import set_setting

    set_setting("service_areas.out_of_area_message", "We do not cover Manchester yet.")
    job_payload["latitude"] = "53.4808"
    job_payload["longitude"] = "-2.2426"

    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")
    assert response.status_code == 400
    assert response.data["errors"]["location"] == ["We do not cover Manchester yet."]


def test_path_b_on_submission_records_both_figures(customer_client, service_area, job_payload):
    job_payload["tyre_confirmation"] = {
        "confirmation_path": "overridden",
        "tyre_size": "225/45R18",
        "disclaimer_accepted": True,
    }
    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")

    assert response.status_code == 201, response.data
    assert response.data["looked_up_tyre_size"] == "205/55R16"
    assert response.data["customer_tyre_size"] == "225/45R18"
    assert response.data["tyre_size"] == "225/45R18"


def test_path_b_without_the_notice_is_refused(customer_client, service_area, job_payload):
    job_payload["tyre_confirmation"] = {"confirmation_path": "overridden", "tyre_size": "225/45R18"}
    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")
    assert response.status_code == 400
    assert "tyre_confirmation" in response.data["errors"]


def test_an_unlisted_issue_type_is_refused(customer_client, service_area, job_payload):
    job_payload["issue_type"] = "engine_fire"
    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")
    assert response.status_code == 400
    assert "issue_type" in response.data["errors"]


def test_out_of_hours_can_be_configured_to_refuse(customer_client, service_area, job_payload):
    from apps.configuration.services import set_setting

    set_setting("operational.business_hours", {day: [] for day in
                ("mon", "tue", "wed", "thu", "fri", "sat", "sun")})
    set_setting("operational.out_of_hours_behaviour", "refuse")

    response = customer_client.post("/api/v1/my/jobs", job_payload, format="json")
    assert response.status_code == 400
    assert response.data["errors"]["out_of_hours"] == ["We're outside our normal hours, so it may take us longer than usual to reach you."]


def test_customer_sees_the_driver_identity_but_not_their_position(
    customer_client, customer, make_job, driver, driver_client
):
    """Sections 4.6 and 4.7, together: name, photo, van — no coordinates, no phone."""
    from apps.dispatch.engine import dispatch_job

    job = make_job(customer=customer)
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")

    response = customer_client.get(f"/api/v1/my/jobs/{job.pk}")
    assert response.status_code == 200
    payload = response.data

    assert payload["driver"]["first_name"] == "Amir"
    assert payload["driver"]["vehicle_plate"] == "AB12 CDE"
    assert set(payload["driver"]) == {
        "first_name", "photo", "vehicle_make", "vehicle_model", "vehicle_colour", "vehicle_plate"
    }
    assert payload["eta_minutes"] is not None
    assert "internal_notes" not in payload
    assert "dispatch_attempts" not in payload


def test_customer_only_sees_their_own_jobs(customer_client, make_job):
    from apps.accounts.models import Customer

    other = Customer.objects.create(phone="+447700900999", name="Someone Else")
    make_job(customer=other)
    response = customer_client.get("/api/v1/my/jobs")
    assert response.status_code == 200
    assert response.data["count"] == 0


def test_customer_can_cancel_up_to_the_configured_point(customer_client, customer, make_job):
    from apps.configuration.services import set_setting

    set_setting("operational.customer_cancel_until", "accepted")
    job = make_job(customer=customer)

    response = customer_client.post(f"/api/v1/my/jobs/{job.pk}/cancel", {"reason": "Sorted it"}, format="json")
    assert response.status_code == 200, response.data
    assert response.data["status"] == "cancelled"


def test_customer_cannot_cancel_once_the_limit_has_passed(
    customer_client, customer, make_job, driver, driver_client
):
    from apps.configuration.services import set_setting
    from apps.dispatch.engine import dispatch_job

    set_setting("operational.customer_cancel_until", "accepted")
    job = make_job(customer=customer)
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/status", {"status": "en_route"}, format="json")

    response = customer_client.post(f"/api/v1/my/jobs/{job.pk}/cancel", format="json")
    assert response.status_code == 400


def test_staff_can_enter_a_phone_in_job(staff_client, service_area, job_payload):
    job_payload["source"] = "phone"
    response = staff_client.post("/api/v1/jobs", job_payload, format="json")
    assert response.status_code == 201, response.data
    assert response.data["source"] == "phone"


def test_illegal_transitions_are_refused(staff_client, make_job):
    job = make_job()
    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/status", {"status": "completed"}, format="json"
    )
    assert response.status_code == 400
    assert "status" in response.data["errors"]


def test_status_history_is_written_for_every_change(staff_client, make_job):
    job = make_job()
    staff_client.post(f"/api/v1/jobs/{job.pk}/status", {"status": "cancelled", "note": "Duplicate"},
                      format="json")
    response = staff_client.get(f"/api/v1/jobs/{job.pk}")
    statuses = [event["to_status"] for event in response.data["status_events"]]
    assert statuses == ["submitted", "cancelled"]
    assert response.data["cancellation_reason"] == "Duplicate"


def test_stats_counts_the_open_queue(staff_client, make_job, driver):
    make_job()
    make_job()
    response = staff_client.get("/api/v1/jobs/stats")
    assert response.status_code == 200
    assert response.data["submitted"] == 2
    assert response.data["open_total"] == 2
    assert response.data["drivers_online"] == 1


def test_map_lists_positioned_open_jobs(staff_client, make_job):
    """The map feed carries the tracking answers and drops what it cannot draw."""
    make_job()
    make_job(latitude=None, longitude=None)

    response = staff_client.get("/api/v1/jobs/map")

    assert response.status_code == 200
    assert len(response.data) == 1
    row = response.data[0]
    # Everything the tracking strip asks for, in one row.
    assert {"reference", "plate", "status", "contact_phone", "driver_phone",
            "eta_distance_metres", "latitude"} <= set(row)


def test_map_excludes_finished_jobs(staff_client, make_job):
    """A completed call-out is history, not something to keep a pin on."""
    from apps.bookings.models import Job

    job = make_job()
    Job.objects.filter(pk=job.pk).update(status=Job.Status.COMPLETED)

    assert staff_client.get("/api/v1/jobs/map").data == []


def test_map_is_staff_only(customer_client, make_job):
    """Section 4.6 — a driver's live position never reaches a customer surface."""
    make_job()
    assert customer_client.get("/api/v1/jobs/map").status_code in (401, 403, 404)


def test_staff_override_moves_a_job_the_lifecycle_forbids(staff_client, make_job):
    """Reality does not always take the allowed transitions — section 5 is not a cage."""
    job = make_job()
    blocked = staff_client.post(
        f"/api/v1/jobs/{job.pk}/status", {"status": "completed"}, format="json"
    )
    assert blocked.status_code == 400

    forced = staff_client.post(
        f"/api/v1/jobs/{job.pk}/status",
        {"status": "completed", "force": True, "note": "Finished on paper, driver's phone died."},
        format="json",
    )
    assert forced.status_code == 200
    assert forced.data["status"] == "completed"

    # The override is on the record, attributed, and marked as one.
    event = forced.data["status_events"][-1]
    assert event["to_status"] == "completed"
    assert event["actor_type"] == "staff"
    assert event["note"].startswith("Override:")


def test_override_demands_a_reason(staff_client, make_job):
    job = make_job()
    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/status", {"status": "completed", "force": True}, format="json"
    )
    assert response.status_code == 400
    assert "note" in response.data["errors"]


def test_normal_transitions_are_still_checked(staff_client, make_job):
    """`force` defaults off — the lifecycle still governs every ordinary move."""
    job = make_job()
    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/status", {"status": "arrived", "note": "oops"}, format="json"
    )
    assert response.status_code == 400


# ------------------------------------------------- damaged tyre positions -----


def test_customer_records_which_tyres_are_damaged(customer_client, job_payload):
    """Section 7.1: the van is loaded from this, so it travels with the job."""
    payload = {
        **job_payload,
        "damaged_positions": [
            {"position": "front_left", "severity": "flat", "note": "Kerbed it"},
            {"position": "rear_right", "severity": "deflating"},
        ],
    }
    response = customer_client.post("/api/v1/my/jobs", payload, format="json")

    assert response.status_code == 201, response.data
    assert len(response.data["damaged_positions"]) == 2
    assert response.data["damaged_summary"] == "Nearside front, Offside rear"


def test_an_unknown_wheel_is_refused(customer_client, job_payload):
    """The column is JSON, so the serializer is the only thing keeping it sane."""
    response = customer_client.post(
        "/api/v1/my/jobs",
        {**job_payload, "damaged_positions": [{"position": "front_leftish"}]},
        format="json",
    )
    assert response.status_code == 400
    assert "damaged_positions" in response.data["errors"]


def test_the_same_wheel_cannot_be_listed_twice(customer_client, job_payload):
    response = customer_client.post(
        "/api/v1/my/jobs",
        {
            **job_payload,
            "damaged_positions": [{"position": "spare"}, {"position": "spare"}],
        },
        format="json",
    )
    assert response.status_code == 400


def test_the_technician_is_told_which_wheels(driver_client, make_job, driver):
    from apps.bookings.models import Job
    from apps.bookings.services import transition_job

    job = make_job()
    job.damaged_positions = [{"position": "rear_left", "severity": "blowout", "note": ""}]
    job.save(update_fields=["damaged_positions"])
    transition_job(job, Job.Status.DISPATCHING)
    transition_job(job, Job.Status.ASSIGNED, set_driver=driver)

    response = driver_client.get(f"/api/v1/driver/jobs/{job.pk}")

    assert response.status_code == 200, response.data
    assert response.data["damaged_summary"] == "Nearside rear"
    assert response.data["damaged_positions"][0]["severity"] == "blowout"
