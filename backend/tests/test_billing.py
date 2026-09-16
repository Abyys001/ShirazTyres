"""Specification section 7: the call-out fee, on-site items, VAT, and one payment."""

from decimal import Decimal

import pytest

from apps.billing.models import Invoice, ServiceItem

pytestmark = pytest.mark.django_db


def _set(key, value):
    from apps.configuration.services import set_setting

    set_setting(key, value)


@pytest.fixture
def price_list(db):
    return ServiceItem.objects.create(
        code="TYRE-205-55-16", name="205/55R16 tyre", kind=ServiceItem.Kind.PART,
        unit_price=Decimal("85.00"), unit="each",
    )


# ------------------------------------------------------ the call-out fee ----


def test_the_callout_fee_is_attached_when_the_job_is_created(make_job):
    """Section 7.1 step 2 — automatically, as the first line, without anyone asking."""
    _set("pricing.callout_fee", "60.00")
    job = make_job()

    line = job.invoice.lines.get()
    assert line.is_system
    assert line.kind == ServiceItem.Kind.CALLOUT
    assert line.unit_price == Decimal("60.00")
    assert job.invoice.subtotal == Decimal("60.00")
    assert job.invoice.vat_amount == Decimal("12.00")
    assert job.invoice.total == Decimal("72.00")


def test_the_callout_fee_can_be_switched_off(make_job):
    _set("pricing.callout_fee_enabled", False)
    job = make_job()

    assert job.invoice.lines.count() == 0
    assert job.invoice.total == Decimal("0.00")


def test_the_vat_rate_is_snapshotted_on_the_invoice(make_job):
    """Section 7.2 — a rate change must not silently rewrite yesterday's invoices."""
    _set("pricing.vat_rate", "20.00")
    job = make_job()

    _set("pricing.vat_rate", "5.00")
    job.invoice.refresh_from_db()
    job.invoice.recalculate()

    assert job.invoice.vat_rate == Decimal("20.00")
    assert job.invoice.vat_amount == Decimal("12.00")


# ------------------------------------------------------ the driver on site ----


def test_driver_adds_a_price_list_item_and_the_totals_follow(
    in_progress_job, driver_client, price_list
):
    response = driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines",
        {"service_item_id": price_list.pk, "quantity": "2"},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["subtotal"] == "230.00"  # 60 call-out + 2 × 85
    assert response.data["vat_amount"] == "46.00"
    assert response.data["total"] == "276.00"


def test_driver_adds_a_free_text_line(in_progress_job, driver_client):
    response = driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines",
        {"description": "Valve replacement", "unit_price": "4.50", "kind": "part"},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["subtotal"] == "64.50"


def test_a_line_needs_either_a_price_list_item_or_a_price(in_progress_job, driver_client):
    response = driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines",
        {"description": "Something"}, format="json",
    )
    assert response.status_code == 400
    assert "unit_price" in response.data["errors"]


def test_driver_cannot_remove_the_callout_fee(in_progress_job, driver_client):
    """The fee is the office's decision, not the technician's."""
    system_line = in_progress_job.invoice.lines.get(is_system=True)
    response = driver_client.delete(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines/{system_line.pk}"
    )
    assert response.status_code == 400
    assert in_progress_job.invoice.lines.filter(pk=system_line.pk).exists()


def test_driver_can_remove_a_line_they_added(in_progress_job, driver_client, price_list):
    added = driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines",
        {"service_item_id": price_list.pk}, format="json",
    ).data["lines"][-1]

    response = driver_client.delete(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines/{added['id']}"
    )
    assert response.status_code == 200, response.data
    assert response.data["total"] == "72.00"


def test_driver_only_sees_active_price_list_items(driver_client, price_list):
    ServiceItem.objects.create(
        code="OLD", name="Discontinued", unit_price=Decimal("10.00"), is_active=False
    )
    response = driver_client.get("/api/v1/driver/service-items")
    assert response.status_code == 200
    assert [item["code"] for item in response.data] == ["TYRE-205-55-16"]


# ------------------------------------------------------------ completion ----


def test_completing_the_job_issues_the_invoice_and_records_how_it_was_paid(
    in_progress_job, driver_client, price_list
):
    """Section 7.1 steps 5 and 6 — one payment, after the work."""
    driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines",
        {"service_item_id": price_list.pk}, format="json",
    )
    response = driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/complete",
        {"payment_method": "card_reader", "payment_reference": "TRX-9911"},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["status"] == "completed"

    invoice = Invoice.objects.get(job=in_progress_job)
    assert invoice.status == Invoice.Status.PAID
    assert invoice.payment_method == Invoice.PaymentMethod.CARD_READER
    assert invoice.payment_reference == "TRX-9911"
    assert invoice.total == Decimal("174.00")
    assert invoice.issued_at is not None


