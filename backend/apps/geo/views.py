from django.db.models import Count
from drf_spectacular.utils import extend_schema
from rest_framework import viewsets
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsOwner, IsStaff
from apps.configuration.services import get_setting
from apps.realtime.mixins import AnnouncesConfigChange

from .models import ServiceArea
from .serializers import CoverageCheckSerializer, CoverageResultSerializer, ServiceAreaSerializer
from .services import find_area, invalidate_cache, is_covered


@extend_schema(tags=["service-areas"])
class ServiceAreaViewSet(AnnouncesConfigChange, viewsets.ModelViewSet):
    config_kind = "service-areas"

    queryset = ServiceArea.objects.annotate(driver_count=Count("drivers"))
    serializer_class = ServiceAreaSerializer
    filterset_fields = ["is_active"]
    search_fields = ["name"]
    ordering_fields = ["name", "priority", "updated_at"]

    def get_permissions(self):
        # Reading coverage is part of triage; redrawing it is a business decision.
        return [IsStaff()] if self.request.method in ("GET", "HEAD", "OPTIONS") else [IsOwner()]

    def perform_create(self, serializer):
        super().perform_create(serializer)
        invalidate_cache()

    def perform_update(self, serializer):
        super().perform_update(serializer)
        invalidate_cache()

    def perform_destroy(self, instance):
        super().perform_destroy(instance)
        invalidate_cache()


@extend_schema(
    tags=["service-areas"],
    request=CoverageCheckSerializer,
    responses={200: CoverageResultSerializer},
)
class CoverageCheckView(APIView):
    """Called by the customer surfaces the moment a location is captured, so a
    motorist outside the area finds out before filling in the rest of the form."""

    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = CoverageCheckSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        latitude = serializer.validated_data["latitude"]
        longitude = serializer.validated_data["longitude"]

        covered = is_covered(latitude, longitude)
        area = find_area(latitude, longitude)
        return Response(
            CoverageResultSerializer(
                {
                    "covered": covered,
                    "area": area.name if area else None,
                    "message": "" if covered else get_setting("service_areas.out_of_area_message"),
                }
            ).data
        )
