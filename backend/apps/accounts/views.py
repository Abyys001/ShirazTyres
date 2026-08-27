from django.db.models import Count
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Driver
from .permissions import IsDriver, IsStaff
from .serializers import (
    DriverSelfSerializer,
    DriverSerializer,
    OtpRequestSerializer,
    OtpVerifySerializer,
    RefreshSerializer,
    StaffLoginSerializer,
    StaffUserSerializer,
    TokenPairSerializer,
)
from .services import get_or_create_driver, issue_otp, verify_otp
from .tokens import SCOPE_DRIVER, SCOPE_STAFF, issue_pair, refresh_pair


@extend_schema(tags=["auth"], request=OtpRequestSerializer, responses={200: dict})
class OtpRequestView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "otp_request"

    def post(self, request):
        serializer = OtpRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = issue_otp(serializer.validated_data["phone"], serializer.validated_data["purpose"])
        payload = {
            "expires_at": result.expires_at,
            "resend_after_seconds": result.resend_after_seconds,
        }
        if result.debug_code:
            payload["debug_code"] = result.debug_code
        return Response(payload)


@extend_schema(tags=["auth"], request=OtpVerifySerializer, responses={200: TokenPairSerializer})
class OtpVerifyView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "otp_verify"

    def post(self, request):
        serializer = OtpVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        verify_otp(data["phone"], data["code"])
        driver, created = get_or_create_driver(data["phone"], data.get("name", ""), data.get("email", ""))
        tokens = issue_pair(SCOPE_DRIVER, driver.pk)
        return Response(
            {**tokens, "is_new_driver": created, "driver": DriverSelfSerializer(driver).data},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@extend_schema(tags=["auth"], request=StaffLoginSerializer, responses={200: TokenPairSerializer})
class StaffLoginView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = StaffLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        return Response({**issue_pair(SCOPE_STAFF, user.pk), "user": StaffUserSerializer(user).data})


@extend_schema(tags=["auth"], request=RefreshSerializer, responses={200: TokenPairSerializer})
class ScopedRefreshView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    scope = SCOPE_STAFF

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(refresh_pair(serializer.validated_data["refresh"], self.scope))


class StaffRefreshView(ScopedRefreshView):
    scope = SCOPE_STAFF


class DriverRefreshView(ScopedRefreshView):
    scope = SCOPE_DRIVER


@extend_schema(tags=["auth"], responses={200: StaffUserSerializer})
class StaffMeView(APIView):
    permission_classes = [IsStaff]

    def get(self, request):
        return Response(StaffUserSerializer(request.user).data)


@extend_schema(tags=["drivers"], responses={200: DriverSelfSerializer})
class DriverMeView(APIView):
    permission_classes = [IsDriver]
    serializer_class = DriverSelfSerializer

    def get(self, request):
        return Response(DriverSelfSerializer(request.user).data)

    @extend_schema(request=DriverSelfSerializer, responses={200: DriverSelfSerializer})
    def patch(self, request):
        serializer = DriverSelfSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


@extend_schema(tags=["drivers"])
class DriverViewSet(viewsets.ModelViewSet):
    """Staff-side driver management — the 'shop can add drivers' half of the brief."""

    serializer_class = DriverSerializer
    permission_classes = [IsStaff]
    filterset_fields = ["is_active", "is_phone_verified"]
    search_fields = ["name", "phone", "email"]
    ordering_fields = ["created_at", "name", "last_login_at"]
    queryset = Driver.objects.annotate(vehicle_count=Count("vehicle_links")).all()

    def perform_create(self, serializer):
        serializer.save(created_by_staff=self.request.user)

    @extend_schema(request=None, responses={200: dict})
    @action(detail=True, methods=["post"], url_path="send-login-code")
    def send_login_code(self, request, pk=None):
        """Staff-added drivers get a code so they can claim the account from the app."""
        driver = self.get_object()
        result = issue_otp(driver.phone)
        return Response({"expires_at": result.expires_at, "resend_after_seconds": result.resend_after_seconds})
