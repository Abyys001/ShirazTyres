"""Building and closing an invoice. Section 7.1, in order."""

import logging
from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.configuration.services import get_setting

from .models import Invoice, InvoiceLineItem, ServiceItem

logger = logging.getLogger(__name__)


def create_invoice_for_job(job) -> Invoice:
    """Step 1 and 2: the configured call-out fee becomes the invoice's first line."""
    invoice, created = Invoice.objects.get_or_create(
        job=job,
        defaults={
            "vat_rate": Decimal(str(get_setting("pricing.vat_rate"))),
            "currency": get_setting("pricing.currency"),
        },
    )
    if not created:
        return invoice

    if get_setting("pricing.callout_fee_enabled"):
        InvoiceLineItem.objects.create(
            invoice=invoice,
            kind=ServiceItem.Kind.CALLOUT,
            description="Emergency call-out",
            quantity=Decimal("1.00"),
            unit_price=Decimal(str(get_setting("pricing.callout_fee"))),
            is_system=True,
            sort_order=-100,
        )
    return invoice.recalculate()


def _guard_editable(invoice: Invoice) -> None:
    if not invoice.is_editable:
        raise ValidationError({"detail": ["This invoice has been issued and can no longer be changed."]})


def add_line(
    invoice: Invoice,
    *,
    description: str,
    unit_price,
    quantity=Decimal("1.00"),
    kind: str = ServiceItem.Kind.PART,
    service_item: ServiceItem | None = None,
) -> InvoiceLineItem:
    _guard_editable(invoice)
    line = InvoiceLineItem.objects.create(
        invoice=invoice,
        service_item=service_item,
        kind=service_item.kind if service_item else kind,
        description=description or (service_item.name if service_item else ""),
        quantity=Decimal(str(quantity)),
        unit_price=Decimal(str(unit_price if unit_price is not None else service_item.unit_price)),
    )
    invoice.recalculate()
    return line


def remove_line(line: InvoiceLineItem) -> Invoice:
    _guard_editable(line.invoice)
    if line.is_system:
        raise ValidationError({"detail": ["The call-out fee is set by the office, not on site."]})
    invoice = line.invoice
    line.delete()
    return invoice.recalculate()


def issue_invoice(invoice: Invoice, *, driver=None, payment_method: str = "", reference: str = "") -> Invoice:
    """Step 6: the driver marks the job complete and the invoice is recorded against it."""
    _guard_editable(invoice)
    invoice.recalculate(commit=False)
    invoice.status = Invoice.Status.ISSUED
    invoice.issued_at = timezone.now()
    invoice.issued_by_driver = driver
    if payment_method:
        invoice.payment_method = payment_method
    if reference:
        invoice.payment_reference = reference[:128]
    invoice.save()
    logger.info("invoice.issued job=%s total=%s", invoice.job.reference, invoice.total)
    return invoice


def mark_paid(invoice: Invoice, *, payment_method: str = "", reference: str = "") -> Invoice:
    if invoice.status == Invoice.Status.VOID:
        raise ValidationError({"detail": ["A void invoice cannot be marked paid."]})
    if invoice.status == Invoice.Status.DRAFT:
        issue_invoice(invoice, payment_method=payment_method, reference=reference)
    invoice.status = Invoice.Status.PAID
    invoice.paid_at = timezone.now()
    if payment_method:
        invoice.payment_method = payment_method
    if reference:
        invoice.payment_reference = reference[:128]
    invoice.save(update_fields=["status", "paid_at", "payment_method", "payment_reference"])
    logger.info("invoice.paid job=%s total=%s", invoice.job.reference, invoice.total)
    return invoice


def void_invoice(invoice: Invoice, *, staff=None, reason: str = "") -> Invoice:
    with transaction.atomic():
        invoice.status = Invoice.Status.VOID
        invoice.voided_by = staff
        invoice.notes = (invoice.notes + f"\nVoided: {reason}").strip()
        invoice.save(update_fields=["status", "voided_by", "notes"])
    logger.warning("invoice.voided job=%s reason=%s", invoice.job.reference, reason)
    return invoice
