from django.conf import settings
from django.db.models import Count
from django.http import Http404
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.audit.models import AuditEvent
from apps.audit.services import record
from apps.realtime.mixins import AnnouncesConfigChange

from .google import verify_id_token
from .models import Customer, OtpCode, StaffUser
from .permissions import IsAdminStaff, IsCustomer, IsStaff
from .serializers import (
    AttachPhoneSerializer,
    CustomerSelfSerializer,
    CustomerSerializer,
    GoogleSignInSerializer,
    OtpRequestSerializer,
    OtpVerifySerializer,
    PasswordChangeSerializer,
    PasswordResetSerializer,
    RefreshSerializer,
    StaffCreateSerializer,
    StaffLoginSerializer,
    StaffUpdateSerializer,
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

        record(
            "staff",
            f"{user.name or user.email} signed in to the panel",
            actor=user.name or user.email,
            subject_type="staff",
            subject_id=user.pk,
            email=user.email,
            role=user.role,
        )
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


# ------------------------------------------------------- staff administration --


@extend_schema(tags=["staff"])
class StaffViewSet(AnnouncesConfigChange, viewsets.ModelViewSet):
    """
    Panel accounts, managed from the panel.

    Creating staff was previously a `manage.py` command on a production box,
    which meant in practice it did not happen and everybody shared the owner's
    login. Restricted to owners and shop owners: the office works the board, it
    does not decide who else can.
    """

    config_kind = "staff"
    queryset = StaffUser.objects.all()
    permission_classes = [IsAdminStaff]
    http_method_names = ["get", "post", "patch", "delete"]
    search_fields = ["name", "email"]
    ordering_fields = ["name", "date_joined", "role"]

    def get_serializer_class(self):
        if self.action == "create":
            return StaffCreateSerializer
        if self.action == "partial_update":
            return StaffUpdateSerializer
        return StaffUserSerializer

    def perform_create(self, serializer):
        user = serializer.save()
        self.announce_config_change()
        record(
            "staff",
            f"Staff account created for {user.name} ({user.get_role_display()})",
            actor=self.request.user.name or self.request.user.email,
            subject_type="staff",
            subject_id=user.pk,
            email=user.email,
            role=user.role,
        )

    def perform_update(self, serializer):
        user = serializer.save()
        self.announce_config_change()
        record(
            "staff",
            f"Staff account updated: {user.name}",
            actor=self.request.user.name or self.request.user.email,
            subject_type="staff",
            subject_id=user.pk,
            email=user.email,
            role=user.role,
            is_active=user.is_active,
        )

    def perform_destroy(self, instance):
        """
        Deactivate rather than delete.

        A staff user is referenced by every job they touched and every invoice
        they voided; removing the row would either cascade that history away or
        fail on the constraint. Losing the ability to sign in is what "remove
        this person" actually means here.
        """
        if instance.pk == self.request.user.pk:
            raise ValidationError({"detail": ["You cannot deactivate your own account."]})
        instance.is_active = False
        instance.save(update_fields=["is_active"])
        self.announce_config_change()
        record(
            "staff",
            f"Staff account deactivated: {instance.name}",
            severity=AuditEvent.Severity.WARNING,
            actor=self.request.user.name or self.request.user.email,
            subject_type="staff",
            subject_id=instance.pk,
            email=instance.email,
        )

    @extend_schema(request=PasswordResetSerializer, responses={200: StaffUserSerializer})
    @action(detail=True, methods=["post"], url_path="set-password")
    def set_password(self, request, pk=None):
        """An administrator setting somebody else's password — the forgotten-password path."""
        user = self.get_object()
        serializer = PasswordResetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])
        record(
            "staff",
            f"Password reset for {user.name} by an administrator",
            severity=AuditEvent.Severity.WARNING,
            actor=request.user.name or request.user.email,
            subject_type="staff",
            subject_id=user.pk,
        )
        return Response(StaffUserSerializer(user).data)


@extend_schema(tags=["staff"], request=PasswordChangeSerializer, responses={200: dict})
class StaffPasswordView(APIView):
    """Changing your own password. Any signed-in staff user may do this."""

    permission_classes = [IsStaff]

    def post(self, request):
        serializer = PasswordChangeSerializer(data=request.data, context={"user": request.user})
        serializer.is_valid(raise_exception=True)

        if not request.user.check_password(serializer.validated_data["current_password"]):
            raise ValidationError({"current_password": ["That is not your current password."]})

        request.user.set_password(serializer.validated_data["new_password"])
        request.user.save(update_fields=["password"])
        record(
            "staff",
            f"{request.user.name} changed their own password",
            actor=request.user.name or request.user.email,
            subject_type="staff",
            subject_id=request.user.pk,
        )
        # The tokens already issued stay valid: this is a password change, not a
        # compromise response, and signing the user out of the tab they are
        # typing in would be surprising rather than safer.
        return Response({"detail": "Password changed."})


@extend_schema(tags=["auth"], responses={200: dict})
class DevAccountsView(APIView):
    """
    The seeded accounts a development build may sign in as.

    The apps used to carry this list hard-coded (`mobile/lib/core/config.dart`),
    which meant a driver created in the panel never appeared on the sign-in
    screen and the listed numbers drifted from the database every time the seed
    changed. Reading it from the database fixes both: what the panel creates is
    immediately signable-in, and nothing is offered that does not exist.

    **Three independent locks, because this lists real phone numbers.**

    1. ``DEBUG`` must be on. A production image never serves it.
    2. The request must not be over HTTPS — a debug build talking to a deployed
       host is the case the apps' own ``devSignInEnabled`` already refuses, and
       the server refuses it here too rather than trusting the client.
    3. It returns phone numbers and names only. No tokens, no codes, no way in
       that the ordinary OTP flow does not already provide.
    """

    authentication_classes: list = []
    permission_classes = [AllowAny]

    def get(self, request):
        if not settings.DEBUG or request.is_secure():
            raise Http404

        from apps.drivers.models import Driver

        drivers = Driver.objects.filter(is_active=True).order_by("-created_at")[:25]
        customers = Customer.objects.filter(is_active=True).order_by("-id")[:25]

        return Response(
            {
                "drivers": [
                    {
                        "phone": driver.phone,
                        "name": driver.name or "Unnamed driver",
                        "state": driver.get_verification_status_display(),
                        "is_approved": driver.is_approved,
                        "is_online": driver.is_online,
                    }
                    for driver in drivers
                ],
                "customers": [
                    {
                        "phone": customer.phone,
                        "name": customer.display_name,
                        "state": "Customer",
                        "is_approved": True,
                        "is_online": False,
                    }
                    for customer in customers
                    if customer.phone
                ],
                # Section 4.1: the mock Google route resolves to a seeded account.
                "google_mock": "mock:sara@example.com" if settings.GOOGLE_OAUTH_MOCK else None,
            }
        )
