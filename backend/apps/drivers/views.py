from django.db.models import Count, Q
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.generics import ListAPIView
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import OtpCode
from apps.accounts.permissions import IsDriver, IsStaff
from apps.accounts.services import verify_otp
from apps.accounts.tokens import SCOPE_DRIVER, issue_pair
from apps.vehicles.providers import VehicleLookupError
from apps.vehicles.services import fetch_dvla_only

from .models import Driver, DriverDocument, DriverLocation, DriverVehicle
from .serializers import (
    DocumentReviewSerializer,
    DriverDocumentSelfSerializer,
    DriverDocumentSerializer,
    DriverLocationSerializer,
    DriverMapSerializer,
    DriverOtpVerifySerializer,
    DriverSelfSerializer,
    DriverSerializer,
    DriverVehicleSerializer,
    LocationBatchSerializer,
    LocationPingSerializer,
    OnlineToggleSerializer,
    VerificationUpdateSerializer,
)
from .services import (
    get_or_create_driver,
    record_location,
    review_document,
    set_online,
    set_verification,
)

DRIVER_QUERYSET = Driver.objects.prefetch_related("vehicles", "documents", "service_areas")


@extend_schema(tags=["driver-app"], request=DriverOtpVerifySerializer, responses={200: DriverSelfSerializer})
class DriverOtpVerifyView(APIView):
    """Section 8.1 step 1. A new driver lands in ``pending`` and receives no jobs until approved."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "otp_verify"

    def post(self, request):
        serializer = DriverOtpVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        verify_otp(data["phone"], data["code"], purpose=OtpCode.Purpose.DRIVER)
        driver, created = get_or_create_driver(data["phone"], data.get("name", ""))
        return Response(
            {
                **issue_pair(SCOPE_DRIVER, driver.pk),
                "is_new_driver": created,
                "driver": DriverSelfSerializer(driver).data,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@extend_schema(tags=["driver-app"], responses={200: DriverSelfSerializer})
class DriverMeView(APIView):
    permission_classes = [IsDriver]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = DriverSelfSerializer

    def get(self, request):
        return Response(DriverSelfSerializer(request.user).data)

    @extend_schema(request=DriverSelfSerializer, responses={200: DriverSelfSerializer})
    def patch(self, request):
        serializer = DriverSelfSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


@extend_schema(tags=["driver-app"], request=OnlineToggleSerializer, responses={200: DriverSelfSerializer})
class DriverOnlineView(APIView):
    permission_classes = [IsDriver]

    def post(self, request):
        serializer = OnlineToggleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        driver = set_online(request.user, serializer.validated_data["is_online"])
        return Response(DriverSelfSerializer(driver).data)


@extend_schema(tags=["driver-app"], request=LocationPingSerializer, responses={202: dict})
class DriverLocationView(APIView):
    """One fix, or a flushed buffer. Section 11.1 keeps the cadence on the device —
    a distance filter with a time cap — so this endpoint just accepts what arrives."""

    permission_classes = [IsDriver]

    def post(self, request):
        if isinstance(request.data, dict) and "points" in request.data:
            serializer = LocationBatchSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            points = serializer.validated_data["points"]
        else:
            serializer = LocationPingSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            points = [serializer.validated_data]

        for point in sorted(points, key=lambda item: item.get("recorded_at") or ""):
            record_location(request.user, **point)
        return Response({"accepted": len(points)}, status=status.HTTP_202_ACCEPTED)


@extend_schema(tags=["driver-app"])
class DriverVehicleViewSet(viewsets.ModelViewSet):
    """Section 8.1 step 3 — the plate fills in make, model and colour."""

    serializer_class = DriverVehicleSerializer
    permission_classes = [IsDriver]
    http_method_names = ["get", "post", "patch", "delete"]
    queryset = DriverVehicle.objects.none()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return DriverVehicle.objects.none()
        return DriverVehicle.objects.filter(driver=self.request.user)

    def perform_create(self, serializer):
        driver = self.request.user
        data = self._autofill(serializer.validated_data)
        if data.get("is_primary", True):
            DriverVehicle.objects.filter(driver=driver).update(is_primary=False)
        serializer.save(driver=driver, **data)

    def perform_update(self, serializer):
        data = self._autofill(serializer.validated_data) if "plate" in serializer.validated_data else {}
        if serializer.validated_data.get("is_primary"):
            DriverVehicle.objects.filter(driver=self.request.user).exclude(
                pk=serializer.instance.pk
            ).update(is_primary=False)
        serializer.save(**data)

    def _autofill(self, validated: dict) -> dict:
        """A DVLA miss must not stop a driver registering their van by hand."""
        plate = validated.get("plate")
        if not plate:
            return {}
        try:
            result = fetch_dvla_only(plate)
        except VehicleLookupError:
            return {}
        return {
            "make": validated.get("make") or result.make,
            "model": validated.get("model") or result.model,
            "colour": validated.get("colour") or result.colour,
            "year_of_manufacture": validated.get("year_of_manufacture") or result.year_of_manufacture,
        }


@extend_schema(tags=["driver-app"])
class DriverDocumentViewSet(viewsets.ModelViewSet):
    """Section 8.1 step 4. Re-uploading a document type resets it to pending review."""

    serializer_class = DriverDocumentSelfSerializer
    permission_classes = [IsDriver]
    parser_classes = [MultiPartParser, FormParser]
    http_method_names = ["get", "post", "delete"]
    queryset = DriverDocument.objects.none()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return DriverDocument.objects.none()
        return DriverDocument.objects.filter(driver=self.request.user)

    def perform_create(self, serializer):
        serializer.save(driver=self.request.user, status=DriverDocument.Status.PENDING)


@extend_schema(tags=["drivers"])
class DriverViewSet(viewsets.ModelViewSet):
    """Panel-side driver management: onboarding review, documents, service areas."""

    serializer_class = DriverSerializer
    permission_classes = [IsStaff]
    queryset = DRIVER_QUERYSET
    filterset_fields = ["verification_status", "is_active", "is_online", "service_areas"]
    search_fields = ["name", "phone", "email", "employment_reference", "vehicles__plate"]
    ordering_fields = ["created_at", "name", "verification_status", "last_login_at"]

    @extend_schema(request=VerificationUpdateSerializer, responses={200: DriverSerializer})
    @action(detail=True, methods=["post"])
    def verification(self, request, pk=None):
        serializer = VerificationUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        driver = set_verification(
            self.get_object(),
            serializer.validated_data["verification_status"],
            by=request.user,
            note=serializer.validated_data.get("note", ""),
        )
        return Response(DriverSerializer(driver).data)

    @extend_schema(responses={200: DriverDocumentSerializer(many=True)})
    @action(detail=True, methods=["get"])
    def documents(self, request, pk=None):
        queryset = self.get_object().documents.all()
        return Response(DriverDocumentSerializer(queryset, many=True).data)

    @extend_schema(responses={200: DriverLocationSerializer(many=True)})
    @action(detail=True, methods=["get"], url_path="location-history")
    def location_history(self, request, pk=None):
        queryset = DriverLocation.objects.filter(driver=self.get_object())[:200]
        return Response(DriverLocationSerializer(queryset, many=True).data)


@extend_schema(tags=["drivers"], request=DocumentReviewSerializer, responses={200: DriverDocumentSerializer})
class DocumentReviewView(APIView):
    permission_classes = [IsStaff]

    def post(self, request, pk):
        document = DriverDocument.objects.filter(pk=pk).first()
        if document is None:
            return Response({"detail": "No such document.", "errors": {}}, status=status.HTTP_404_NOT_FOUND)
        serializer = DocumentReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        document = review_document(
            document,
            serializer.validated_data["status"],
            by=request.user,
            note=serializer.validated_data.get("note", ""),
        )
        return Response(DriverDocumentSerializer(document).data)


@extend_schema(tags=["drivers"], responses={200: DriverMapSerializer(many=True)})
class DriverMapView(ListAPIView):
    """Feeds the panel's live map. The customer surfaces have no equivalent — section 4.6."""

    serializer_class = DriverMapSerializer
    permission_classes = [IsStaff]
    pagination_class = None
    queryset = Driver.objects.filter(is_online=True, latitude__isnull=False).prefetch_related("vehicles")


