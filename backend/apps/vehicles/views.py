from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsCustomer, IsStaff

from .models import CustomerVehicle, Vehicle
from .plate import normalise_plate
from .providers import VehicleLookupError
from .serializers import (
    CustomerVehicleSerializer,
    StaffTyreOverrideSerializer,
    TyreConfirmationSerializer,
    VehicleSerializer,
)
from .services import confirm_tyre_size, lookup_plate, record_confirmation


@extend_schema(tags=["vehicles"], responses={200: VehicleSerializer})
class VehicleLookupView(APIView):
    """Public plate lookup — the website, the customer app and the widget all call this.

    Always served from the cache when there is one, and there is no way to force a
    refresh from here: an anonymous caller must not be able to burn the DVLA quota.
    Staff force one through the panel's own endpoint instead.
    """

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "vehicle_lookup"

    def get(self, request, plate):
        try:
            vehicle = lookup_plate(normalise_plate(plate))
        except VehicleLookupError as exc:
            if exc.not_found:
                raise NotFound(str(exc)) from exc
            raise ValidationError({"plate": [str(exc)]}) from exc
        return Response(VehicleSerializer(vehicle).data)


@extend_schema(tags=["vehicles"])
class VehicleViewSet(viewsets.ReadOnlyModelViewSet):
    """The standalone lookup tool in the panel, independent of any job — section 9.3."""

    queryset = Vehicle.objects.all()
    serializer_class = VehicleSerializer
    permission_classes = [IsStaff]
    search_fields = ["plate", "make", "model"]
    ordering_fields = ["updated_at", "plate"]
    lookup_field = "plate"

    @extend_schema(
        parameters=[OpenApiParameter("refresh", bool, description="Bypass the cached record.")],
        responses={200: VehicleSerializer},
    )
    def retrieve(self, request, plate=None):
        """A registration the office has never seen is looked up, not 404'd.

        This is the standalone tool of section 9.3, so it has to answer for any
        plate, not only the ones that already have a job against them. The caller
        is staff, so forcing a refresh here is safe.
        """
        force = request.query_params.get("refresh") in {"1", "true", "yes"}
        try:
            vehicle = lookup_plate(normalise_plate(plate), force_refresh=force)
        except VehicleLookupError as exc:
            if exc.not_found:
                raise NotFound(str(exc)) from exc
            raise ValidationError({"plate": [str(exc)]}) from exc
        return Response(VehicleSerializer(vehicle).data)

    @extend_schema(request=StaffTyreOverrideSerializer, responses={200: VehicleSerializer})
    @action(detail=True, methods=["post"], url_path="confirm-tyre")
    def confirm_tyre(self, request, plate=None):
        serializer = StaffTyreOverrideSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        vehicle = confirm_tyre_size(
            self.get_object(), serializer.validated_data["tyre_size"], source=Vehicle.TyreSource.STAFF
        )
        return Response(VehicleSerializer(vehicle).data)

    @extend_schema(request=None, responses={200: VehicleSerializer})
    @action(detail=True, methods=["post"])
    def refresh(self, request, plate=None):
        vehicle = lookup_plate(self.get_object().plate, force_refresh=True)
        return Response(VehicleSerializer(vehicle).data)


@extend_schema(tags=["vehicles"])
class MyVehicleViewSet(viewsets.ModelViewSet):
    """A customer's saved cars, so a repeat call-out is two taps."""

    serializer_class = CustomerVehicleSerializer
    permission_classes = [IsCustomer]
    http_method_names = ["get", "post", "patch", "delete"]
    queryset = CustomerVehicle.objects.none()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CustomerVehicle.objects.none()
        return CustomerVehicle.objects.filter(customer=self.request.user).select_related("vehicle")

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            vehicle = lookup_plate(serializer.validated_data["plate"])
        except VehicleLookupError as exc:
            raise ValidationError({"plate": [str(exc)]}) from exc

        link, created = CustomerVehicle.objects.get_or_create(
            customer=request.user,
            vehicle=vehicle,
            defaults={
                "nickname": serializer.validated_data.get("nickname", ""),
                "is_primary": serializer.validated_data.get("is_primary", False),
            },
        )
        return Response(
            CustomerVehicleSerializer(link).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @extend_schema(request=TyreConfirmationSerializer, responses={200: CustomerVehicleSerializer})
    @action(detail=True, methods=["post"], url_path="confirm-tyre")
    def confirm_tyre(self, request, pk=None):
        """Section 4.3 against a saved car, so the decision carries into the next call-out."""
        serializer = TyreConfirmationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        link = self.get_object()
        data = serializer.validated_data
        link = record_confirmation(
            link,
            path=data["confirmation_path"],
            looked_up_size=link.vehicle.tyre_size_front,
            customer_size=data.get("tyre_size", ""),
            load_index=data.get("load_index", ""),
            speed_rating=data.get("speed_rating", ""),
            disclaimer_accepted=data.get("disclaimer_accepted", False),
        )
        return Response(CustomerVehicleSerializer(link).data)
