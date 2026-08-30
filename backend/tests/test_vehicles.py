"""Two lookups, one cache, and the section 4.3 confirmation that hangs off them."""

import pytest

pytestmark = pytest.mark.django_db


def test_lookup_returns_dvla_and_tyre_data(api):
    response = api.get("/api/v1/public/vehicle-lookup/aa19aaa")
    assert response.status_code == 200, response.data
    assert response.data["make"] == "FORD"
    assert response.data["tyre_size_front"] == "205/55R16"
    assert response.data["display_plate"] == "AA19 AAA"


def test_unknown_plate_is_a_404_not_an_empty_record(api):
    from apps.vehicles.models import Vehicle

    assert api.get("/api/v1/public/vehicle-lookup/XX19AAA").status_code == 404
    assert not Vehicle.objects.filter(plate="XX19AAA").exists()


def test_missing_tyre_data_does_not_fail_the_lookup(api):
    """Section 9.3 — a tyre-API outage degrades the record instead of failing the call-out."""
    response = api.get("/api/v1/public/vehicle-lookup/YY19AAA")
    assert response.status_code == 200
    assert response.data["make"] == "FORD"
    assert response.data["tyre_size_front"] == ""
    assert "tyre" in response.data["lookup_error"].lower()


def test_invalid_plate_is_rejected(api):
    assert api.get("/api/v1/public/vehicle-lookup/!!").status_code == 400


def test_confirming_the_specification_records_path_a(customer_client, customer):
    created = customer_client.post("/api/v1/my-vehicles", {"plate": "AA19AAA"}, format="json")
    assert created.status_code == 201, created.data

    response = customer_client.post(
        f"/api/v1/my-vehicles/{created.data['id']}/confirm-tyre",
        {"confirmation_path": "confirmed"},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["confirmation_path"] == "confirmed"
    assert response.data["looked_up_tyre_size"] == "205/55R16"
    assert response.data["customer_tyre_size"] == ""
    assert response.data["disclaimer_accepted_at"] is None


def test_path_b_requires_the_disclaimer(customer_client):
    created = customer_client.post("/api/v1/my-vehicles", {"plate": "AA19AAA"}, format="json")
    response = customer_client.post(
        f"/api/v1/my-vehicles/{created.data['id']}/confirm-tyre",
        {"confirmation_path": "overridden", "tyre_size": "215/50R17"},
        format="json",
    )
    assert response.status_code == 400
    assert "disclaimer_accepted" in response.data["errors"]


def test_path_b_keeps_both_figures(customer_client):
    """When a technician arrives with the wrong tyre, this is what settles it."""
    created = customer_client.post("/api/v1/my-vehicles", {"plate": "AA19AAA"}, format="json")
    response = customer_client.post(
        f"/api/v1/my-vehicles/{created.data['id']}/confirm-tyre",
        {"confirmation_path": "overridden", "tyre_size": "215/50R17", "disclaimer_accepted": True},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["looked_up_tyre_size"] == "205/55R16"
    assert response.data["customer_tyre_size"] == "215/50R17"
    assert response.data["disclaimer_accepted_at"] is not None
    assert response.data["effective_tyre_size"] == "215/50R17"


def test_a_human_confirmation_is_not_overwritten_by_a_later_lookup(customer_client):
    from apps.vehicles.models import Vehicle
    from apps.vehicles.services import lookup_plate

    created = customer_client.post("/api/v1/my-vehicles", {"plate": "AA19AAA"}, format="json")
    customer_client.post(
        f"/api/v1/my-vehicles/{created.data['id']}/confirm-tyre",
        {"confirmation_path": "overridden", "tyre_size": "215/50R17", "disclaimer_accepted": True},
        format="json",
    )
    vehicle = lookup_plate("AA19AAA")
    assert vehicle.tyre_size_front == "215/50R17"
    assert vehicle.tyre_source == Vehicle.TyreSource.CUSTOMER


def test_staff_can_run_the_standalone_lookup_tool(staff_client):
    """Section 9.3 — available in the panel independent of any job."""
    from apps.vehicles.services import lookup_plate

    lookup_plate("AA19AAA")
    response = staff_client.get("/api/v1/vehicles/AA19AAA")
    assert response.status_code == 200
    assert response.data["model"] == "FOCUS"


def test_the_panel_tool_answers_for_a_plate_the_office_has_never_seen(staff_client):
    """Section 9.3 — the standalone lookup is independent of any job."""
    from apps.vehicles.models import Vehicle

    assert not Vehicle.objects.filter(plate="BD51SMR").exists()

    response = staff_client.get("/api/v1/vehicles/BD51SMR")
    assert response.status_code == 200, response.data
    assert response.data["make"] == "FORD"
    assert Vehicle.objects.filter(plate="BD51SMR").exists()


def test_the_panel_tool_still_404s_an_unknown_registration(staff_client):
    assert staff_client.get("/api/v1/vehicles/XX11XXX").status_code == 404
