import os

os.environ.setdefault("USE_SQLITE", "1")
os.environ.setdefault("CELERY_TASK_ALWAYS_EAGER", "1")
os.environ.setdefault("SMS_PROVIDER", "mock")
os.environ.setdefault("PUSH_PROVIDER", "mock")
os.environ.setdefault("VEHICLE_LOOKUP_MOCK", "1")
os.environ.setdefault("GOOGLE_OAUTH_MOCK", "1")
os.environ.setdefault("ROUTING_PROVIDER", "mock")

from decimal import Decimal  # noqa: E402

import pytest  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

#: Central London, used as the job location in most tests.
JOB_LATITUDE = Decimal("51.5074")
JOB_LONGITUDE = Decimal("-0.1278")

LONDON_BOUNDARY = {
    "type": "Polygon",
    "coordinates": [[
        [-0.52, 51.28], [0.34, 51.28], [0.34, 51.72], [-0.52, 51.72], [-0.52, 51.28],
    ]],
}


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def owner(db):
    from apps.accounts.models import StaffUser

    return StaffUser.objects.create_user(
        email="owner@example.com", password="pw-test-1234", name="Owner", role=StaffUser.Role.OWNER
    )


@pytest.fixture
def office_staff(db):
    from apps.accounts.models import StaffUser

    return StaffUser.objects.create_user(
        email="desk@example.com", password="pw-test-1234", name="Desk", role=StaffUser.Role.STAFF
    )


@pytest.fixture
def staff_client(api, owner):
    response = api.post(
        "/api/v1/auth/staff/login", {"email": owner.email, "password": "pw-test-1234"}, format="json"
    )
    assert response.status_code == 200, response.data
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
    return api


@pytest.fixture
def customer(db):
    from apps.accounts.models import Customer

    return Customer.objects.create(
        phone="+447700900123", name="Sara Ahmadi", email="sara@example.com", is_phone_verified=True
    )


@pytest.fixture
def customer_client(customer):
    from apps.accounts.tokens import SCOPE_CUSTOMER, issue_pair

    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_pair(SCOPE_CUSTOMER, customer.pk)['access']}")
    return client


@pytest.fixture
def service_area(db):
    from apps.geo.models import ServiceArea
    from apps.geo.services import invalidate_cache

    area = ServiceArea.objects.create(name="London", boundary=LONDON_BOUNDARY, is_active=True)
    invalidate_cache()
    yield area
    invalidate_cache()


def _make_driver(phone: str, name: str, latitude: str, longitude: str):
    from django.utils import timezone

    from apps.drivers.models import Driver, DriverVehicle

    driver = Driver.objects.create(
        phone=phone,
        name=name,
        verification_status=Driver.Verification.APPROVED,
        approved_at=timezone.now(),
        is_online=True,
        went_online_at=timezone.now(),
        latitude=Decimal(latitude),
        longitude=Decimal(longitude),
        location_updated_at=timezone.now(),
    )
    DriverVehicle.objects.create(
        driver=driver, plate="AB12CDE", make="FORD", model="TRANSIT", colour="White", is_primary=True
    )
    return driver


@pytest.fixture
def driver(db):
    return _make_driver("+447700900201", "Amir Hosseini", "51.5080", "-0.1290")


@pytest.fixture
def second_driver(db):
    return _make_driver("+447700900202", "Grace Okafor", "51.5100", "-0.1350")


@pytest.fixture
def make_driver(db):
    """For tests that need a specific number of drivers at specific distances."""
    return _make_driver


def _client_for_driver(driver):
    from apps.accounts.tokens import SCOPE_DRIVER, issue_pair

    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_pair(SCOPE_DRIVER, driver.pk)['access']}")
    return client


@pytest.fixture
def driver_client(driver):
    return _client_for_driver(driver)


@pytest.fixture
def second_driver_client(second_driver):
    return _client_for_driver(second_driver)


@pytest.fixture
def client_for_driver():
    return _client_for_driver


@pytest.fixture
def job_payload():
    return {
        "plate": "AA19AAA",
        "contact_name": "Sara Ahmadi",
        "contact_phone": "07700900123",
        "issue_type": "puncture",
        "description": "Nearside front, flat.",
        "latitude": str(JOB_LATITUDE),
        "longitude": str(JOB_LONGITUDE),
        "location_text": "Outside 10 Downing Street",
        "location_source": "browser",
        "tyre_confirmation": {"confirmation_path": "confirmed"},
    }


@pytest.fixture
def make_job(db, service_area):
    """A job in ``submitted``, with dispatch not yet run."""
    from decimal import Decimal as D

    from apps.bookings.models import Job
    from apps.bookings.services import create_job
    from apps.vehicles.services import lookup_plate

    def _make(customer=None, **overrides):
        vehicle = lookup_plate("AA19AAA")
        fields = {
            "customer": customer,
            "vehicle": vehicle,
            "contact_name": "Sara Ahmadi",
            "contact_phone": "+447700900123",
            "issue_type": "puncture",
            "issue_label": "Puncture",
            "latitude": D("51.5074"),
            "longitude": D("-0.1278"),
            "location_text": "Roadside",
            "location_source": Job.LocationSource.BROWSER,
            "looked_up_tyre_size": vehicle.tyre_size_front,
            "tyre_size": vehicle.tyre_size_front,
            "auto_dispatch": False,
        }
        fields.update(overrides)
        return create_job(**fields)

    return _make


@pytest.fixture(autouse=True)
def _isolate_side_effects(settings):
    """Throttle counters and the settings cache live in the cache — without this they
    leak between tests."""
    from django.core.cache import cache

    from config.celery import app as celery_app

    cache.clear()
    settings.CELERY_TASK_ALWAYS_EAGER = True
    celery_app.conf.task_always_eager = True
    celery_app.conf.task_eager_propagates = True
    yield
    cache.clear()


@pytest.fixture(autouse=True)
def _synchronous_side_effects(monkeypatch):
    """pytest-django rolls every test back, so ``transaction.on_commit`` callbacks would
    never fire and dispatch escalation would look silently broken. Run them inline.

    The one callback that must *not* run inline is the attempt-expiry countdown: it is a
    timer, and eager Celery ignores ``countdown``, so it would time an offer out the
    instant it was made. Tests that want a timeout call ``expire_attempt_now`` directly.
    """
    from django.db import transaction

    from apps.dispatch import tasks as dispatch_tasks

    monkeypatch.setattr(transaction, "on_commit", lambda func, using=None, robust=False: func())
    monkeypatch.setattr(
        dispatch_tasks.expire_attempt, "apply_async", lambda *args, **kwargs: None
    )


@pytest.fixture
def in_progress_job(make_job, driver, driver_client):
    """A job that has reached the point where the driver is on site with the invoice open."""
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")
    for status in ("en_route", "arrived", "in_progress"):
        response = driver_client.post(
            f"/api/v1/driver/jobs/{job.pk}/status", {"status": status}, format="json"
        )
        assert response.status_code == 200, response.data
    job.refresh_from_db()
    return job
