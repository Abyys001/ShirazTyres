import pytest

from apps.accounts.models import OtpCode
from apps.bookings.models import Booking
from apps.bookings.services import create_booking, transition_booking
from apps.notifications.models import Notification

pytestmark = pytest.mark.django_db


def make_booking(**overrides):
    payload = {
        "contact_name": "Alex",
        "contact_phone": "+447700900123",
        "issue_type": Booking.Issue.PUNCTURE,
        "location_text": "M1 J12",
    }
    payload.update(overrides)
    return create_booking(**payload)


def test_booking_gets_reference_and_history():
    booking = make_booking()
    assert booking.reference.startswith("ST-")
    assert booking.status_events.count() == 1


def test_valid_transition_chain(owner):
    booking = make_booking()
    transition_booking(booking, Booking.Status.ASSIGNED, changed_by=owner)
    transition_booking(booking, Booking.Status.IN_PROGRESS, changed_by=owner)
    transition_booking(booking, Booking.Status.COMPLETED, changed_by=owner)

    booking.refresh_from_db()
    assert booking.completed_at is not None
    assert booking.status_events.count() == 4


def test_completed_booking_is_terminal(owner):
    booking = make_booking()
    transition_booking(booking, Booking.Status.IN_PROGRESS, changed_by=owner)
    transition_booking(booking, Booking.Status.COMPLETED, changed_by=owner)

    with pytest.raises(Exception):
        transition_booking(booking, Booking.Status.ASSIGNED, changed_by=owner)


def test_cannot_skip_straight_to_completed(owner):
    booking = make_booking()
    with pytest.raises(Exception):
        transition_booking(booking, Booking.Status.COMPLETED, changed_by=owner)


def test_new_booking_notifies_the_shop(settings, django_capture_on_commit_callbacks):
    settings.SHOP_NOTIFY_SMS = ["+447700900999"]
    settings.SHOP_NOTIFY_EMAIL = ["owner@shiraztyres.co.uk"]

    with django_capture_on_commit_callbacks(execute=True):
        booking = make_booking()

    channels = set(Notification.objects.filter(booking=booking).values_list("channel", flat=True))
    assert channels == {"sms", "email"}


def test_public_booking_requires_verified_otp(api):
    api.post("/api/v1/auth/otp/request", {"phone": "07700900123", "purpose": "booking"}, format="json")
    code = OtpCode.objects.filter(phone="+447700900123", purpose="booking").first()
    assert code is not None

    response = api.post(
        "/api/v1/public/bookings",
        {
            "contact_name": "Alex",
            "contact_phone": "07700900123",
            "issue_type": "puncture",
            "location_text": "M1 J12",
            "code": "000000",
        },
        format="json",
    )
    assert response.status_code == 400


def test_public_booking_succeeds_with_correct_code(api):
    issued = api.post(
        "/api/v1/auth/otp/request", {"phone": "07700900123", "purpose": "booking"}, format="json"
    )
    response = api.post(
        "/api/v1/public/bookings",
        {
            "contact_name": "Alex",
            "contact_phone": "07700900123",
            "plate": "AB12CDE",
            "issue_type": "puncture",
            "location_text": "M1 J12",
            "code": issued.data["debug_code"],
        },
        format="json",
    )
    assert response.status_code == 201, response.data
    assert response.data["vehicle"]["make"] == "FORD"
    assert response.data["tyre_size"] == "205/55R16"


def test_staff_can_create_and_progress_a_phone_booking(staff_client):
    created = staff_client.post(
        "/api/v1/bookings",
        {
            "contact_name": "Walk-in",
            "contact_phone": "07700900444",
            "issue_type": "blowout",
            "location_text": "Forecourt",
            "source": "phone",
        },
        format="json",
    )
    assert created.status_code == 201, created.data
    booking_id = created.data["id"]

    updated = staff_client.patch(
        f"/api/v1/bookings/{booking_id}/status", {"status": "assigned"}, format="json"
    )
    assert updated.status_code == 200
    assert updated.data["status"] == "assigned"
    assert updated.data["assigned_to"]["email"] == "owner@example.com"


def test_driver_sees_only_their_own_bookings(driver_client, driver):
    make_booking(driver=driver)
    make_booking(contact_phone="+447700900999")

    response = driver_client.get("/api/v1/my/bookings")
    assert response.status_code == 200
    assert response.data["count"] == 1


def test_stats_endpoint(staff_client):
    make_booking()
    response = staff_client.get("/api/v1/bookings/stats")
    assert response.status_code == 200
    assert response.data["received"] == 1
    assert response.data["open_total"] == 1
