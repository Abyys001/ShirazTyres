"""Specification sections 8 and 11: onboarding, verification, expiry, and tracking."""

from datetime import timedelta
from decimal import Decimal

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from apps.drivers.models import Driver, DriverDocument, DriverLocation, DriverVehicle

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def _media_root(settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)


def _upload(name="insurance.pdf"):
    return SimpleUploadedFile(name, b"%PDF-1.4 mock", content_type="application/pdf")


def _document(driver, document_type=DriverDocument.DocumentType.INSURANCE, *, days=180, status=None):
    return DriverDocument.objects.create(
        driver=driver,
        document_type=document_type,
        file=_upload(f"{document_type}.pdf"),
        expiry_date=timezone.localdate() + timedelta(days=days),
        status=status or DriverDocument.Status.APPROVED,
    )


@pytest.fixture
def pending_driver(db):
    return Driver.objects.create(phone="+447700900301", name="Reza Karimi")


@pytest.fixture
def pending_driver_client(pending_driver, client_for_driver):
    return client_for_driver(pending_driver)


# ------------------------------------------------------------ onboarding ----


def test_a_new_driver_signs_in_by_otp_and_lands_in_pending(api):
    request = api.post(
        "/api/v1/auth/otp/request", {"phone": "07700900401", "purpose": "driver"}, format="json"
    )
    assert request.status_code == 200, request.data

    response = api.post(
        "/api/v1/auth/driver/otp/verify",
        {"phone": "07700900401", "code": request.data["debug_code"], "name": "New Starter"},
        format="json",
    )
    assert response.status_code == 201, response.data
    assert response.data["is_new_driver"] is True
    assert response.data["driver"]["verification_status"] == Driver.Verification.PENDING


def test_the_van_plate_fills_in_make_model_and_colour(pending_driver_client):
    """Section 8.1 step 3."""
    response = pending_driver_client.post(
        "/api/v1/driver/vehicles", {"plate": "AB12CDE"}, format="json"
    )
    assert response.status_code == 201, response.data
    assert response.data["make"] == "FORD"
    assert response.data["model"] == "FOCUS"
    assert response.data["colour"] == "Blue"


def test_a_dvla_miss_does_not_stop_the_driver_registering_the_van(pending_driver_client):
    response = pending_driver_client.post(
        "/api/v1/driver/vehicles",
        {"plate": "XX11XXX", "make": "MERCEDES", "model": "SPRINTER", "colour": "White"},
        format="json",
    )
    assert response.status_code == 201, response.data
    assert response.data["make"] == "MERCEDES"


def test_the_van_is_its_own_record_and_never_a_customer_vehicle(pending_driver_client):
    """Section 2 — the two vehicle concepts must not share a table."""
    from apps.vehicles.models import Vehicle

    pending_driver_client.post("/api/v1/driver/vehicles", {"plate": "AB12CDE"}, format="json")
    assert not Vehicle.objects.filter(plate="AB12CDE").exists()


def test_only_one_van_is_primary(pending_driver_client):
    pending_driver_client.post("/api/v1/driver/vehicles", {"plate": "AB12CDE"}, format="json")
    pending_driver_client.post("/api/v1/driver/vehicles", {"plate": "CD34EFG"}, format="json")

    vans = pending_driver_client.get("/api/v1/driver/vehicles").data["results"]
    assert sorted(van["is_primary"] for van in vans) == [False, True]


def test_the_van_carries_its_own_mot_and_tax_dates(pending_driver_client):
    """The technician's screen leads with these, so they live on the record."""
    response = pending_driver_client.post(
        "/api/v1/driver/vehicles", {"plate": "AB12CDE"}, format="json"
    )
    assert response.status_code == 201, response.data
    assert response.data["mot_status"] == "Valid"
    assert response.data["mot_expiry_date"] == "2026-06-14"
    assert response.data["tax_status"] == "Taxed"
    assert response.data["mot_days_remaining"] is not None
    assert response.data["dvla_fetched_at"]


def test_the_van_can_be_rechecked_against_dvla(pending_driver_client):
    van = pending_driver_client.post(
        "/api/v1/driver/vehicles", {"plate": "AB12CDE"}, format="json"
    ).data
    DriverVehicle.objects.filter(pk=van["id"]).update(mot_status="", mot_expiry_date=None)

    response = pending_driver_client.post(f"/api/v1/driver/vehicles/{van['id']}/refresh")
    assert response.status_code == 200, response.data
    assert response.data["mot_status"] == "Valid"


