"""Point-in-polygon and great-circle distance, in plain Python.

Service areas are London-sized GeoJSON polygons and there are a handful of them, so
ray casting on the application side is cheap and keeps the SQLite dev path working.
Driver *ranking* never uses these distances — section 6.4 requires routing-engine
travel time — so this is only ever a coarse pre-filter and a containment test.
If the polygon count ever makes this hot, swap this module for PostGIS; nothing
outside it knows how containment is decided.
"""

from math import asin, cos, radians, sin, sqrt

EARTH_RADIUS_KM = 6371.0088

Point = tuple[float, float]  # (longitude, latitude), GeoJSON order.


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    d_lat = radians(lat2 - lat1)
    d_lng = radians(lng2 - lng1)
    a = sin(d_lat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lng / 2) ** 2
    return 2 * EARTH_RADIUS_KM * asin(sqrt(a))


def _ring_contains(ring: list[Point], lng: float, lat: float) -> bool:
    inside = False
    count = len(ring)
    for index in range(count):
        x1, y1 = ring[index][0], ring[index][1]
        x2, y2 = ring[(index + 1) % count][0], ring[(index + 1) % count][1]
        if (y1 > lat) != (y2 > lat):
            crossing_x = x1 + (lat - y1) * (x2 - x1) / (y2 - y1)
            if crossing_x > lng:
                inside = not inside
    return inside


def _polygon_contains(rings: list[list[Point]], lng: float, lat: float) -> bool:
    if not rings or not _ring_contains(rings[0], lng, lat):
        return False
    return not any(_ring_contains(hole, lng, lat) for hole in rings[1:])


def geojson_contains(geometry: dict, lat: float, lng: float) -> bool:
    """True when (lat, lng) falls inside a GeoJSON Polygon or MultiPolygon."""
    if not isinstance(geometry, dict):
        return False

    kind = geometry.get("type")
    coordinates = geometry.get("coordinates") or []

    if kind == "Polygon":
        return _polygon_contains(coordinates, lng, lat)
    if kind == "MultiPolygon":
        return any(_polygon_contains(polygon, lng, lat) for polygon in coordinates)
    if kind == "Feature":
        return geojson_contains(geometry.get("geometry") or {}, lat, lng)
    if kind == "FeatureCollection":
        return any(geojson_contains(feature, lat, lng) for feature in geometry.get("features") or [])
    return False


def bounds(geometry: dict) -> tuple[float, float, float, float] | None:
    """(min_lat, min_lng, max_lat, max_lng), or None for an unusable geometry."""
    points: list[Point] = []

    def walk(node):
        if isinstance(node, (list, tuple)):
            if len(node) == 2 and all(isinstance(value, (int, float)) for value in node):
                points.append((float(node[0]), float(node[1])))
            else:
                for child in node:
                    walk(child)

    if isinstance(geometry, dict):
        walk(geometry.get("coordinates") or geometry.get("geometry", {}).get("coordinates") or [])
    if not points:
        return None

    lngs = [point[0] for point in points]
    lats = [point[1] for point in points]
    return min(lats), min(lngs), max(lats), max(lngs)


def centroid(geometry: dict) -> tuple[float, float] | None:
    box = bounds(geometry)
    if box is None:
        return None
    min_lat, min_lng, max_lat, max_lng = box
    return (min_lat + max_lat) / 2, (min_lng + max_lng) / 2


def validate_geojson_polygon(geometry) -> dict:
    """Raises ValueError with a message fit to show a human."""
    if not isinstance(geometry, dict):
        raise ValueError("Boundary must be a GeoJSON object.")
    kind = geometry.get("type")
    if kind not in {"Polygon", "MultiPolygon"}:
        raise ValueError("Boundary must be a GeoJSON Polygon or MultiPolygon.")

    polygons = [geometry["coordinates"]] if kind == "Polygon" else geometry.get("coordinates") or []
    if not polygons:
        raise ValueError("Boundary has no coordinates.")

    for polygon in polygons:
        if not polygon or not polygon[0]:
            raise ValueError("Boundary has an empty ring.")
        for ring in polygon:
            if len(ring) < 4:
                raise ValueError("Each ring needs at least four positions.")
            for position in ring:
                if len(position) < 2:
                    raise ValueError("Each position needs a longitude and a latitude.")
                lng, lat = float(position[0]), float(position[1])
                if not (-180 <= lng <= 180 and -90 <= lat <= 90):
                    raise ValueError(f"Position {position} is not a valid longitude/latitude pair.")
    return geometry
