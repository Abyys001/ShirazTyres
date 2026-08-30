from decimal import Decimal

from rest_framework import serializers

from .models import Invoice, InvoiceLineItem, ServiceItem


class ServiceItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = ServiceItem
        fields = ("id", "code", "name", "kind", "unit_price", "unit", "is_active", "sort_order")
        read_only_fields = ("id",)


class InvoiceLineItemSerializer(serializers.ModelSerializer):
    line_total = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)

    class Meta:
        model = InvoiceLineItem
        fields = (
            "id", "service_item", "kind", "description", "quantity",
            "unit_price", "line_total", "is_system", "sort_order",
        )
        read_only_fields = ("id", "line_total", "is_system")


class InvoiceSerializer(serializers.ModelSerializer):
    lines = InvoiceLineItemSerializer(many=True, read_only=True)
    job_reference = serializers.CharField(source="job.reference", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    is_editable = serializers.BooleanField(read_only=True)

    class Meta:
        model = Invoice
        fields = (
            "id", "job", "job_reference", "status", "status_display", "currency", "vat_rate",
            "subtotal", "vat_amount", "total", "payment_method", "payment_reference",
            "notes", "is_editable", "lines", "issued_at", "paid_at", "created_at", "updated_at",
        )
        read_only_fields = (
            "id", "job", "job_reference", "status", "status_display", "currency", "vat_rate",
            "subtotal", "vat_amount", "total", "is_editable", "lines",
            "issued_at", "paid_at", "created_at", "updated_at",
        )


class AddLineSerializer(serializers.Serializer):
    service_item_id = serializers.IntegerField(required=False, allow_null=True)
    description = serializers.CharField(max_length=200, required=False, allow_blank=True)
    quantity = serializers.DecimalField(max_digits=8, decimal_places=2, default=1)
    unit_price = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0")
    )
    kind = serializers.ChoiceField(choices=ServiceItem.Kind.choices, default=ServiceItem.Kind.PART)

    def validate(self, attrs):
        if not attrs.get("service_item_id") and attrs.get("unit_price") is None:
            raise serializers.ValidationError(
                {"unit_price": ["Give a price, or choose an item from the price list."]}
            )
        if not attrs.get("service_item_id") and not attrs.get("description"):
            raise serializers.ValidationError({"description": ["Describe what is being charged for."]})
        return attrs


class PaymentSerializer(serializers.Serializer):
    payment_method = serializers.ChoiceField(
        choices=Invoice.PaymentMethod.choices, required=False, allow_blank=True
    )
    payment_reference = serializers.CharField(max_length=128, required=False, allow_blank=True)