def test_completing_without_a_payment_method_still_issues_the_invoice(
    in_progress_job, driver_client
):
    """Section 16 item 2 is open — an unrecorded capture method must not block the job."""
    response = driver_client.post(f"/api/v1/driver/jobs/{in_progress_job.pk}/complete", {}, format="json")
    assert response.status_code == 200, response.data

    invoice = Invoice.objects.get(job=in_progress_job)
    assert invoice.status == Invoice.Status.ISSUED
    assert invoice.payment_method == Invoice.PaymentMethod.UNSPECIFIED


def test_a_job_cannot_be_completed_before_the_work_starts(make_job, driver, driver_client):
    from apps.dispatch.engine import dispatch_job

    job = make_job()
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")

    response = driver_client.post(f"/api/v1/driver/jobs/{job.pk}/complete", {}, format="json")
    assert response.status_code == 400
    assert "status" in response.data["errors"]


def test_an_issued_invoice_is_closed_to_edits(in_progress_job, driver_client, price_list):
    driver_client.post(f"/api/v1/driver/jobs/{in_progress_job.pk}/complete", {}, format="json")

    response = driver_client.post(
        f"/api/v1/driver/jobs/{in_progress_job.pk}/invoice/lines",
        {"service_item_id": price_list.pk}, format="json",
    )
    assert response.status_code == 400


# ---------------------------------------------------------------- office ----


def test_only_the_owner_sets_the_price_list(staff_client, api, office_staff):
    payload = {"code": "LAB-1", "name": "Labour", "kind": "labour", "unit_price": "30.00"}
    assert staff_client.post("/api/v1/service-items", payload, format="json").status_code == 201

    login = api.post(
        "/api/v1/auth/staff/login",
        {"email": office_staff.email, "password": "pw-test-1234"},
        format="json",
    )
    api.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    assert api.get("/api/v1/service-items").status_code == 200
    payload["code"] = "LAB-2"
    assert api.post("/api/v1/service-items", payload, format="json").status_code == 403


def test_staff_can_add_a_line_the_driver_could_not(staff_client, make_job):
    job = make_job()
    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/invoice",
        {"description": "Roadside disposal", "unit_price": "5.00", "kind": "other"},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["subtotal"] == "65.00"


def test_staff_can_mark_an_invoice_paid(staff_client, in_progress_job, driver_client):
    driver_client.post(f"/api/v1/driver/jobs/{in_progress_job.pk}/complete", {}, format="json")
    invoice = Invoice.objects.get(job=in_progress_job)

    response = staff_client.post(
        f"/api/v1/invoices/{invoice.pk}/mark-paid",
        {"payment_method": "payment_link", "payment_reference": "pl_1"},
        format="json",
    )
    assert response.status_code == 200, response.data
    assert response.data["status"] == "paid"


def test_a_void_invoice_cannot_be_marked_paid(staff_client, make_job):
    job = make_job()
    response = staff_client.post(f"/api/v1/invoices/{job.invoice.pk}/void",
                                 {"reason": "Duplicate job"}, format="json")
    assert response.status_code == 200, response.data

    response = staff_client.post(f"/api/v1/invoices/{job.invoice.pk}/mark-paid", {}, format="json")
    assert response.status_code == 400


# ---------------------------------------------------------- Stripe / payment --


def _invoice_for(staff_client, make_job):
    from apps.billing.models import Invoice

    job = make_job()
    invoice = Invoice.objects.get(job=job)
    staff_client.post(
        f"/api/v1/invoices/{invoice.pk}/lines",
        {"description": "Tyre", "unit_price": "90.00", "quantity": 1},
        format="json",
    )
    invoice.refresh_from_db()
    return invoice


def test_every_invoice_gets_a_quotable_reference(staff_client, make_job):
    invoice = _invoice_for(staff_client, make_job)
    assert invoice.reference.startswith("INV-")
    assert len(invoice.reference) == 10


