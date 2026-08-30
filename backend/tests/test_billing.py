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
