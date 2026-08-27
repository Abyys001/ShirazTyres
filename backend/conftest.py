import os

os.environ.setdefault("USE_SQLITE", "1")
os.environ.setdefault("CELERY_TASK_ALWAYS_EAGER", "1")
os.environ.setdefault("SMS_PROVIDER", "mock")
os.environ.setdefault("PUSH_PROVIDER", "mock")
os.environ.setdefault("VEHICLE_LOOKUP_MOCK", "1")

import pytest  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402


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
def staff_client(api, owner):
    response = api.post(
        "/api/v1/auth/staff/login", {"email": owner.email, "password": "pw-test-1234"}, format="json"
    )
    assert response.status_code == 200, response.data
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
    return api


@pytest.fixture
def driver(db):
    from apps.accounts.models import Driver

    return Driver.objects.create(phone="+447700900123", name="Test Driver", is_phone_verified=True)


@pytest.fixture
def driver_client(driver):
    from apps.accounts.tokens import SCOPE_DRIVER, issue_pair

    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_pair(SCOPE_DRIVER, driver.pk)['access']}")
    return client


@pytest.fixture(autouse=True)
def _isolate_side_effects(settings):
    """Throttle counters live in the cache — without this they leak between tests."""
    from django.core.cache import cache

    from config.celery import app as celery_app

    cache.clear()
    settings.CELERY_TASK_ALWAYS_EAGER = True
    celery_app.conf.task_always_eager = True
    celery_app.conf.task_eager_propagates = True
    yield
    cache.clear()
