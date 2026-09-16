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
    """
    Money owed, usually for a job.

    Every call-out still gets one at creation so the call-out fee is never
    forgotten (section 7.1 step 2) — that is what ``job`` being the common case
    means. But an invoice that *required* a job could not be raised for anything
    else: a fleet account settled monthly, a tyre sold over the counter, a
    re-issue after a dispute. ``job`` is optional and ``customer`` carries the
    "who owes this" that used to be reachable only through the job.

    Exactly one of the two is always set; ``clean`` enforces it, and so does the
    serializer, because a row with neither is money owed by nobody.
    """

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

    job = models.OneToOneField(
        Job, null=True, blank=True, on_delete=models.CASCADE, related_name="invoice"
    )
    customer = models.ForeignKey(
        "accounts.Customer", null=True, blank=True, on_delete=models.PROTECT, related_name="invoices"
    )
    #: Who to bill when there is no customer account — a company, a walk-in.
    bill_to_name = models.CharField(max_length=120, blank=True)
    bill_to_email = models.EmailField(blank=True)
    bill_to_phone = models.CharField(max_length=20, blank=True)
    reference = models.CharField(max_length=24, unique=True, blank=True)
    due_date = models.DateField(null=True, blank=True)
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
    # --- Stripe (section 7.2's open decision, now settled) ------------------
    #: Set once the invoice has been mirrored into Stripe. Its presence is what
    #: "this is collectable online" means; absence means cash or card reader.
    stripe_invoice_id = models.CharField(max_length=64, blank=True, db_index=True)
    stripe_payment_intent_id = models.CharField(max_length=64, blank=True)
    stripe_customer_id = models.CharField(max_length=64, blank=True)
    #: The page the customer actually pays on. Sent by SMS or email; never built
    #: by hand, because only Stripe can mint one.
    hosted_invoice_url = models.URLField(blank=True)
    stripe_status = models.CharField(max_length=32, blank=True)
    #: Which mode raised it, so a test-mode row can never be mistaken for money.
    stripe_mode = models.CharField(max_length=8, blank=True)

    issued_at = models.DateTimeField(null=True, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.display_reference} — {self.currency} {self.total}"

    def clean(self):
        from django.core.exceptions import ValidationError as DjangoValidationError

        if self.job_id is None and self.customer_id is None and not self.bill_to_name:
            raise DjangoValidationError(
                "An invoice needs a job, a customer, or a name to bill."
            )

    def save(self, *args, **kwargs):
        if not self.reference:
            self.reference = self._next_reference()
        super().save(*args, **kwargs)

    @staticmethod
    def _next_reference() -> str:
        """
        A human-quotable reference, unique without being guessable in sequence.

        Invoices get read out over the phone, so this follows the job's own
        shape rather than exposing a primary key — "INV-4" tells a caller how
        much business we did this month.
        """
        import secrets
        import string

        alphabet = string.ascii_uppercase + string.digits
        while True:
            candidate = "INV-" + "".join(secrets.choice(alphabet) for _ in range(6))
            if not Invoice.objects.filter(reference=candidate).exists():
                return candidate

    @property
    def display_reference(self) -> str:
        return self.reference or (self.job.reference if self.job_id else f"Invoice {self.pk}")

    @property
    def bill_to(self) -> str:
        """Who owes this, wherever the answer happens to live."""
        if self.bill_to_name:
            return self.bill_to_name
        if self.customer_id:
            return self.customer.display_name
        if self.job_id:
            return self.job.contact_name
        return ""

    @property
    def bill_to_contact(self) -> tuple[str, str]:
        """(email, phone) for sending a payment link."""
        email = self.bill_to_email or (
            self.customer.email if self.customer_id else ""
        ) or (self.job.contact_email if self.job_id else "")
        phone = self.bill_to_phone or (
            self.customer.phone if self.customer_id else ""
        ) or (self.job.contact_phone if self.job_id else "")
        return email, phone

    @property
    def is_payable_online(self) -> bool:
        return bool(self.hosted_invoice_url) and self.status != self.Status.PAID

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
