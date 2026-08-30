from django.db.models import Count
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .google import verify_id_token
from .models import Customer, OtpCode
from .permissions import IsCustomer, IsStaff
from .serializers import (
    AttachPhoneSerializer,
    CustomerSelfSerializer,
    CustomerSerializer,
    GoogleSignInSerializer,
    OtpRequestSerializer,
    OtpVerifySerializer,
    RefreshSerializer,
    StaffLoginSerializer,
    StaffUserSerializer,
    TokenPairSerializer,
)
from .services import (
    attach_phone_to_customer,
    get_or_create_customer_by_google,
    get_or_create_customer_by_phone,
    issue_otp,
    verify_otp,
)
from .tokens import SCOPE_CUSTOMER, SCOPE_DRIVER, SCOPE_STAFF, issue_pair, refresh_pair


@extend_schema(tags=["auth"], request=OtpRequestSerializer, responses={200: dict})
class OtpRequestView(APIView):
    """Shared by customers and drivers — the ``purpose`` decides which flow verifies it."""

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
class CustomerOtpVerifyView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "otp_verify"

    def post(self, request):
        serializer = OtpVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        verify_otp(data["phone"], data["code"], purpose=OtpCode.Purpose.LOGIN)
        customer, created = get_or_create_customer_by_phone(
            data["phone"], data.get("name", ""), data.get("email", "")
        )
        return Response(
            {
                **issue_pair(SCOPE_CUSTOMER, customer.pk),
                "is_new_customer": created,
                "customer": CustomerSelfSerializer(customer).data,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@extend_schema(tags=["auth"], request=GoogleSignInSerializer, responses={200: TokenPairSerializer})
class GoogleSignInView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_scope = "otp_verify"

    def post(self, request):
        serializer = GoogleSignInSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = verify_id_token(serializer.validated_data["id_token"])
        customer, created = get_or_create_customer_by_google(profile)
        return Response(
            {
                **issue_pair(SCOPE_CUSTOMER, customer.pk),
                "is_new_customer": created,
                "customer": CustomerSelfSerializer(customer).data,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@extend_schema(tags=["auth"], request=AttachPhoneSerializer, responses={200: CustomerSelfSerializer})
class AttachPhoneView(APIView):
    """A Google-first customer proving a phone number, so both routes reach one account."""

    permission_classes = [IsCustomer]
    throttle_scope = "otp_verify"

    def post(self, request):
        serializer = AttachPhoneSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        verify_otp(phone, serializer.validated_data["code"], purpose=OtpCode.Purpose.LOGIN)
        customer = attach_phone_to_customer(request.user, phone)
        return Response(CustomerSelfSerializer(customer).data)


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


class CustomerRefreshView(ScopedRefreshView):
    scope = SCOPE_CUSTOMER


class DriverRefreshView(ScopedRefreshView):
    scope = SCOPE_DRIVER


@extend_schema(tags=["auth"], responses={200: StaffUserSerializer})
class StaffMeView(APIView):
    permission_classes = [IsStaff]

    def get(self, request):
        return Response(StaffUserSerializer(request.user).data)


@extend_schema(tags=["customers"], responses={200: CustomerSelfSerializer})
class CustomerMeView(APIView):
    permission_classes = [IsCustomer]
    serializer_class = CustomerSelfSerializer

    def get(self, request):
        return Response(CustomerSelfSerializer(request.user).data)

    @extend_schema(request=CustomerSelfSerializer, responses={200: CustomerSelfSerializer})
    def patch(self, request):
        serializer = CustomerSelfSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


@extend_schema(tags=["customers"])
class CustomerViewSet(viewsets.ModelViewSet):
    """Staff-side customer records, including manually created ones for phone-in jobs."""

    serializer_class = CustomerSerializer
    permission_classes = [IsStaff]
    filterset_fields = ["is_active", "is_phone_verified"]
    search_fields = ["name", "phone", "email"]
    ordering_fields = ["created_at", "name", "last_login_at"]
    queryset = Customer.objects.annotate(
        vehicle_count=Count("vehicle_links", distinct=True),
        job_count=Count("jobs", distinct=True),
    ).prefetch_related("identities")

    def perform_create(self, serializer):
        serializer.save(created_by_staff=self.request.user)

    @extend_schema(request=None, responses={200: dict})
    @action(detail=True, methods=["post"], url_path="send-login-code")
    def send_login_code(self, request, pk=None):
        """Staff-created customers get a code so they can claim the account from the app."""
        customer = self.get_object()
        if not customer.phone:
            return Response(
                {"detail": "This customer has no phone number.", "errors": {}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        result = issue_otp(customer.phone)
        return Response({"expires_at": result.expires_at, "resend_after_seconds": result.resend_after_seconds})
