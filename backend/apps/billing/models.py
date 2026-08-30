"""Invoicing. VAT is present from the first line of the first invoice — section 7.2 is
explicit that retrofitting it later is painful and error-prone.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.db import models

from apps.accounts.models import StaffUser
from apps.bookings.models import Job
from apps.drivers.models import Driver

TWO_PLACES = Decimal("0.01")


def money(value) -> Decimal:
    return Decimal(value or 0).quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


class ServiceItem(models.Model):
    """The owner's price list — section 12. What a driver picks from on site."""

    class Kind(models.TextChoices):
        CALLOUT = "callout", "Call-out fee"
        PART = "part", "Part"
        LABOUR = "labour", "Labour"
        OTHER = "other", "Other"

    code = models.CharField(max_length=32, unique=True)
    name = models.CharField(max_length=120)
    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.PART)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=24, blank=True, help_text="each, hour, litre…")
    is_active = models.BooleanField(default=True)
    sort_order = models.SmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("sort_order", "name")

    def __str__(self):
        return f"{self.name} (£{self.unit_price})"


class Invoice(models.Model):
    """One per job, created with the job so the call-out fee is never forgotten."""

    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        ISSUED = "issued", "Issued"
        PAID = "paid", "Paid"
        VOID = "void", "Void"

    class PaymentMethod(models.TextChoices):
        # Section 16 item 2: the capture method is an open decision. Recording which one
        # was actually used costs nothing now and answers the question with real data.
        UNSPECIFIED = "unspecified", "Not recorded"
        CARD_READER = "card_reader", "Card reader in the van"
        PAYMENT_LINK = "payment_link", "Payment link by SMS"
        CASH = "cash", "Cash"
        OTHER = "other", "Other"

    job = models.OneToOneField(Job, on_delete=models.CASCADE, related_name="invoice")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.DRAFT, db_index=True)
    currency = models.CharField(max_length=8, default="GBP")
    vat_rate = models.DecimalField(
        max_digits=5, decimal_places=2, help_text="Percentage, snapshotted when the job was created."
    )
    subtotal = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    vat_amount = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    total = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))

    payment_method = models.CharField(
        max_length=16, choices=PaymentMethod.choices, default=PaymentMethod.UNSPECIFIED
    )
    payment_reference = models.CharField(max_length=128, blank=True)
    notes = models.TextField(blank=True)

    issued_by_driver = models.ForeignKey(
        Driver, null=True, blank=True, on_delete=models.SET_NULL, related_name="invoices"
    )
    voided_by = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="voided_invoices"
    )
    issued_at = models.DateTimeField(null=True, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return f"Invoice for {self.job.reference} — {self.currency} {self.total}"

    @property
    def is_editable(self) -> bool:
        return self.status == self.Status.DRAFT

    def recalculate(self, *, commit: bool = True) -> "Invoice":
        # Read the lines back from the database rather than through ``self.lines``: the
        # view that just added or deleted a line usually holds a prefetch cache from
        # before the change, and totalling that would persist a wrong figure.
        lines = InvoiceLineItem.objects.filter(invoice_id=self.pk)
        subtotal = sum((line.line_total for line in lines), Decimal("0.00"))
        self.subtotal = money(subtotal)
        self.vat_amount = money(self.subtotal * self.vat_rate / Decimal("100"))
        self.total = money(self.subtotal + self.vat_amount)
        if commit:
            self.save(update_fields=["subtotal", "vat_amount", "total"])
        return self


class InvoiceLineItem(models.Model):
    invoice = models.ForeignKey(Invoice, on_delete=models.CASCADE, related_name="lines")
    service_item = models.ForeignKey(
        ServiceItem, null=True, blank=True, on_delete=models.SET_NULL, related_name="line_items"
    )
    kind = models.CharField(max_length=16, choices=ServiceItem.Kind.choices, default=ServiceItem.Kind.PART)
    description = models.CharField(max_length=200)
    quantity = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal("1.00"))
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    is_system = models.BooleanField(
        default=False, help_text="Added by the system — the call-out fee. Not driver-editable."
    )
    sort_order = models.SmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("sort_order", "created_at")

    def __str__(self):
        return f"{self.description} × {self.quantity}"

    @property
    def line_total(self) -> Decimal:
        return money(self.quantity * self.unit_price)