def test_an_invoice_can_be_raised_without_a_job(staff_client):
    """A fleet account or a counter sale is not a call-out."""
    response = staff_client.post(
        "/api/v1/invoices",
        {"bill_to_name": "Acme Haulage", "bill_to_email": "accounts@acme.test"},
        format="json",
    )
    assert response.status_code == 201, response.data
    assert response.data["job"] is None
    assert response.data["bill_to"] == "Acme Haulage"


def test_an_invoice_for_nobody_is_refused(staff_client):
    response = staff_client.post("/api/v1/invoices", {}, format="json")
    assert response.status_code == 400


def test_sending_for_payment_raises_a_stripe_page(staff_client, make_job, settings):
    settings.STRIPE_MODE = "mock"
    invoice = _invoice_for(staff_client, make_job)

    response = staff_client.post(f"/api/v1/invoices/{invoice.pk}/send-payment-link")

    assert response.status_code == 200, response.data
    assert response.data["hosted_invoice_url"]
    assert response.data["stripe_mode"] == "mock"
    assert response.data["status"] == "issued"
    # Section 7.2's open decision, recorded: this one went out as a link.
    assert response.data["payment_method"] == "payment_link"


def test_a_payment_link_is_not_raised_twice(staff_client, make_job, settings):
    """Two working payment pages for one debt is worse than an error."""
    settings.STRIPE_MODE = "mock"
    invoice = _invoice_for(staff_client, make_job)

    first = staff_client.post(f"/api/v1/invoices/{invoice.pk}/send-payment-link")
    second = staff_client.post(f"/api/v1/invoices/{invoice.pk}/send-payment-link")

    assert first.data["hosted_invoice_url"] == second.data["hosted_invoice_url"]


def test_stripe_webhook_marks_the_invoice_paid(api, staff_client, make_job, settings):
    settings.STRIPE_MODE = "mock"
    invoice = _invoice_for(staff_client, make_job)
    staff_client.post(f"/api/v1/invoices/{invoice.pk}/send-payment-link")
    invoice.refresh_from_db()

    response = api.post(
        "/api/v1/billing/stripe/webhook",
        {
            "id": "evt_test_1",
            "type": "invoice.paid",
            "data": {"object": {"id": invoice.stripe_invoice_id, "payment_intent": "pi_test_1"}},
        },
        format="json",
    )

    assert response.status_code == 200, response.data
    invoice.refresh_from_db()
    assert invoice.status == "paid"
    assert invoice.payment_reference == "pi_test_1"


def test_the_same_webhook_twice_is_applied_once(api, staff_client, make_job, settings):
    """Stripe delivers at least once and retries — every handler must be idempotent."""
    settings.STRIPE_MODE = "mock"
    invoice = _invoice_for(staff_client, make_job)
    staff_client.post(f"/api/v1/invoices/{invoice.pk}/send-payment-link")
    invoice.refresh_from_db()

    payload = {
        "id": "evt_test_2",
        "type": "invoice.paid",
        "data": {"object": {"id": invoice.stripe_invoice_id, "payment_intent": "pi_test_2"}},
    }
    api.post("/api/v1/billing/stripe/webhook", payload, format="json")
    invoice.refresh_from_db()
    first_paid_at = invoice.paid_at

    second = api.post("/api/v1/billing/stripe/webhook", payload, format="json")

    assert second.data["duplicate"] is True
    invoice.refresh_from_db()
    assert invoice.paid_at == first_paid_at


def test_an_unknown_event_is_acknowledged_not_rejected(api, settings):
    """A non-2xx makes Stripe retry forever something we never wanted."""
    settings.STRIPE_MODE = "mock"
    response = api.post(
        "/api/v1/billing/stripe/webhook",
        {"id": "evt_test_3", "type": "customer.created", "data": {"object": {}}},
        format="json",
    )
    assert response.status_code == 200
    assert response.data["handled"] is False


def test_live_mode_refuses_a_test_key(settings):
    """A test key in live mode means nothing would ever actually be collected."""
    from apps.billing.stripe_gateway import StripeError, get_gateway

    settings.STRIPE_MODE = "live"
    settings.STRIPE_SECRET_KEY = "sk_test_pretend"
    with pytest.raises(StripeError, match="live but the key is a test key"):
        get_gateway()


def test_an_issued_invoice_cannot_be_deleted(staff_client, make_job, settings):
    settings.STRIPE_MODE = "mock"
    invoice = _invoice_for(staff_client, make_job)
    staff_client.post(f"/api/v1/invoices/{invoice.pk}/send-payment-link")

    assert staff_client.delete(f"/api/v1/invoices/{invoice.pk}").status_code == 400