@extend_schema(tags=["drivers"], responses={200: dict})
class DriverComplianceView(APIView):
    """The onboarding queue and the expiry watchlist, in one call for the panel dashboard."""

    permission_classes = [IsStaff]

    def get(self, request):
        from django.utils import timezone

        from apps.configuration.services import get_setting

        warn_days = int(get_setting("drivers.expiry_warning_days"))
        today = timezone.localdate()
        horizon = today + timezone.timedelta(days=warn_days)

        expiring = DriverDocument.objects.filter(
            expiry_date__lte=horizon, status=DriverDocument.Status.APPROVED
        ).select_related("driver").order_by("expiry_date")[:100]

        counts = Driver.objects.aggregate(
            pending=Count("pk", filter=Q(verification_status=Driver.Verification.PENDING)),
            approved=Count("pk", filter=Q(verification_status=Driver.Verification.APPROVED)),
            suspended=Count("pk", filter=Q(verification_status=Driver.Verification.SUSPENDED)),
            online=Count("pk", filter=Q(is_online=True)),
        )
        return Response(
            {
                "counts": counts,
                "pending_documents": DriverDocument.objects.filter(
                    status=DriverDocument.Status.PENDING
                ).count(),
                "expiring": [
                    {
                        "document_id": document.pk,
                        "driver_id": document.driver_id,
                        "driver_name": document.driver.name,
                        "document_type": document.document_type,
                        "expiry_date": document.expiry_date,
                        "days_to_expiry": document.days_to_expiry,
                        "is_expired": document.is_expired,
                    }
                    for document in expiring
                ],
            }
        )
