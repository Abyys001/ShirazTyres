"""
Stripe's callbacks.

Two rules govern everything here.

**Verify before trusting.** This endpoint is unauthenticated and public — it has
to be, Stripe has no session — so the signature is the only thing separating a
real payment notification from anybody who found the URL. Verification runs
against the *raw* request body: Stripe signs the exact bytes it sent, and DRF
re-serialising a parsed body changes them.

**Assume every event arrives more than once.** Stripe delivers at least once and
retries on any non-2xx, so the same `invoice.paid` will land again. Every handler
is idempotent, and a duplicate event id is acknowledged without being applied a
second time.
"""

import logging

from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.audit.models import AuditEvent
from apps.audit.services import record

from .models import Invoice
from .services import apply_stripe_payment
from .stripe_gateway import StripeError, get_gateway

logger = logging.getLogger(__name__)

#: Events we act on. Anything else is acknowledged and logged, never 400'd —
#: Stripe retries a rejected callback, and refusing events we simply do not care
#: about would have it retrying them forever.
HANDLED = {
    "invoice.paid",
    "invoice.payment_succeeded",
    "invoice.payment_failed",
    "invoice.voided",
    "invoice.marked_uncollectible",
    "charge.refunded",
}


@method_decorator(csrf_exempt, name="dispatch")
@extend_schema(tags=["billing"], request=None, responses={200: dict})
class StripeWebhookView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        signature = request.META.get("HTTP_STRIPE_SIGNATURE", "")

        try:
            gateway = get_gateway()
            event = gateway.construct_event(request.body, signature)
        except StripeError as exc:
            record(
                "stripe",
                "Rejected a webhook callback",
                severity=AuditEvent.Severity.WARNING,
                actor="stripe",
                reason=str(exc),
            )
            # 400 tells Stripe this was not us. It will retry, which is correct
            # if the secret was merely missing, and harmless if it was a forgery.
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        event_id = str(event.get("id", ""))
        event_type = str(event.get("type", ""))

        # Idempotency: the same event id is acknowledged, not re-applied.
        if event_id and AuditEvent.objects.filter(
            category="stripe", subject_type="stripe_event", subject_id=event_id
        ).exists():
            return Response({"detail": "Already handled.", "duplicate": True})

        obj = (event.get("data") or {}).get("object") or {}
        invoice = self._find_invoice(obj)

        record(
            "stripe",
            f"{event_type} received"
            + (f" for {invoice.display_reference}" if invoice else " (no matching invoice)"),
            severity=(
                AuditEvent.Severity.WARNING
                if event_type == "invoice.payment_failed" or invoice is None
                else AuditEvent.Severity.INFO
            ),
            actor="stripe",
            subject_type="stripe_event",
            subject_id=event_id,
            event_type=event_type,
            stripe_invoice_id=obj.get("id", ""),
            invoice_id=invoice.pk if invoice else None,
            mode=gateway.mode,
        )

        if event_type in HANDLED and invoice is not None:
            self._apply(event_type, event_id, invoice, obj)

        # Always 200 for anything correctly signed: Stripe retries non-2xx, and
        # an event we chose not to act on is handled, not failed.
        return Response({"detail": "ok", "handled": event_type in HANDLED})

    @staticmethod
    def _find_invoice(obj: dict) -> Invoice | None:
        stripe_id = obj.get("id") or ""
        if stripe_id:
            found = Invoice.objects.filter(stripe_invoice_id=stripe_id).first()
            if found:
                return found

        # A charge carries the payment intent rather than the invoice id.
        intent = obj.get("payment_intent") or ""
        if intent:
            return Invoice.objects.filter(stripe_payment_intent_id=intent).first()
        return None

    @staticmethod
    def _apply(event_type: str, event_id: str, invoice: Invoice, obj: dict) -> None:
        if event_type in {"invoice.paid", "invoice.payment_succeeded"}:
            apply_stripe_payment(
                invoice,
                event_id=event_id,
                payment_intent_id=str(obj.get("payment_intent") or ""),
            )
            return

        if event_type == "invoice.payment_failed":
            invoice.stripe_status = "payment_failed"
            invoice.save(update_fields=["stripe_status"])
            return

        if event_type in {"invoice.voided", "invoice.marked_uncollectible"}:
            # Stripe's copy is gone; ours stays issued so the debt is still on
            # the board. Voiding here is the office's call, not Stripe's.
            invoice.stripe_status = str(obj.get("status") or event_type)
            invoice.hosted_invoice_url = ""
            invoice.save(update_fields=["stripe_status", "hosted_invoice_url"])
            return

        if event_type == "charge.refunded":
            invoice.stripe_status = "refunded"
            invoice.save(update_fields=["stripe_status"])
