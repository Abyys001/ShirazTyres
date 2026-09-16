"""Building and closing an invoice. Section 7.1, in order."""

import logging
from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.configuration.services import get_setting

from .models import Invoice, InvoiceLineItem, ServiceItem

logger = logging.getLogger(__name__)


def _announce(invoice: Invoice, kind: str) -> Invoice:
    """The panel's invoice list and the job it hangs off both move on their own."""
    from apps.realtime.publish import publish_invoice_event, publish_job_event

    transaction.on_commit(lambda: publish_invoice_event(invoice, kind))
    # A standalone invoice has no job board row to refresh.
    if invoice.job_id:
        transaction.on_commit(lambda: publish_job_event(invoice.job, "invoice"))
    return invoice


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
    _announce(invoice, "line_added")
    return line


def remove_line(line: InvoiceLineItem) -> Invoice:
    _guard_editable(line.invoice)
    if line.is_system:
        raise ValidationError({"detail": ["The call-out fee is set by the office, not on site."]})
    invoice = line.invoice
    line.delete()
    return _announce(invoice.recalculate(), "line_removed")


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
    logger.info("invoice.issued ref=%s total=%s", invoice.display_reference, invoice.total)
    return _announce(invoice, "issued")


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
    logger.info("invoice.paid ref=%s total=%s", invoice.display_reference, invoice.total)
    return _announce(invoice, "paid")


def void_invoice(invoice: Invoice, *, staff=None, reason: str = "") -> Invoice:
    with transaction.atomic():
        invoice.status = Invoice.Status.VOID
        invoice.voided_by = staff
        invoice.notes = (invoice.notes + f"\nVoided: {reason}").strip()
        invoice.save(update_fields=["status", "voided_by", "notes"])
    logger.warning("invoice.voided ref=%s reason=%s", invoice.display_reference, reason)
    return _announce(invoice, "voided")


def record_refund(invoice: Invoice, *, refund_id: str, reason: str = "") -> Invoice:
    """Write a completed refund onto the invoice.

    The gateway call belongs to the view — it can fail, and a failed refund must
    not touch the record. What happened afterwards belongs here, with every other
    invoice mutation, so the panel's list and the job it hangs off are told the
    same way they are told about a void or a payment.
    """
    with transaction.atomic():
        invoice.stripe_status = "refunded"
        invoice.notes = (invoice.notes + f"\nRefunded ({refund_id}): {reason}").strip()
        invoice.save(update_fields=["stripe_status", "notes"])
    logger.warning("invoice.refunded ref=%s refund=%s", invoice.display_reference, refund_id)
    return _announce(invoice, "refunded")


# ------------------------------------------------------------------ Stripe ----


def send_for_payment(invoice: Invoice, *, staff=None, notify: bool = True) -> Invoice:
    """
    Mirror an invoice into Stripe and hand the customer a way to pay it.

    Section 7.1 step 5: the customer pays once the work is finished, so this is
    called after the invoice is issued rather than at booking. A draft is issued
    first — Stripe finalizes what it is given, and sending a payment link for
    figures that can still change is how a customer ends up paying the wrong
    total.

    Idempotent: an invoice already carrying a ``hosted_invoice_url`` is returned
    as-is rather than raising a second one. A duplicate payment page is worse
    than an error, because both of them work.
    """
    from apps.audit.models import AuditEvent
    from apps.audit.services import record

    from .stripe_gateway import StripeError, get_gateway

    if invoice.status == Invoice.Status.VOID:
        raise ValidationError({"detail": ["A void invoice cannot be sent for payment."]})
    if invoice.status == Invoice.Status.PAID:
        raise ValidationError({"detail": ["This invoice is already paid."]})
    if invoice.hosted_invoice_url:
        return invoice
    if invoice.total <= 0:
        raise ValidationError({"detail": ["There is nothing to charge for on this invoice."]})

    if invoice.status == Invoice.Status.DRAFT:
        issue_invoice(invoice, payment_method=Invoice.PaymentMethod.PAYMENT_LINK)

    gateway = get_gateway()
    try:
        remote = gateway.create_invoice(invoice)
    except StripeError as exc:
        record(
            "stripe",
            f"Could not raise a payment page for {invoice.display_reference}",
            severity=AuditEvent.Severity.ERROR,
            actor=getattr(staff, "name", "") or "system",
            subject_type="invoice",
            subject_id=invoice.pk,
            error=str(exc),
            mode=gateway.mode,
        )
        raise ValidationError({"detail": [f"Stripe refused this: {exc}"]}) from exc

    invoice.stripe_invoice_id = remote.invoice_id
    invoice.stripe_payment_intent_id = remote.payment_intent_id
    invoice.stripe_customer_id = remote.customer_id
    invoice.hosted_invoice_url = remote.hosted_url
    invoice.stripe_status = remote.status
    invoice.stripe_mode = gateway.mode
    invoice.payment_method = Invoice.PaymentMethod.PAYMENT_LINK
    invoice.save(
        update_fields=[
            "stripe_invoice_id", "stripe_payment_intent_id", "stripe_customer_id",
            "hosted_invoice_url", "stripe_status", "stripe_mode", "payment_method",
        ]
    )

    record(
        "stripe",
        f"Payment page raised for {invoice.display_reference} ({invoice.currency} {invoice.total})",
        actor=getattr(staff, "name", "") or "system",
        subject_type="invoice",
        subject_id=invoice.pk,
        mode=gateway.mode,
        stripe_invoice_id=remote.invoice_id,
        total=str(invoice.total),
    )

    if notify:
        _send_payment_link(invoice)
    return _announce(invoice, "payment_link")


def _send_payment_link(invoice: Invoice) -> None:
    """
    Text or email the link, whichever we have. Never both — one bill, one nudge.

    A failure here is logged, not raised: the page exists and the office can read
    the link out over the phone, so a bounced email must not undo the invoice.
    """
    from apps.notifications.services import send_email, send_sms

    email, phone = invoice.bill_to_contact
    body = (
        f"ShirazTyres invoice {invoice.display_reference} — "
        f"{invoice.currency} {invoice.total}. Pay here: {invoice.hosted_invoice_url}"
    )
    try:
        if phone:
            send_sms(phone, body, job=invoice.job, event="invoice.payment_link")
        elif email:
            send_email(
                email,
                f"Your ShirazTyres invoice {invoice.display_reference}",
                body,
                job=invoice.job,
                event="invoice.payment_link",
            )
    except Exception as exc:  # noqa: BLE001 — the invoice stands either way.
        logger.warning("invoice.link_not_sent ref=%s error=%s", invoice.display_reference, exc)


def apply_stripe_payment(invoice: Invoice, *, event_id: str, payment_intent_id: str = "") -> Invoice:
    """
    Stripe says this invoice is paid. Believe it once.

    Webhooks are delivered at least once and often more, so this returns early
    on an invoice that is already paid rather than moving ``paid_at`` every time
    the same event arrives.
    """
    if invoice.status == Invoice.Status.PAID:
        return invoice
    if payment_intent_id:
        invoice.stripe_payment_intent_id = payment_intent_id
    invoice.stripe_status = "paid"
    invoice.save(update_fields=["stripe_payment_intent_id", "stripe_status"])
    return mark_paid(
        invoice,
        payment_method=Invoice.PaymentMethod.PAYMENT_LINK,
        reference=payment_intent_id or event_id,
    )
