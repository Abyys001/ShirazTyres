"""Specification sections 4.4, 6.4 and 10: coverage, containment, and travel time."""

from decimal import Decimal

import pytest

pytestmark = pytest.mark.django_db

INSIDE = (51.5074, -0.1278)      # Trafalgar Square
OUTSIDE = (52.4862, -1.8904)     # Birmingham


# ------------------------------------------------------------ containment ----


def test_a_point_inside_and_outside_the_polygon():
    from apps.geo.geometry import geojson_contains

    square = {"type": "Polygon", "coordinates": [[[0, 0], [2, 0], [2, 2], [0, 2], [0, 0]]]}

    assert geojson_contains(square, 1, 1) is True
    assert geojson_contains(square, 3, 1) is False


def test_a_hole_in_the_polygon_is_not_covered():
    from apps.geo.geometry import geojson_contains

    doughnut = {
        "type": "Polygon",
        "coordinates": [
            [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
            [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
        ],
    }

    assert geojson_contains(doughnut, 1, 1) is True
    assert geojson_contains(doughnut, 5, 5) is False


def test_a_multipolygon_covers_either_part():
    from apps.geo.geometry import geojson_contains

    two_islands = {
        "type": "MultiPolygon",
        "coordinates": [
            [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]],
            [[[5, 5], [6, 5], [6, 6], [5, 6], [5, 5]]],
        ],
    }

    assert geojson_contains(two_islands, 0.5, 0.5) is True
    assert geojson_contains(two_islands, 5.5, 5.5) is True
    assert geojson_contains(two_islands, 3, 3) is False


def test_a_malformed_boundary_covers_nothing():
    from apps.geo.geometry import geojson_contains

    assert geojson_contains({"type": "Point", "coordinates": [0, 0]}, 0, 0) is False
    assert geojson_contains({}, 0, 0) is False
    assert geojson_contains(None, 0, 0) is False


def test_the_distance_between_two_known_points():
    from apps.geo.geometry import haversine_km

    # Trafalgar Square to Canary Wharf, about 7 km.
    assert 6.5 < haversine_km(51.5074, -0.1278, 51.5054, -0.0235) < 7.5


# --------------------------------------------------------------- coverage ----


def test_a_location_in_the_area_is_covered(api, service_area):
    response = api.post(
        "/api/v1/public/coverage",
        {"latitude": str(INSIDE[0]), "longitude": str(INSIDE[1])}, format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["covered"] is True
    assert response.data["area"] == "London"
    assert response.data["message"] == ""


def test_a_location_outside_gets_the_configured_refusal(api, service_area):
    """Section 4.4 — the motorist is told before they fill in the rest of the form."""
    from apps.configuration.services import set_setting

    set_setting("service_areas.out_of_area_message", "We only cover Greater London.")

    response = api.post(
        "/api/v1/public/coverage",
        {"latitude": str(OUTSIDE[0]), "longitude": str(OUTSIDE[1])}, format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["covered"] is False
    assert response.data["area"] is None
    assert response.data["message"] == "We only cover Greater London."


def test_coverage_needs_no_account(api, service_area):
    """The check happens the moment the browser hands over a position."""
    response = api.post(
        "/api/v1/public/coverage", {"latitude": "51.5", "longitude": "-0.12"}, format="json"
    )
    assert response.status_code == 200


def test_an_empty_area_table_does_not_refuse_everyone(api, db):
    """During setup there are no polygons yet; refusing every request would be worse."""
    response = api.post(
        "/api/v1/public/coverage",
        {"latitude": str(OUTSIDE[0]), "longitude": str(OUTSIDE[1])}, format="json",
    )
    assert response.data["covered"] is True


def test_enforcement_can_be_switched_off(api, service_area):
    from apps.configuration.services import set_setting

    set_setting("service_areas.enforce", False)
    response = api.post(
        "/api/v1/public/coverage",
        {"latitude": str(OUTSIDE[0]), "longitude": str(OUTSIDE[1])}, format="json",
    )
    assert response.data["covered"] is True


def test_the_highest_priority_area_wins_where_they_overlap(db):
    from apps.geo.models import ServiceArea
    from apps.geo.services import find_area, invalidate_cache

    box = {"type": "Polygon", "coordinates": [[[-1, 51], [1, 51], [1, 52], [-1, 52], [-1, 51]]]}
    ServiceArea.objects.create(name="Wide", boundary=box, priority=0)
    ServiceArea.objects.create(name="Central", boundary=box, priority=10)
    invalidate_cache()

    assert find_area(*INSIDE).name == "Central"


def test_an_inactive_area_covers_nothing(db):
    from apps.geo.models import ServiceArea
    from apps.geo.services import find_area, invalidate_cache

    box = {"type": "Polygon", "coordinates": [[[-1, 51], [1, 51], [1, 52], [-1, 52], [-1, 51]]]}
    ServiceArea.objects.create(name="Retired", boundary=box, is_active=False)
    invalidate_cache()

    assert find_area(*INSIDE) is None


# ------------------------------------------------------------ area admin ----


def test_only_the_owner_redraws_the_boundary(api, staff_client, office_staff):
    box = {"type": "Polygon", "coordinates": [[[-1, 51], [1, 51], [1, 52], [-1, 52], [-1, 51]]]}
    assert staff_client.post(
        "/api/v1/service-areas", {"name": "New Area", "boundary": box}, format="json"
    ).status_code == 201

    login = api.post(
        "/api/v1/auth/staff/login",
        {"email": office_staff.email, "password": "pw-test-1234"}, format="json",
    )
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    assert api.get("/api/v1/service-areas").status_code == 200
    assert api.post(
        "/api/v1/service-areas", {"name": "Sneaky", "boundary": box}, format="json"
    ).status_code == 403


def test_an_unusable_boundary_is_refused(staff_client):
    response = staff_client.post(
        "/api/v1/service-areas",
        {"name": "Nonsense", "boundary": {"type": "Polygon", "coordinates": [[[0, 0], [1, 1]]]}},
        format="json",
    )
    assert response.status_code == 400


def test_editing_an_area_takes_effect_without_a_restart(staff_client, service_area):
    """The active-area list is cached; a stale cache would keep refusing valid jobs."""
    from apps.geo.services import find_area

    assert find_area(*INSIDE) is not None

    response = staff_client.patch(
        f"/api/v1/service-areas/{service_area.pk}", {"is_active": False}, format="json"
    )
    assert response.status_code == 200, response.data
    assert find_area(*INSIDE) is None


def test_per_area_dispatch_overrides_fall_back_to_the_global_setting(service_area):
    from apps.geo.services import area_setting

    service_area.dispatch_overrides = {"dispatch.max_attempts": 7}
    service_area.save(update_fields=["dispatch_overrides"])

    assert area_setting(service_area, "dispatch.max_attempts") == 7
    assert area_setting(service_area, "dispatch.offer_batch_size") == 5
    assert area_setting(None, "dispatch.max_attempts") == 3


def test_only_dispatch_keys_can_be_overridden_per_area(service_area):
    """A per-area VAT rate is not a thing; the whitelist is what stops it becoming one."""
    from apps.geo.services import area_setting

    service_area.dispatch_overrides = {"pricing.vat_rate": "0"}
    service_area.save(update_fields=["dispatch_overrides"])

    assert area_setting(service_area, "pricing.vat_rate") == Decimal("20.00")


# ---------------------------------------------------------------- routing ----


def test_travel_time_is_what_ranks_drivers_not_distance():
    """Section 6.4 and 10.2 — the ETA comes from the routing engine, with traffic applied."""
    from apps.geo.routing import travel_time

    route = travel_time((51.5080, -0.1290), (51.5074, -0.1278))
    assert route is not None
    assert route.duration_seconds > 0
    assert route.distance_metres > 0


def test_the_matrix_call_answers_for_every_origin():
    """One dispatch round is one routing request, not one per candidate."""
    from apps.geo.routing import travel_times

    origins = [(51.5080, -0.1290), (51.5100, -0.1350), (51.5200, -0.1500)]
    routes = travel_times(origins, (51.5074, -0.1278))

    assert len(routes) == len(origins)
    durations = [route.duration_seconds for route in routes]
    assert durations == sorted(durations)  # further away takes longer, in the mock


def test_the_traffic_correction_is_applied(settings):
    """A default routing profile is optimistic in central London — section 10.2."""
    from apps.geo import routing

    buckets = ("default", "morning_peak", "evening_peak", "overnight", "weekend")

    settings.ROUTING_TRAFFIC_FACTORS = dict.fromkeys(buckets, 2.0)
    doubled = routing.travel_time((51.5200, -0.1500), (51.5074, -0.1278))

    settings.ROUTING_TRAFFIC_FACTORS = dict.fromkeys(buckets, 1.0)
    plain = routing.travel_time((51.5200, -0.1500), (51.5074, -0.1278))

    assert doubled.duration_seconds == pytest.approx(plain.duration_seconds * 2, rel=0.01)
