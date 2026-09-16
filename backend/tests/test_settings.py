"""Specification section 12: the owner changes how the business behaves, without a deploy."""

from decimal import Decimal

import pytest

pytestmark = pytest.mark.django_db


def _get(key):
    from apps.configuration.services import get_setting

    return get_setting(key)


def test_every_setting_has_a_default_so_a_fresh_install_works(db):
    from apps.configuration.catalogue import CATALOGUE
    from apps.configuration.models import Setting
    from apps.configuration.services import all_settings

    assert Setting.objects.count() == 0
    values = all_settings()
    assert set(values) == {spec.key for spec in CATALOGUE}
    assert values["dispatch.mode"] == "automatic"
    assert values["dispatch.selection_timeout_seconds"] == 60
    assert values["dispatch.automatic_timeout_seconds"] == 90
    assert values["dispatch.offer_batch_size"] == 5
    assert values["dispatch.initial_radius_km"] == Decimal("5")
    assert values["dispatch.radius_increment_km"] == Decimal("3")
    assert values["dispatch.max_attempts"] == 3


def test_the_catalogue_covers_every_group_the_specification_lists():
    from apps.configuration.catalogue import CATALOGUE

    groups = {spec.group for spec in CATALOGUE}
    assert groups == {"dispatch", "pricing", "service_areas", "drivers", "notifications", "operational"}


def test_only_overrides_are_stored(db):
    from apps.configuration.models import Setting
    from apps.configuration.services import set_setting

    set_setting("dispatch.max_attempts", 5)

    assert Setting.objects.count() == 1
    assert _get("dispatch.max_attempts") == 5
    assert _get("dispatch.offer_batch_size") == 5  # still the default, not stored


def test_a_decimal_survives_the_json_round_trip(db):
    from apps.configuration.services import set_setting

    set_setting("pricing.callout_fee", "72.50")
    assert _get("pricing.callout_fee") == Decimal("72.50")


def test_an_unknown_key_is_refused(db):
    from rest_framework.exceptions import ValidationError

    from apps.configuration.services import set_setting

    with pytest.raises(ValidationError):
        set_setting("dispatch.something_invented", 1)


# --------------------------------------------------------------- the API ----


def test_the_panel_gets_values_and_the_metadata_to_render_them(staff_client):
    response = staff_client.get("/api/v1/settings")
    assert response.status_code == 200

    assert "dispatch.mode" in response.data["values"]
    spec = next(s for s in response.data["specs"] if s["key"] == "dispatch.mode")
    assert spec["type"] == "choice"
    assert {choice["value"] for choice in spec["choices"]} == {"automatic", "selection"}


