from drf_spectacular.utils import extend_schema
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.generics import ListAPIView
from rest_framework.response import Response

from apps.accounts.permissions import IsApprovedDriver, IsOwner, IsStaff

from .models import Invoice, ServiceItem
from .serializers import InvoiceSerializer, PaymentSerializer, ServiceItemSerializer
from .services import mark_paid, void_invoice


@extend_schema(tags=["billing"])
class ServiceItemViewSet(viewsets.ModelViewSet):
    """The owner's price list. Drivers read it; only the owner sets the prices."""

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
class InvoiceViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Invoice.objects.select_related("job").prefetch_related("lines")
    serializer_class = InvoiceSerializer
    permission_classes = [IsStaff]
    filterset_fields = ["status", "payment_method"]
    search_fields = ["job__reference", "payment_reference"]
    ordering_fields = ["created_at", "total", "issued_at"]

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
