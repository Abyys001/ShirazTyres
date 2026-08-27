from django.db.models import Count, Q
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Driver, StaffUser
from apps.accounts.permissions import IsDriver, IsStaff
from apps.accounts.services import verify_otp
from apps.vehicles.models import DriverVehicle

from .filters import BookingFilter
from .models import Booking
from .serializers import (
    BookingCreateSerializer,
    BookingDetailSerializer,
    BookingSerializer,
    BookingStaffUpdateSerializer,
    BookingStatsSerializer,
    BookingStatusUpdateSerializer,
    DriverBookingDetailSerializer,
    DriverBookingSerializer,
)
from .services import create_booking, transition_booking

BOOKING_QUERYSET = Booking.objects.select_related("vehicle", "assigned_to", "driver")


def _build_booking(serializer: BookingCreateSerializer, *, source: str, driver=None, staff=None) -> Booking:
    data = dict(serializer.validated_data)
    vehicle = serializer.resolve_vehicle(data.pop("plate", ""))
    if vehicle and not data.get("tyre_size"):
        data["tyre_size"] = vehicle.tyre_size_front
    return create_booking(
        vehicle=vehicle, driver=driver, source=source, created_by_staff=staff, **data
    )


@extend_schema(tags=["bookings"], request=BookingCreateSerializer, responses={201: BookingDetailSerializer})
class PublicBookingCreateView(APIView):
    """Website flow: no account needed, but the phone number is proved with an OTP first."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "booking_create"

    def post(self, request):
        code = request.data.get("code")
        if not code:
            raise ValidationError({"code": ["Verify your phone number to submit a request."]})

        serializer = BookingCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["contact_phone"]
        verify_otp(phone, code, purpose="booking")

        driver = Driver.objects.filter(phone=phone).first()
        booking = _build_booking(serializer, source=Booking.Source.WEBSITE, driver=driver)
        return Response(BookingDetailSerializer(booking).data, status=status.HTTP_201_CREATED)


@extend_schema(tags=["bookings"], request=BookingCreateSerializer, responses={201: BookingDetailSerializer})
class DriverBookingCreateView(APIView):
    """App flow: the driver is already authenticated, so no second OTP."""

    permission_classes = [IsDriver]
    throttle_scope = "booking_create"

    def post(self, request):
        driver: Driver = request.user
        # The account already holds the contact details, so the app need not resend
        # them — fill them in before validation rather than after it.
        data = {key: value for key, value in request.data.items() if value not in (None, "")}
        data.setdefault("contact_name", driver.name or driver.phone)
        data.setdefault("contact_phone", driver.phone)

        serializer = BookingCreateSerializer(data=data)
        serializer.is_valid(raise_exception=True)

        if not serializer.validated_data.get("plate"):
            primary = DriverVehicle.objects.filter(driver=driver).order_by("-is_primary").first()
            if primary:
                serializer.validated_data["plate"] = primary.vehicle.plate

        booking = _build_booking(serializer, source=Booking.Source.APP, driver=driver)
        return Response(DriverBookingDetailSerializer(booking).data, status=status.HTTP_201_CREATED)


class DriverBookingScopedMixin:
    permission_classes = [IsDriver]
    queryset = Booking.objects.none()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Booking.objects.none()
        return BOOKING_QUERYSET.filter(driver=self.request.user)


@extend_schema(tags=["bookings"], responses={200: DriverBookingSerializer})
class DriverBookingListView(DriverBookingScopedMixin, ListAPIView):
    serializer_class = DriverBookingSerializer


@extend_schema(tags=["bookings"], responses={200: DriverBookingDetailSerializer})
class DriverBookingDetailView(DriverBookingScopedMixin, RetrieveAPIView):
    serializer_class = DriverBookingDetailSerializer

    def get_queryset(self):
        return super().get_queryset().prefetch_related("status_events")


@extend_schema(tags=["bookings"])
class BookingViewSet(viewsets.ModelViewSet):
    """The panel's main surface: list, detail, manual creation, status changes."""

    queryset = BOOKING_QUERYSET
    permission_classes = [IsStaff]
    filterset_class = BookingFilter
    search_fields = ["reference", "contact_name", "contact_phone", "vehicle__plate", "location_text"]
    ordering_fields = ["created_at", "status", "updated_at"]
    http_method_names = ["get", "post", "patch"]

    def get_serializer_class(self):
        if self.action == "create":
            return BookingCreateSerializer
        if self.action == "partial_update":
            return BookingStaffUpdateSerializer
        if self.action == "retrieve":
            return BookingDetailSerializer
        return BookingSerializer

    def create(self, request, *args, **kwargs):
        serializer = BookingCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        source = request.data.get("source", Booking.Source.PANEL)
        if source not in Booking.Source.values:
            source = Booking.Source.PANEL
        driver = Driver.objects.filter(phone=serializer.validated_data["contact_phone"]).first()
        booking = _build_booking(serializer, source=source, driver=driver, staff=request.user)
        return Response(BookingDetailSerializer(booking).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=BookingStatusUpdateSerializer, responses={200: BookingDetailSerializer})
    @action(detail=True, methods=["patch"])
    def status(self, request, pk=None):
        serializer = BookingStatusUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        assigned_to = None
        if serializer.validated_data.get("assigned_to_id"):
            assigned_to = StaffUser.objects.filter(
                pk=serializer.validated_data["assigned_to_id"], is_active=True
            ).first()
            if assigned_to is None:
                raise ValidationError({"assigned_to_id": ["No such active staff member."]})

        booking = transition_booking(
            self.get_object(),
            serializer.validated_data["status"],
            changed_by=request.user,
            note=serializer.validated_data.get("note", ""),
            assigned_to=assigned_to,
        )
        return Response(BookingDetailSerializer(booking).data)

    @extend_schema(responses={200: BookingStatsSerializer})
    @action(detail=False, methods=["get"])
    def stats(self, request):
        today = timezone.localtime().replace(hour=0, minute=0, second=0, microsecond=0)
        counts = Booking.objects.aggregate(
            received=Count("pk", filter=Q(status=Booking.Status.RECEIVED)),
            assigned=Count("pk", filter=Q(status=Booking.Status.ASSIGNED)),
            in_progress=Count("pk", filter=Q(status=Booking.Status.IN_PROGRESS)),
            completed_today=Count("pk", filter=Q(status=Booking.Status.COMPLETED, completed_at__gte=today)),
        )
        counts["open_total"] = counts["received"] + counts["assigned"] + counts["in_progress"]
        return Response(BookingStatsSerializer(counts).data)
