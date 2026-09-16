"""
Stripe, behind a seam — section 7.2's open decision, settled.

Three modes, chosen by ``STRIPE_MODE``, following the same factory shape the SMS
and push providers already use (``notifications.providers``):

``mock``  no network at all. Mints plausible-looking identifiers and a local
          hosted-page URL. This is the default, so the repository still runs with
          zero keys and zero spend, and the whole invoice flow is exercisable in
          a test.
``test``  real Stripe, test keys, the sandbox. Cards that never move money.
``live``  real money.

Mode is recorded on every invoice it touches (``Invoice.stripe_mode``), because
the one failure that actually costs something is a test-mode row being read as
income.

The flow is section 7.1 exactly: build the invoice locally with VAT, mirror it
into Stripe, finalize, and hand the customer ``hosted_invoice_url``. Stripe is
told the totals we calculated — VAT is ours (`pricing.vat_rate`), not Stripe Tax,
so the figure on the invoice the customer receives is the figure the panel shows.
"""

import logging
from dataclasses import dataclass
from decimal import Decimal

from django.conf import settings

logger = logging.getLogger(__name__)


class StripeError(Exception):
    """Anything the gateway could not do. Never leaks a key into its message."""


@dataclass(frozen=True)
class RemoteInvoice:
    invoice_id: str
    hosted_url: str
    status: str
    payment_intent_id: str = ""
    customer_id: str = ""


def _minor_units(amount: Decimal) -> int:
    """Stripe counts in pence. Rounding here, once, keeps it off every call site."""
    return int((Decimal(str(amount)) * 100).quantize(Decimal("1")))


class BaseStripeGateway:
    mode = "mock"

    def create_invoice(self, invoice) -> RemoteInvoice:
        raise NotImplementedError

    def void_invoice(self, invoice) -> None:
        raise NotImplementedError

    def refund(self, invoice, amount: Decimal | None = None) -> str:
        raise NotImplementedError

    def construct_event(self, payload: bytes, signature: str) -> dict:
        raise NotImplementedError


class MockStripeGateway(BaseStripeGateway):
    """
    Everything the real one does, minus the network.

    Deliberately not a no-op: it returns a distinct id and a working-looking URL
    so the panel, the SMS body and the webhook handler all get exercised. The
    identifiers carry a ``mock_`` prefix so nothing in the database can later be
    mistaken for a real Stripe object.
    """

    mode = "mock"

    def create_invoice(self, invoice) -> RemoteInvoice:
        import secrets

        token = secrets.token_hex(8)
        base = (settings.PANEL_BASE_URL or "http://localhost:3000").rstrip("/")
        logger.info(
            "stripe.mock.invoice_created ref=%s total=%s", invoice.display_reference, invoice.total
        )
        return RemoteInvoice(
            invoice_id=f"mock_in_{token}",
            hosted_url=f"{base}/pay/mock/{token}",
            status="open",
            payment_intent_id=f"mock_pi_{token}",
            customer_id=f"mock_cus_{token}",
        )

    def void_invoice(self, invoice) -> None:
        logger.info("stripe.mock.invoice_voided ref=%s", invoice.display_reference)

    def refund(self, invoice, amount: Decimal | None = None) -> str:
        import secrets

        return f"mock_re_{secrets.token_hex(8)}"

    def construct_event(self, payload: bytes, signature: str) -> dict:
        """
        No signature to verify without a secret, so the mock accepts plain JSON.

        This is only ever reachable when ``STRIPE_MODE=mock``, which a production
        deployment must not be in — ``/health`` reports the mode for exactly that
        reason.
        """
        import json

        return json.loads(payload.decode("utf-8"))


