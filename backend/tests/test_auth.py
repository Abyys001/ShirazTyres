import pytest
from django.utils import timezone

from apps.accounts.models import Driver, OtpCode
from apps.accounts.phone import normalise_phone

pytestmark = pytest.mark.django_db


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("07700 900123", "+447700900123"),
        ("+44 7700 900123", "+447700900123"),
        ("00447700900123", "+447700900123"),
        ("7700900123", "+447700900123"),
    ],
)
def test_phone_normalisation(raw, expected):
    assert normalise_phone(raw) == expected


def test_otp_round_trip_creates_driver(api):
    request = api.post("/api/v1/auth/otp/request", {"phone": "07700900123"}, format="json")
    assert request.status_code == 200
    code = request.data["debug_code"]

    verify = api.post(
        "/api/v1/auth/otp/verify", {"phone": "07700900123", "code": code, "name": "Alex"}, format="json"
    )
    assert verify.status_code == 201
    assert verify.data["is_new_driver"] is True
    assert Driver.objects.get(phone="+447700900123").is_phone_verified


def test_otp_is_single_use(api):
    code = api.post("/api/v1/auth/otp/request", {"phone": "07700900123"}, format="json").data["debug_code"]
    api.post("/api/v1/auth/otp/verify", {"phone": "07700900123", "code": code}, format="json")

    replay = api.post("/api/v1/auth/otp/verify", {"phone": "07700900123", "code": code}, format="json")
    assert replay.status_code == 400


def test_otp_rejects_wrong_code_and_counts_attempts(api):
    api.post("/api/v1/auth/otp/request", {"phone": "07700900123"}, format="json")
    response = api.post("/api/v1/auth/otp/verify", {"phone": "07700900123", "code": "000000"}, format="json")
    assert response.status_code == 400
    assert OtpCode.objects.get(phone="+447700900123").attempts == 1


def test_expired_otp_is_rejected(api):
    api.post("/api/v1/auth/otp/request", {"phone": "07700900123"}, format="json")
    otp = OtpCode.objects.get(phone="+447700900123")
    otp.expires_at = timezone.now() - timezone.timedelta(seconds=1)
    otp.save(update_fields=["expires_at"])

    response = api.post("/api/v1/auth/otp/verify", {"phone": "07700900123", "code": "123456"}, format="json")
    assert response.status_code == 400
    assert "expired" in str(response.data).lower()


def test_driver_token_cannot_reach_staff_endpoints(driver_client):
    assert driver_client.get("/api/v1/bookings").status_code in (401, 403)


def test_staff_token_cannot_reach_driver_endpoints(staff_client):
    assert staff_client.get("/api/v1/drivers/me").status_code in (401, 403)


def test_staff_login_rejects_bad_password(api, owner):
    response = api.post(
        "/api/v1/auth/staff/login", {"email": owner.email, "password": "wrong"}, format="json"
    )
    assert response.status_code == 400
