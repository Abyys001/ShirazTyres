from drf_spectacular.utils import extend_schema
from rest_framework import status as http_status
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.generics import ListAPIView
from rest_framework.response import Response

from apps.audit.models import AuditEvent
from apps.audit.services import record

from apps.accounts.permissions import IsAdminStaff, IsApprovedDriver, IsOwner, IsStaff
from apps.realtime.mixins import AnnouncesConfigChange

from .models import Invoice, ServiceItem
from .serializers import (
    AddLineSerializer,
    InvoiceCreateSerializer,
    InvoiceSerializer,
    PaymentSerializer,
    RefundSerializer,
    ServiceItemSerializer,
)
from .services import (
    add_line,
    mark_paid,
    record_refund,
    remove_line,
    send_for_payment,
    void_invoice,
)


@extend_schema(tags=["billing"])
class ServiceItemViewSet(AnnouncesConfigChange, viewsets.ModelViewSet):
    """The owner's price list. Drivers read it; only the owner sets the prices."""

    config_kind = "service-items"
    queryset = ServiceItem.objects.all()
    serializer_class = ServiceItemSerializer
    filterset_fields = ["kind", "is_active"]
    search_fields = ["name", "code"]
    ordering_fields = ["sort_order", "name", "unit_price"]

    def get_permissions(self):
        return [IsStaff()] if self.request.method in ("GET", "HEAD", "OPTIONS") else [IsOwner()]


@extend_schema(tags=["billing"], responses={200: ServiceItemSerializer(many=True)})
class DriverServiceItemListView(ListAPIView):
    """What the driver app puts on its invoice screen."""

    serializer_class = ServiceItemSerializer
    permission_classes = [IsApprovedDriver]
    pagination_class = None
    queryset = ServiceItem.objects.filter(is_active=True)


@extend_schema(tags=["billing"])
class InvoiceViewSet(viewsets.ModelViewSet):
    """
    The office's invoices: raise, edit, issue, collect, void, refund.

    A ModelViewSet now rather than read-only — an invoice can be raised for
    something that is not a call-out, and the lines on a draft have to be
    editable from the panel and not only from the driver's phone.
    """

    queryset = Invoice.objects.select_related("job", "customer").prefetch_related("lines")
    serializer_class = InvoiceSerializer
    permission_classes = [IsStaff]
    http_method_names = ["get", "post", "patch", "delete"]
    filterset_fields = ["status", "payment_method", "stripe_mode"]
    search_fields = ["reference", "job__reference", "payment_reference", "bill_to_name"]
    ordering_fields = ["created_at", "total", "issued_at"]

    def get_serializer_class(self):
        return InvoiceCreateSerializer if self.action == "create" else InvoiceSerializer

    def create(self, request, *args, **kwargs):
        serializer = InvoiceCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invoice = serializer.save()
        record(
            "billing",
            f"Invoice {invoice.display_reference} raised for {invoice.bill_to or 'nobody named'}",
            actor=request.user.name or request.user.email,
            subject_type="invoice",
            subject_id=invoice.pk,
        )
        return Response(InvoiceSerializer(invoice).data, status=http_status.HTTP_201_CREATED)

    def perform_destroy(self, instance):
        """Only a draft can be deleted; anything issued is voided, never removed."""
        if instance.status != Invoice.Status.DRAFT:
            raise ValidationError(
                {"detail": ["An issued invoice is voided, not deleted — the record has to stand."]}
            )
        record(
            "billing",
            f"Draft invoice {instance.display_reference} deleted",
            severity=AuditEvent.Severity.WARNING,
            actor=self.request.user.name or self.request.user.email,
            subject_type="invoice",
            subject_id=instance.pk,
        )
        instance.delete()

    @extend_schema(request=AddLineSerializer, responses={200: InvoiceSerializer})
    @action(detail=True, methods=["post"], url_path="lines")
    def add_line(self, request, pk=None):
        invoice = self.get_object()
        serializer = AddLineSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        item = None
        if serializer.validated_data.get("service_item_id"):
            item = ServiceItem.objects.filter(
                pk=serializer.validated_data["service_item_id"]
            ).first()
            if item is None:
                raise ValidationError({"service_item_id": ["No such price list item."]})

        add_line(
            invoice,
            description=serializer.validated_data.get("description", ""),
            unit_price=serializer.validated_data.get("unit_price"),
            quantity=serializer.validated_data.get("quantity", 1),
            kind=serializer.validated_data.get("kind", ServiceItem.Kind.PART),
            service_item=item,
        )
        invoice.refresh_from_db()
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(responses={200: InvoiceSerializer})
    @action(detail=True, methods=["delete"], url_path="lines/(?P<line_id>[^/.]+)")
    def remove_line(self, request, pk=None, line_id=None):
        invoice = self.get_object()
        line = invoice.lines.filter(pk=line_id).first()
        if line is None:
            raise ValidationError({"detail": ["No such line on this invoice."]})
        remove_line(line)
        invoice.refresh_from_db()
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(request=None, responses={200: InvoiceSerializer})
    @action(detail=True, methods=["post"], url_path="send-payment-link")
    def send_payment_link(self, request, pk=None):
        """Section 7.1 step 5 — raise the Stripe page and text or email it over."""
        invoice = send_for_payment(self.get_object(), staff=request.user)
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(request=RefundSerializer, responses={200: InvoiceSerializer})
    @action(detail=True, methods=["post"])
    def refund(self, request, pk=None):
        if not IsAdminStaff().has_permission(request, self):
            self.permission_denied(request, message=IsAdminStaff.message)

        from .stripe_gateway import StripeError, get_gateway

        invoice = self.get_object()
        serializer = RefundSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        try:
            refund_id = get_gateway().refund(invoice, serializer.validated_data.get("amount"))
        except StripeError as exc:
            raise ValidationError({"detail": [str(exc)]}) from exc

        invoice = record_refund(
            invoice, refund_id=refund_id, reason=serializer.validated_data.get("reason", "")
        )

        record(
            "stripe",
            f"Refund issued on {invoice.display_reference}",
            severity=AuditEvent.Severity.WARNING,
            actor=request.user.name or request.user.email,
            subject_type="invoice",
            subject_id=invoice.pk,
            refund_id=refund_id,
            amount=str(serializer.validated_data.get("amount") or invoice.total),
        )
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(request=PaymentSerializer, responses={200: InvoiceSerializer})
    @action(detail=True, methods=["post"], url_path="mark-paid")
    def mark_paid(self, request, pk=None):
        serializer = PaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invoice = mark_paid(
            self.get_object(),
            payment_method=serializer.validated_data.get("payment_method", ""),
            reference=serializer.validated_data.get("payment_reference", ""),
        )
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(request=None, responses={200: InvoiceSerializer})
    @action(detail=True, methods=["post"])
    def void(self, request, pk=None):
        if not IsOwner().has_permission(request, self):
            self.permission_denied(request, message=IsOwner.message)
        invoice = void_invoice(
            self.get_object(), staff=request.user, reason=request.data.get("reason", "")
        )
        return Response(InvoiceSerializer(invoice).data)
