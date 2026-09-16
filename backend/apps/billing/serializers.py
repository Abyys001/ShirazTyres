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
    job_reference = serializers.CharField(source="job.reference", read_only=True, default="")
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    is_editable = serializers.BooleanField(read_only=True)
    display_reference = serializers.CharField(read_only=True)
    bill_to = serializers.CharField(read_only=True)
    is_payable_online = serializers.BooleanField(read_only=True)

    class Meta:
        model = Invoice
        fields = (
            "id", "reference", "display_reference", "job", "job_reference",
            "customer", "bill_to", "bill_to_name", "bill_to_email", "bill_to_phone",
            "status", "status_display", "currency", "vat_rate", "due_date",
            "subtotal", "vat_amount", "total", "payment_method", "payment_reference",
            "notes", "is_editable", "lines",
            "stripe_invoice_id", "hosted_invoice_url", "stripe_status", "stripe_mode",
            "is_payable_online",
            "issued_at", "paid_at", "created_at", "updated_at",
        )
        read_only_fields = (
            "id", "reference", "display_reference", "job", "job_reference", "bill_to",
            "status", "status_display", "currency", "vat_rate",
            "subtotal", "vat_amount", "total", "is_editable", "lines",
            "stripe_invoice_id", "hosted_invoice_url", "stripe_status", "stripe_mode",
            "is_payable_online", "issued_at", "paid_at", "created_at", "updated_at",
        )


class InvoiceCreateSerializer(serializers.ModelSerializer):
    """
    Raise an invoice by hand, with or without a job behind it.

    The office needs this for the things that are not call-outs — a fleet account
    settled monthly, a counter sale, a re-issue after a dispute — which an
    invoice welded to a job could not express.
    """

    class Meta:
        model = Invoice
        fields = (
            "job", "customer", "bill_to_name", "bill_to_email", "bill_to_phone",
            "due_date", "notes",
        )

    def validate_job(self, value):
        if value is not None and Invoice.objects.filter(job=value).exists():
            raise serializers.ValidationError("That job already has an invoice.")
        return value

    def validate(self, attrs):
        if not any(
            (attrs.get("job"), attrs.get("customer"), (attrs.get("bill_to_name") or "").strip())
        ):
            raise serializers.ValidationError(
                {"bill_to_name": ["Say who this is for — a job, a customer, or a name."]}
            )
        return attrs

    def create(self, validated_data):
        from decimal import Decimal

        from apps.configuration.services import get_setting

        # VAT is snapshotted at creation, as it is for a job's own invoice: the
        # rate on the day the work happened is the rate that must stay on it.
        return Invoice.objects.create(
            vat_rate=Decimal(str(get_setting("pricing.vat_rate"))),
            currency=get_setting("pricing.currency"),
            **validated_data,
        )


class RefundSerializer(serializers.Serializer):
    amount = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True,
        help_text="Leave empty to refund the whole invoice.",
    )
    reason = serializers.CharField(max_length=255, required=False, allow_blank=True)


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
