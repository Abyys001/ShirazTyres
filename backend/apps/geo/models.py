from django.db import models

from .geometry import centroid, geojson_contains


class ServiceArea(models.Model):
    """A polygon the business will travel to, with optional dispatch overrides.

    The boundary is stored as GeoJSON rather than a PostGIS geometry: see the note in
    ``apps.geo.geometry`` for why, and for what to change if that stops being true.
    """

    name = models.CharField(max_length=120, unique=True)
    boundary = models.JSONField(help_text="GeoJSON Polygon or MultiPolygon, [longitude, latitude] order.")
    is_active = models.BooleanField(default=True, db_index=True)
    priority = models.SmallIntegerField(
        default=0, help_text="Higher wins where areas overlap."
    )
    dispatch_overrides = models.JSONField(
        default=dict, blank=True,
        help_text="Setting keys from the dispatch group that differ inside this area.",
    )
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-priority", "name")

    def __str__(self):
        return self.name

    def contains(self, latitude: float, longitude: float) -> bool:
        return geojson_contains(self.boundary, float(latitude), float(longitude))

    @property
    def centre(self) -> dict | None:
        point = centroid(self.boundary)
        return None if point is None else {"latitude": point[0], "longitude": point[1]}
