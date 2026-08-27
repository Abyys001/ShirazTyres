import pytest

from apps.vehicles.models import Vehicle
from apps.vehicles.plate import format_plate, normalise_plate
from apps.vehicles.providers import VehicleLookupError
from apps.vehicles.services import lookup_plate

pytestmark = pytest.mark.django_db


def test_plate_normalisation_and_display():
    assert normalise_plate("ab12 cde") == "AB12CDE"
    assert format_plate("AB12CDE") == "AB12 CDE"


def test_lookup_merges_dvla_and_tyre_data():
    vehicle = lookup_plate("AB12CDE")
    assert vehicle.make == "FORD"
    assert vehicle.tyre_size_front == "205/55R16"
    assert vehicle.tyre_source == Vehicle.TyreSource.API


def test_lookup_is_cached(monkeypatch):
    lookup_plate("AB12CDE")

    def explode(*args, **kwargs):
        raise AssertionError("provider should not be called for a fresh record")

    monkeypatch.setattr("apps.vehicles.services.get_dvla_provider", explode)
    monkeypatch.setattr("apps.vehicles.services.get_tyre_provider", explode)
    assert lookup_plate("AB12CDE").make == "FORD"


def test_unknown_plate_raises_and_leaves_no_row():
    with pytest.raises(VehicleLookupError):
        lookup_plate("XX99XXX")
    assert not Vehicle.objects.filter(plate="XX99XXX").exists()


def test_tyre_failure_does_not_fail_the_lookup():
    vehicle = lookup_plate("YY19ABC")
    assert vehicle.make == "FORD"
    assert vehicle.tyre_size_front == ""
    assert "tyre" in vehicle.lookup_error.lower()


def test_driver_confirmation_survives_refresh(driver_client):
    lookup_plate("AB12CDE")
    response = driver_client.post("/api/v1/my-vehicles", {"plate": "AB12CDE"}, format="json")
    assert response.status_code == 201, response.data

    link_id = response.data["id"]
    confirmed = driver_client.post(
        f"/api/v1/my-vehicles/{link_id}/confirm-tyre", {"tyre_size": "215/50R17"}, format="json"
    )
    assert confirmed.status_code == 200

    refreshed = lookup_plate("AB12CDE")
    assert refreshed.tyre_size_front == "215/50R17"
    assert refreshed.tyre_source == Vehicle.TyreSource.DRIVER


def test_public_lookup_endpoint(api):
    response = api.get("/api/v1/vehicle-lookup/ab12cde")
    assert response.status_code == 200
    assert response.data["display_plate"] == "AB12 CDE"


def test_public_lookup_404_for_unknown_plate(api):
    assert api.get("/api/v1/vehicle-lookup/XX99XXX").status_code == 404