def test_a_driver_looks_up_any_plate_and_gets_the_tyre_size(pending_driver_client):
    """The section 9.3 tool, in the technician's hand."""
    response = pending_driver_client.get("/api/v1/driver/vehicle-lookup/AB12CDE")
    assert response.status_code == 200, response.data
    assert response.data["make"] == "FORD"
    assert response.data["tyre_size_front"] == "205/55R16"
    assert response.data["mot_expiry_date"] == "2026-06-14"


def test_a_plate_dvla_does_not_know_is_a_404_not_a_crash(pending_driver_client):
    assert pending_driver_client.get("/api/v1/driver/vehicle-lookup/XX11XXX").status_code == 404


def test_the_plate_tool_is_closed_to_anyone_who_is_not_a_driver(api):
    assert api.get("/api/v1/driver/vehicle-lookup/AB12CDE").status_code in (401, 403)


def test_a_driver_uploads_a_document_and_it_starts_pending(pending_driver_client):
    response = pending_driver_client.post(
        "/api/v1/driver/documents",
        {
            "document_type": "insurance",
            "file": _upload(),
            "expiry_date": str(timezone.localdate() + timedelta(days=200)),
        },
        format="multipart",
    )
    assert response.status_code == 201, response.data
    assert response.data["status"] == DriverDocument.Status.PENDING


def test_a_driver_never_sees_the_staff_only_reference(pending_driver, pending_driver_client):
    document = _document(pending_driver)
    document.reference = "POL-123456"
    document.save(update_fields=["reference"])

    documents = pending_driver_client.get("/api/v1/driver/documents").data["results"]
    assert "reference" not in documents[0]


# ---------------------------------------------------------- verification ----


def test_a_driver_cannot_be_approved_with_documents_outstanding(staff_client, pending_driver):
    response = staff_client.post(
        f"/api/v1/drivers/{pending_driver.pk}/verification",
        {"verification_status": "approved"}, format="json",
    )
    assert response.status_code == 400
    assert "insurance" in str(response.data["errors"])


