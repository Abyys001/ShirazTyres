from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Driver
from apps.accounts.permissions import IsDriver, IsStaff

from .models import DriverVehicle, Vehicle
from .plate import normalise_plate
from .providers import VehicleLookupError
from .serializers import DriverVehicleSerializer, TyreConfirmSerializer, VehicleSerializer
from .services import confirm_tyre_size, lookup_plate


@extend_schema(
    tags=["vehicles"],
    parameters=[OpenApiParameter("refresh", bool, description="Bypass the cached record.")],
    responses={200: VehicleSerializer},
)
class VehicleLookupView(APIView):
    """Public plate lookup — the website widget and the app both call this."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "vehicle_lookup"

    def get(self, request, plate):
        normalised = normalise_plate(plate)
        force = request.query_params.get("refresh") in {"1", "true", "yes"}
        if force and not isinstance(request.user, (Driver,)) and not request.user.is_authenticated:
            force = False  # Anonymous callers must not be able to burn the DVLA quota.

        try:
            vehicle = lookup_plate(normalised, force_refresh=force)
        except VehicleLookupError as exc:
            if exc.not_found:
                raise NotFound(str(exc)) from exc
            raise ValidationError({"plate": [str(exc)]}) from exc
        return Response(VehicleSerializer(vehicle).data)


@extend_schema(tags=["vehicles"])
class VehicleViewSet(viewsets.ReadOnlyModelViewSet):
    """Staff-side vehicle browser plus the manual tyre-size override."""

    queryset = Vehicle.objects.all()
    serializer_class = VehicleSerializer
    permission_classes = [IsStaff]
    search_fields = ["plate", "make", "model"]
    ordering_fields = ["updated_at", "plate"]
    lookup_field = "plate"

    @extend_schema(request=TyreConfirmSerializer, responses={200: VehicleSerializer})
    @action(detail=True, methods=["post"], url_path="confirm-tyre")
    def confirm_tyre(self, request, plate=None):
        serializer = TyreConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        vehicle = confirm_tyre_size(self.get_object(), serializer.validated_data["tyre_size"], by_staff=True)
        return Response(VehicleSerializer(vehicle).data)

    @extend_schema(request=None, responses={200: VehicleSerializer})
    @action(detail=True, methods=["post"])
    def refresh(self, request, plate=None):
        vehicle = lookup_plate(self.get_object().plate, force_refresh=True)
        return Response(VehicleSerializer(vehicle).data)


@extend_schema(tags=["vehicles"])
class MyVehicleViewSet(viewsets.ModelViewSet):
    """A driver's saved vehicles — 'my car' in the app, so a callout is two taps."""

    serializer_class = DriverVehicleSerializer
    permission_classes = [IsDriver]
    http_method_names = ["get", "post", "patch", "delete"]

    queryset = DriverVehicle.objects.none()  # Real rows come from get_queryset.

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return DriverVehicle.objects.none()
        return DriverVehicle.objects.filter(driver=self.request.user).select_related("vehicle")

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            vehicle = lookup_plate(serializer.validated_data["plate"])
        except VehicleLookupError as exc:
            raise ValidationError({"plate": [str(exc)]}) from exc

        link, created = DriverVehicle.objects.get_or_create(
            driver=request.user,
            vehicle=vehicle,
            defaults={
                "nickname": serializer.validated_data.get("nickname", ""),
                "is_primary": serializer.validated_data.get("is_primary", False),
            },
        )
        return Response(
            DriverVehicleSerializer(link).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @extend_schema(request=TyreConfirmSerializer, responses={200: VehicleSerializer})
    @action(detail=True, methods=["post"], url_path="confirm-tyre")
    def confirm_tyre(self, request, pk=None):
        serializer = TyreConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        vehicle = confirm_tyre_size(self.get_object().vehicle, serializer.validated_data["tyre_size"], by_staff=False)
        return Response(VehicleSerializer(vehicle).data)