def test_the_owner_changes_a_setting(staff_client):
    response = staff_client.patch(
        "/api/v1/settings",
        {"values": {"dispatch.mode": "selection", "pricing.callout_fee": "75.00"}},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["values"]["dispatch.mode"] == "selection"
    assert _get("pricing.callout_fee") == Decimal("75.00")


def test_office_staff_may_read_but_not_change(api, office_staff):
    login = api.post(
        "/api/v1/auth/staff/login",
        {"email": office_staff.email, "password": "pw-test-1234"}, format="json",
    )
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    assert api.get("/api/v1/settings").status_code == 200
    assert api.patch(
        "/api/v1/settings", {"values": {"dispatch.mode": "selection"}}, format="json"
    ).status_code == 403


def test_a_bad_value_is_rejected_with_the_key_named(staff_client):
    response = staff_client.patch(
        "/api/v1/settings", {"values": {"dispatch.max_attempts": "lots"}}, format="json"
    )
    assert response.status_code == 400
    assert "dispatch.max_attempts" in str(response.data["errors"])


def test_a_negative_fee_is_rejected(staff_client):
    response = staff_client.patch(
        "/api/v1/settings", {"values": {"pricing.callout_fee": "-10"}}, format="json"
    )
    assert response.status_code == 400


def test_an_unknown_key_is_rejected_by_the_api(staff_client):
    response = staff_client.patch(
        "/api/v1/settings", {"values": {"dispatch.turbo": True}}, format="json"
    )
    assert response.status_code == 400


def test_a_change_takes_effect_immediately(staff_client, make_job):
    """The cache is what makes this fast; a stale cache would make it useless."""
    staff_client.patch(
        "/api/v1/settings", {"values": {"pricing.callout_fee": "99.00"}}, format="json"
    )
    job = make_job()
    assert job.invoice.lines.get().unit_price == Decimal("99.00")


# ---------------------------------------------------- the public whitelist ----


def test_the_public_config_serves_the_customer_surfaces_anonymously(api, service_area):
    response = api.get("/api/v1/public/config")
    assert response.status_code == 200
    assert response.data["callout_fee"] == "60.00"
    assert response.data["vat_rate"] == "20.00"
    assert [issue["value"] for issue in response.data["issue_types"]]
    assert response.data["service_areas"][0]["name"] == "London"


def test_the_public_config_is_a_whitelist_not_the_whole_table(api):
    """Nothing about drivers, dispatch tuning, or notification routing leaves the panel."""
    response = api.get("/api/v1/public/config")
    leaked = [key for key in response.data if key.startswith(("dispatch", "drivers", "notifications"))]
    assert leaked == []


def test_business_hours_drive_the_open_flag(api, settings):
    from apps.configuration.services import set_setting

    set_setting("operational.business_hours", {day: [] for day in
                ("mon", "tue", "wed", "thu", "fri", "sat", "sun")})
    response = api.get("/api/v1/public/config")

    assert response.data["is_open"] is False
    assert response.data["out_of_hours_message"]


def test_a_window_running_past_midnight_is_understood():
    from datetime import datetime

    from django.utils import timezone

    from apps.configuration.hours import is_open_at
    from apps.configuration.services import set_setting

    set_setting("operational.business_hours", {
        "mon": ["22:00", "06:00"], "tue": ["22:00", "06:00"], "wed": ["22:00", "06:00"],
        "thu": ["22:00", "06:00"], "fri": ["22:00", "06:00"], "sat": ["22:00", "06:00"],
        "sun": ["22:00", "06:00"],
    })

    late = timezone.make_aware(datetime(2026, 8, 26, 23, 30))
    afternoon = timezone.make_aware(datetime(2026, 8, 26, 15, 0))

    assert is_open_at(late) is True
    assert is_open_at(afternoon) is False


# --------------------------------------------------------------- audit log ----


def test_settings_change_is_logged_with_both_values(staff_client):
    """"It used to work" is nearly always a setting — keep the before and after."""
    from apps.audit.models import AuditEvent

    response = staff_client.patch(
        "/api/v1/settings", {"values": {"pricing.callout_fee": "42.00"}}, format="json"
    )
    assert response.status_code == 200, response.data
    event = AuditEvent.objects.filter(category="settings", subject_id="pricing.callout_fee").first()
    assert event is not None
    assert "previous" in event.payload and "value" in event.payload


def test_otp_code_is_logged_only_while_sms_is_mocked(api, settings):
    """Section: the code is already public under the mock provider, never under a real one."""
    from apps.audit.models import AuditEvent

    settings.SMS_PROVIDER = "twilio"
    api.post("/api/v1/auth/otp/request", {"phone": "07700900123", "purpose": "login"}, format="json")
    event = AuditEvent.objects.filter(category="auth").first()
    assert event is not None
    assert event.payload["code"] == "[not recorded — live SMS provider]"


def test_audit_payloads_never_keep_secrets():
    from apps.audit.services import record

    event = record(
        "system", "test", api_key="sk_live_abc", password="hunter2", nested={"stripe_secret": "x"}
    )
    assert event.payload["api_key"] == "[redacted]"
    assert event.payload["password"] == "[redacted]"
    assert event.payload["nested"]["stripe_secret"] == "[redacted]"


def test_logs_and_health_are_staff_only(api, customer_client):
    for path in ("/api/v1/logs", "/api/v1/health"):
        assert api.get(path).status_code in (401, 403)
        assert customer_client.get(path).status_code in (401, 403, 404)