class LiveStripeGateway(BaseStripeGateway):
    """Real Stripe. ``test`` and ``live`` differ only in which key is configured."""

    def __init__(self, mode: str):
        self.mode = mode
        secret = settings.STRIPE_SECRET_KEY
        if not secret:
            raise StripeError("STRIPE_SECRET_KEY is not set — cannot reach Stripe.")
        if mode == "live" and secret.startswith("sk_test_"):
            raise StripeError("STRIPE_MODE is live but the key is a test key.")
        if mode == "test" and secret.startswith("sk_live_"):
            raise StripeError("STRIPE_MODE is test but the key is a live key.")

        try:
            import stripe
        except ImportError as exc:  # pragma: no cover - dependency is declared
            raise StripeError("The stripe package is not installed.") from exc

        self._stripe = stripe
        self._client = stripe.StripeClient(secret)

    def _customer_id(self, invoice) -> str:
        """Find or make the Stripe customer this invoice is billed to."""
        if invoice.stripe_customer_id:
            return invoice.stripe_customer_id

        email, phone = invoice.bill_to_contact
        created = self._client.v1.customers.create(
            params={
                "name": invoice.bill_to or "ShirazTyres customer",
                **({"email": email} if email else {}),
                **({"phone": phone} if phone else {}),
                "metadata": {"shiraztyres_invoice": invoice.display_reference},
            }
        )
        return created.id

    def create_invoice(self, invoice) -> RemoteInvoice:
        try:
            customer_id = self._customer_id(invoice)

            remote = self._client.v1.invoices.create(
                params={
                    "customer": customer_id,
                    "collection_method": "send_invoice",
                    "days_until_due": 7,
                    # We finalize explicitly, so the totals are never sent to the
                    # customer before every line has been attached.
                    "auto_advance": False,
                    "currency": invoice.currency.lower(),
                    "metadata": {
                        "shiraztyres_invoice": invoice.display_reference,
                        "shiraztyres_job": invoice.job.reference if invoice.job_id else "",
                    },
                }
            )

            for line in invoice.lines.all():
                self._client.v1.invoice_items.create(
                    params={
                        "customer": customer_id,
                        "invoice": remote.id,
                        "currency": invoice.currency.lower(),
                        "amount": _minor_units(line.line_total),
                        "description": f"{line.description} × {line.quantity}",
                    }
                )

            # VAT is ours, not Stripe Tax: the panel already applied
            # `pricing.vat_rate` and the customer must see the same figure.
            if invoice.vat_amount and invoice.vat_amount > 0:
                self._client.v1.invoice_items.create(
                    params={
                        "customer": customer_id,
                        "invoice": remote.id,
                        "currency": invoice.currency.lower(),
                        "amount": _minor_units(invoice.vat_amount),
                        "description": f"VAT at {invoice.vat_rate}%",
                    }
                )

            finalized = self._client.v1.invoices.finalize_invoice(remote.id)
            return RemoteInvoice(
                invoice_id=finalized.id,
                hosted_url=finalized.hosted_invoice_url or "",
                status=finalized.status or "open",
                payment_intent_id=getattr(finalized, "payment_intent", "") or "",
                customer_id=customer_id,
            )
        except self._stripe.StripeError as exc:
            raise StripeError(str(getattr(exc, "user_message", None) or exc)) from exc

    def void_invoice(self, invoice) -> None:
        if not invoice.stripe_invoice_id:
            return
        try:
            self._client.v1.invoices.void_invoice(invoice.stripe_invoice_id)
        except self._stripe.StripeError as exc:
            raise StripeError(str(getattr(exc, "user_message", None) or exc)) from exc

    def refund(self, invoice, amount: Decimal | None = None) -> str:
        if not invoice.stripe_payment_intent_id:
            raise StripeError("This invoice was not paid through Stripe.")
        try:
            refund = self._client.v1.refunds.create(
                params={
                    "payment_intent": invoice.stripe_payment_intent_id,
                    **({"amount": _minor_units(amount)} if amount is not None else {}),
                }
            )
            return refund.id
        except self._stripe.StripeError as exc:
            raise StripeError(str(getattr(exc, "user_message", None) or exc)) from exc

    def construct_event(self, payload: bytes, signature: str) -> dict:
        """
        Verify the signature against the **raw** body.

        Stripe signs the exact bytes it sent; re-serialising a parsed body
        changes them and verification fails. The view reads `request.body` and
        passes it straight through for that reason.
        """
        secret = settings.STRIPE_WEBHOOK_SECRET
        if not secret:
            raise StripeError("STRIPE_WEBHOOK_SECRET is not set — refusing to trust a callback.")
        try:
            event = self._stripe.Webhook.construct_event(payload, signature, secret)
            return dict(event)
        except Exception as exc:  # noqa: BLE001 — a bad signature must read as one error.
            raise StripeError(f"Signature verification failed: {exc}") from exc


def get_gateway() -> BaseStripeGateway:
    mode = getattr(settings, "STRIPE_MODE", "mock")
    if mode == "mock":
        return MockStripeGateway()
    if mode in {"test", "live"}:
        return LiveStripeGateway(mode)
    raise StripeError(f"Unknown STRIPE_MODE {mode!r} — expected mock, test or live.")
