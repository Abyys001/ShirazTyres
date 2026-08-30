"""Three audiences, one token format. The scope claim is the only thing keeping them apart."""

import pytest

pytestmark = pytest.mark.django_db


def _request_code(api, phone, purpose="login"):
    response = api.post(
        "/api/v1/auth/otp/request", {"phone": phone, "purpose": purpose}, format="json"
    )
    assert response.status_code == 200, response.data
    return response.data["debug_code"]


def test_customer_signs_in_with_phone_otp(api):
    code = _request_code(api, "07700900123")
    response = api.post(
        "/api/v1/auth/customer/otp/verify",
        {"phone": "07700900123", "code": code, "name": "Sara"},
        format="json",
    )
    assert response.status_code == 201, response.data
    assert response.data["is_new_customer"] is True
    assert response.data["customer"]["phone"] == "+447700900123"
    assert response.data["access"]


def test_wrong_code_is_rejected_and_counted(api):
    _request_code(api, "07700900123")
    response = api.post(
        "/api/v1/auth/customer/otp/verify",
        {"phone": "07700900123", "code": "000000"},
        format="json",
    )
    assert response.status_code == 400
    assert "attempt(s) remaining" in response.data["errors"]["code"][0]


def test_google_and_phone_resolve_to_one_account(api, settings):
    """Section 4.1 — the same person must not end up with two job histories."""
    from apps.accounts.models import Customer

    code = _request_code(api, "07700900123")
    api.post(
        "/api/v1/auth/customer/otp/verify",
        {"phone": "07700900123", "code": code, "email": "sara@example.com"},
        format="json",
    )
    assert Customer.objects.count() == 1

    google = api.post(
        "/api/v1/auth/customer/google", {"id_token": "mock:sara@example.com"}, format="json"
    )
    assert google.status_code == 200, google.data
    assert google.data["is_new_customer"] is False
    assert Customer.objects.count() == 1


def test_google_first_customer_can_attach_a_phone(api):
    from apps.accounts.models import Customer

    google = api.post(
        "/api/v1/auth/customer/google", {"id_token": "mock:new@example.com"}, format="json"
    )
    assert google.status_code == 201
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {google.data['access']}")

    code = _request_code(api, "07700900456")
    response = api.post(
        "/api/v1/auth/customer/attach-phone", {"phone": "07700900456", "code": code}, format="json"
    )
    assert response.status_code == 200, response.data
    assert response.data["phone"] == "+447700900456"
    assert Customer.objects.count() == 1


def test_attaching_a_phone_merges_a_duplicate_account(api, customer, make_job):
    """A customer who used OTP first and Google second keeps their job history."""
    from apps.accounts.models import Customer
    from apps.bookings.models import Job

    make_job(customer=customer)

    google = api.post(
        "/api/v1/auth/customer/google", {"id_token": "mock:other@example.com"}, format="json"
    )
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {google.data['access']}")
    code = _request_code(api, customer.phone)
    response = api.post(
        "/api/v1/auth/customer/attach-phone", {"phone": customer.phone, "code": code}, format="json"
    )

    assert response.status_code == 200, response.data
    assert Customer.objects.count() == 1
    surviving = Customer.objects.get()
    assert Job.objects.get().customer_id == surviving.pk


def test_driver_otp_uses_its_own_purpose(api):
    """A customer login code must not be redeemable for a driver token."""
    login_code = _request_code(api, "07700900201", purpose="login")
    response = api.post(
        "/api/v1/auth/driver/otp/verify",
        {"phone": "07700900201", "code": login_code},
        format="json",
    )
    assert response.status_code == 400

    driver_code = _request_code(api, "07700900201", purpose="driver")
    response = api.post(
        "/api/v1/auth/driver/otp/verify",
        {"phone": "07700900201", "code": driver_code, "name": "Amir"},
        format="json",
    )
    assert response.status_code == 201, response.data
    assert response.data["driver"]["verification_status"] == "pending"


def test_staff_login_and_me(api, owner):
    response = api.post(
        "/api/v1/auth/staff/login", {"email": owner.email, "password": "pw-test-1234"}, format="json"
    )
    assert response.status_code == 200
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
    assert api.get("/api/v1/auth/staff/me").data["role"] == "owner"


def test_customer_token_cannot_reach_a_panel_endpoint(customer_client):
    assert customer_client.get("/api/v1/jobs").status_code == 403


def test_driver_token_cannot_reach_a_panel_endpoint(driver_client):
    assert driver_client.get("/api/v1/jobs").status_code == 403


def test_staff_token_cannot_reach_a_customer_endpoint(staff_client):
    assert staff_client.get("/api/v1/my/jobs").status_code == 403


def test_refresh_is_scoped(api, customer):
    from apps.accounts.tokens import SCOPE_CUSTOMER, issue_pair

    tokens = issue_pair(SCOPE_CUSTOMER, customer.pk)
    wrong = api.post("/api/v1/auth/staff/refresh", {"refresh": tokens["refresh"]}, format="json")
    assert wrong.status_code in (401, 403)
    assert api.post("/api/v1/auth/customer/refresh", {"refresh": tokens["refresh"]}, format="json").status_code == 200