def test_approval_once_the_documents_are_in(staff_client, pending_driver):
    for document_type in ("insurance", "licence", "mot"):
        _document(pending_driver, document_type)

    response = staff_client.post(
        f"/api/v1/drivers/{pending_driver.pk}/verification",
        {"verification_status": "approved"}, format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["verification_status"] == Driver.Verification.APPROVED
    assert response.data["approved_at"] is not None


def test_an_unapproved_driver_cannot_go_online(pending_driver_client):
    """Section 8.2 — only approved drivers enter the dispatch pool."""
    response = pending_driver_client.post("/api/v1/driver/online", {"is_online": True}, format="json")
    assert response.status_code == 400
    assert "is_online" in response.data["errors"]


def test_a_pending_driver_is_told_what_they_are_waiting_for(pending_driver_client):
    """The refusal is the only thing the driver app has to explain the wait with.

    Every dispatch endpoint answers a pending driver with 403. Before this said
    who they were waiting on, the app rendered that as "could not load", which
    reads as a fault in the app rather than a decision nobody has taken yet.
    """
    for path in ("/api/v1/driver/offers", "/api/v1/driver/jobs/available", "/api/v1/driver/jobs"):
        response = pending_driver_client.get(path)
        assert response.status_code == 403, path
        assert "awaiting approval" in response.data["detail"]
        assert "accept shifts" in response.data["detail"]


def test_a_suspended_driver_is_not_told_to_wait_for_an_approval(pending_driver, pending_driver_client):
    """Suspension already happened; telling them to keep waiting is a lie."""
    pending_driver.verification_status = Driver.Verification.SUSPENDED
    pending_driver.save(update_fields=["verification_status"])

    response = pending_driver_client.get("/api/v1/driver/offers")
    assert response.status_code == 403
    assert "suspended" in response.data["detail"]
    assert "awaiting approval" not in response.data["detail"]


def test_the_approval_decision_is_written_down(staff_client, pending_driver):
    """Who let this technician in front of customers, and when."""
    from apps.audit.models import AuditEvent

    for document_type in ("insurance", "licence", "mot"):
        _document(pending_driver, document_type)

    response = staff_client.post(
        f"/api/v1/drivers/{pending_driver.pk}/verification",
        {"verification_status": "approved", "note": "References checked"}, format="json",
    )
    assert response.status_code == 200, response.data

    event = AuditEvent.objects.filter(category="driver", subject_id=str(pending_driver.pk)).first()
    assert event is not None
    assert event.payload["previous_status"] == Driver.Verification.PENDING
    assert event.payload["verification_status"] == Driver.Verification.APPROVED
    assert event.payload["note"] == "References checked"
    assert event.actor


def test_suspending_a_driver_takes_them_offline(staff_client, driver):
    response = staff_client.post(
        f"/api/v1/drivers/{driver.pk}/verification",
        {"verification_status": "suspended", "note": "Insurance query"}, format="json",
    )
    assert response.status_code == 200, response.data
    driver.refresh_from_db()
    assert driver.is_online is False


def test_staff_review_a_document(staff_client, pending_driver):
    document = _document(pending_driver, status=DriverDocument.Status.PENDING)

    response = staff_client.post(
        f"/api/v1/driver-documents/{document.pk}/review",
        {"status": "rejected", "note": "Illegible scan"}, format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["status"] == DriverDocument.Status.REJECTED
    assert response.data["review_note"] == "Illegible scan"


# --------------------------------------------------------- document expiry ----


def test_the_owner_is_warned_before_a_document_lapses(driver, settings):
    """Section 8.3, with the threshold from the configuration catalogue."""
    from apps.drivers.tasks import warn_expiring_documents
    from apps.notifications.models import Notification

    settings.SHOP_NOTIFY_SMS = ["+447700900999"]
    document = _document(driver, days=10)

    assert warn_expiring_documents() == 1
    document.refresh_from_db()
    assert document.expiry_warned_at is not None
    assert Notification.objects.filter(event="document_expiring").exists()

    # Once per document, not once per run.
    assert warn_expiring_documents() == 0


def test_a_lapsed_document_suspends_the_driver_automatically(driver):
    from apps.drivers.tasks import suspend_drivers_with_expired_documents

    _document(driver, days=-1)

    assert suspend_drivers_with_expired_documents() == 1
    driver.refresh_from_db()
    assert driver.verification_status == Driver.Verification.SUSPENDED
    assert driver.is_online is False


def test_automatic_suspension_can_be_switched_off(driver):
    from apps.configuration.services import set_setting
    from apps.drivers.tasks import suspend_drivers_with_expired_documents

    set_setting("drivers.suspend_on_expiry", False)
    _document(driver, days=-1)

    assert suspend_drivers_with_expired_documents() == 0
    driver.refresh_from_db()
    assert driver.verification_status == Driver.Verification.APPROVED


def test_the_compliance_dashboard_lists_the_queue_and_the_watchlist(
    staff_client, driver, pending_driver
):
    _document(driver, days=5)
    _document(pending_driver, status=DriverDocument.Status.PENDING)

    response = staff_client.get("/api/v1/drivers/compliance")
    assert response.status_code == 200
    assert response.data["counts"]["pending"] == 1
    assert response.data["pending_documents"] == 1
    assert response.data["expiring"][0]["driver_id"] == driver.pk


# ------------------------------------------------------------- tracking ----


def test_location_is_only_accepted_while_online(driver, driver_client):
    """Section 11.1 — tracking runs only while the driver is toggled online."""
    from apps.drivers.services import set_online

    set_online(driver, False)
    response = driver_client.post(
        "/api/v1/driver/location", {"latitude": "51.5", "longitude": "-0.12"}, format="json"
    )
    assert response.status_code == 400
    assert DriverLocation.objects.count() == 0


def test_going_offline_clears_the_last_known_position(driver, driver_client):
    response = driver_client.post("/api/v1/driver/online", {"is_online": False}, format="json")
    assert response.status_code == 200, response.data

    driver.refresh_from_db()
    assert driver.latitude is None
    assert driver.location_updated_at is None


def test_a_buffered_batch_of_fixes_is_accepted(driver, driver_client):
    """The app flushes what it stored while it had no signal."""
    now = timezone.now()
    Driver.objects.filter(pk=driver.pk).update(location_updated_at=now - timedelta(minutes=10))
    response = driver_client.post(
        "/api/v1/driver/location",
        {"points": [
            {"latitude": "51.5000", "longitude": "-0.1200",
             "recorded_at": (now - timedelta(minutes=2)).isoformat()},
            {"latitude": "51.5010", "longitude": "-0.1210",
             "recorded_at": (now - timedelta(minutes=1)).isoformat()},
        ]},
        format="json",
    )
    assert response.status_code == 202, response.data
    assert DriverLocation.objects.count() == 2

    driver.refresh_from_db()
    assert driver.latitude == Decimal("51.5010")


def test_an_out_of_order_fix_does_not_overwrite_a_newer_one(driver):
    from apps.drivers.services import record_location

    now = timezone.now()
    record_location(driver, latitude=Decimal("51.5010"), longitude=Decimal("-0.1210"), recorded_at=now)
    record_location(
        driver, latitude=Decimal("51.4000"), longitude=Decimal("-0.3000"),
        recorded_at=now - timedelta(minutes=5),
    )

    driver.refresh_from_db()
    assert driver.latitude == Decimal("51.5010")
    assert DriverLocation.objects.count() == 2  # both kept in the time series


def test_location_history_is_purged_on_the_retention_schedule(driver):
    """UK GDPR, section 18 — a defined retention period, not indefinite storage."""
    from apps.drivers.tasks import purge_driver_locations

    old = DriverLocation.objects.create(
        driver=driver, latitude=Decimal("51.5"), longitude=Decimal("-0.12"),
        recorded_at=timezone.now() - timedelta(days=200),
    )
    recent = DriverLocation.objects.create(
        driver=driver, latitude=Decimal("51.5"), longitude=Decimal("-0.12"),
        recorded_at=timezone.now() - timedelta(days=2),
    )

    assert purge_driver_locations() == 1
    assert not DriverLocation.objects.filter(pk=old.pk).exists()
    assert DriverLocation.objects.filter(pk=recent.pk).exists()


def test_the_live_map_is_staff_only(staff_client, driver_client, driver):
    """Section 4.6 — the driver's position reaches the panel and nowhere else."""
    assert staff_client.get("/api/v1/drivers/map").status_code == 200
    assert driver_client.get("/api/v1/drivers/map").status_code == 403


def test_a_customer_cannot_read_the_driver_directory(customer_client, driver):
    assert customer_client.get("/api/v1/drivers").status_code == 403
    assert customer_client.get(f"/api/v1/drivers/{driver.pk}").status_code == 403


# ------------------------------------------------- panel-created drivers ------


def test_panel_created_driver_is_approved_when_nothing_is_outstanding(staff_client, settings):
    """Staff typing in an employee IS section 8.2's administrator decision."""
    from apps.configuration.services import set_setting
    from apps.drivers.models import Driver

    set_setting("drivers.required_documents", [])

    response = staff_client.post(
        "/api/v1/drivers", {"name": "New Hire", "phone": "07700900401"}, format="json"
    )
    assert response.status_code == 201, response.data

    driver = Driver.objects.get(phone="+447700900401")
    assert driver.verification_status == Driver.Verification.APPROVED
    assert driver.approved_at is not None


def test_panel_created_driver_still_waits_on_required_documents(staff_client):
    """Section 8.2/8.3 is a compliance gate, not a formality — it is not bypassed."""
    from apps.configuration.services import set_setting
    from apps.drivers.models import Driver

    set_setting("drivers.required_documents", ["insurance"])

    response = staff_client.post(
        "/api/v1/drivers", {"name": "Undocumented", "phone": "07700900402"}, format="json"
    )
    assert response.status_code == 201, response.data

    driver = Driver.objects.get(phone="+447700900402")
    assert driver.verification_status == Driver.Verification.PENDING
    assert "insurance" in driver.missing_documents()


def test_panel_created_driver_can_sign_in_immediately(staff_client, api):
    """Whatever their verification state, the account exists and OTP resolves to it."""
    staff_client.post(
        "/api/v1/drivers", {"name": "Signs In", "phone": "07700900403"}, format="json"
    )
    issued = api.post(
        "/api/v1/auth/otp/request", {"phone": "07700900403", "purpose": "driver"}, format="json"
    )
    verified = api.post(
        "/api/v1/auth/driver/otp/verify",
        {"phone": "07700900403", "code": issued.data["debug_code"]},
        format="json",
    )
    assert verified.status_code == 200, verified.data
    assert verified.data["driver"]["name"] == "Signs In"


# ----------------------------------------------------- development sign-in ----


def test_dev_accounts_lists_drivers_from_the_database(staff_client, api, driver, settings):
    """A driver created in the panel appears on the app's sign-in screen."""
    settings.DEBUG = True
    staff_client.post(
        "/api/v1/drivers", {"name": "Fresh Driver", "phone": "07700900404"}, format="json"
    )

    response = api.get("/api/v1/auth/dev/accounts")

    assert response.status_code == 200
    phones = [row["phone"] for row in response.data["drivers"]]
    assert "+447700900404" in phones
    # Names and numbers only — never a code or a token.
    assert set(response.data["drivers"][0]) == {
        "phone", "name", "state", "is_approved", "is_online",
    }


def test_dev_accounts_is_gone_outside_debug(api, settings):
    settings.DEBUG = False
    assert api.get("/api/v1/auth/dev/accounts").status_code == 404
