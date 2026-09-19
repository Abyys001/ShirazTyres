"""Specification sections 4.6, 4.7 and 11.1: who is allowed to receive what, live.

The audience boundary is enforced in ``apps.realtime.publish``, so that is what is
tested here rather than the socket handshake.
"""

import asyncio

import pytest
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from apps.realtime import groups

pytestmark = pytest.mark.django_db


@pytest.fixture
def listen():
    """Subscribes a throwaway channel to groups and returns everything they receive."""
    layer = get_channel_layer()
    channels: dict[str, str] = {}

    def _subscribe(*group_names):
        for index, group in enumerate(group_names):
            channel = f"test-{index}-{group}"
            channels[group] = channel
            async_to_sync(layer.group_add)(group, channel)
        return _drain

    def _drain(group):
        async def _pull():
            received = []
            while True:
                try:
                    message = await asyncio.wait_for(layer.receive(channels[group]), timeout=0.05)
                except (asyncio.TimeoutError, TimeoutError):
                    return received
                received.append(message["payload"])

        return async_to_sync(_pull)()

    return _subscribe


def test_a_driver_position_reaches_the_panel_and_nobody_else(listen, driver, customer):
    """Section 4.6 — the customer never sees where the technician is."""
    from apps.realtime.publish import publish_driver_location

    drain = listen(groups.PANEL, groups.customer_group(customer.pk), groups.driver_group(driver.pk))
    publish_driver_location(driver)

    panel = drain(groups.PANEL)
    assert [message["event"] for message in panel] == ["driver.location"]
    assert panel[0]["latitude"] == str(driver.latitude)

    assert drain(groups.customer_group(customer.pk)) == []
    assert drain(groups.driver_group(driver.pk)) == []


def test_the_customer_feed_carries_the_eta_figure_but_no_coordinates(
    listen, make_job, customer, driver, driver_client
):
    """Section 4.6 — the ETA is recalculated on the backend and only the figure is sent."""
    from apps.dispatch.engine import dispatch_job

    drain = listen(groups.customer_group(customer.pk))
    job = make_job(customer=customer)
    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")

    messages = drain(groups.customer_group(customer.pk))
    assert messages, "the customer should have been told a technician is on the way"

    payload = messages[-1]["job"]
    assert payload["eta_minutes"] is not None
    assert set(payload["driver"]) == {
        "first_name", "photo", "vehicle_make", "vehicle_model", "vehicle_colour", "vehicle_plate"
    }
    assert "latitude" not in str(payload["driver"])


def test_the_panel_feed_carries_the_full_job(listen, make_job, driver):
    from apps.dispatch.engine import dispatch_job

    drain = listen(groups.PANEL)
    job = make_job()
    dispatch_job(job)

    events = [message["event"] for message in drain(groups.PANEL)]
    assert "job.created" in events
    assert "job.status" in events


def test_an_offer_reaches_only_the_driver_it_was_made_to(listen, make_job, driver, second_driver):
    from apps.dispatch.engine import dispatch_job

    drain = listen(groups.driver_group(driver.pk), groups.driver_group(second_driver.pk))
    dispatch_job(make_job())

    mine = [message["event"] for message in drain(groups.driver_group(driver.pk))]
    assert "offer.new" in mine
    assert drain(groups.driver_group(second_driver.pk)) == []


def test_the_losing_drivers_are_told_the_job_is_gone(
    listen, make_job, driver, second_driver, driver_client
):
    """Selection mode offers to several; only one can have it."""
    from apps.configuration.services import set_setting
    from apps.dispatch.engine import dispatch_job

    set_setting("dispatch.mode", "selection")
    job = make_job()
    dispatch_job(job)

    drain = listen(groups.driver_group(second_driver.pk))
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")

    events = [message["event"] for message in drain(groups.driver_group(second_driver.pk))]
    assert "offer.withdrawn" in events


def test_a_token_for_the_wrong_audience_is_refused_at_the_socket(customer, driver):
    """The socket takes the same scoped token as the REST API and checks it the same way."""
    from apps.accounts.tokens import (
        SCOPE_CUSTOMER,
        SCOPE_DRIVER,
        SCOPE_STAFF,
        issue_pair,
        read_scoped_token,
    )
    from apps.realtime.consumers import TOKEN_ERRORS

    token = issue_pair(SCOPE_CUSTOMER, customer.pk)["access"]
    assert read_scoped_token(token, SCOPE_CUSTOMER) == customer.pk

    for wrong_scope in (SCOPE_STAFF, SCOPE_DRIVER):
        # The consumer must recognise this as a refusal and close the socket, not blow up.
        with pytest.raises(TOKEN_ERRORS):
            read_scoped_token(token, wrong_scope)

    with pytest.raises(TOKEN_ERRORS):
        read_scoped_token("not-a-token", SCOPE_CUSTOMER)


def test_a_rejection_reaches_the_panel_even_when_it_does_not_escalate(
    listen, make_job, driver, second_driver, driver_client
):
    """Section 6.3. In selection mode with offers still open a rejection changes
    nothing else the office can see, so without its own event the dispatch card
    goes on showing a name that has already said no."""
    from apps.configuration.services import set_setting
    from apps.dispatch.engine import dispatch_job

    set_setting("dispatch.mode", "selection")
    job = make_job()
    dispatch_job(job)

    drain = listen(groups.PANEL)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/reject", {"reason": "Too far."}, format="json")

    events = [message["event"] for message in drain(groups.PANEL)]
    assert "dispatch.rejected" in events


def test_assigning_by_hand_withdraws_the_offer_on_every_other_phone(
    listen, make_job, driver, second_driver, staff_client
):
    """The office taking a job off the board has to reach the drivers who were
    still holding an offer for it, or one of them taps accept on a job that is gone."""
    from apps.configuration.services import set_setting
    from apps.dispatch.engine import dispatch_job

    set_setting("dispatch.mode", "selection")
    job = make_job()
    dispatch_job(job)

    drain = listen(groups.driver_group(second_driver.pk))
    response = staff_client.post(
        f"/api/v1/jobs/{job.pk}/assign", {"driver_id": driver.pk}, format="json"
    )
    assert response.status_code == 200, response.data

    withdrawals = [
        message for message in drain(groups.driver_group(second_driver.pk))
        if message["event"] == "offer.withdrawn"
    ]
    assert withdrawals, "the losing driver was never told"
    assert "office" in withdrawals[0]["reason"].lower()


def test_a_refund_moves_the_panel_without_a_reload(listen, in_progress_job, driver_client, staff_client):
    """Every other invoice mutation announces itself; a refund used to be written
    straight onto the row in the view and nobody was told."""
    driver_client.post(f"/api/v1/driver/jobs/{in_progress_job.pk}/complete", {}, format="json")
    in_progress_job.refresh_from_db()
    invoice_id = in_progress_job.invoice.pk

    drain = listen(groups.PANEL)
    response = staff_client.post(
        f"/api/v1/invoices/{invoice_id}/refund", {"reason": "Wrong tyre fitted."}, format="json"
    )
    assert response.status_code == 200, response.data

    events = [message["event"] for message in drain(groups.PANEL)]
    assert "invoice.refunded" in events


def test_changing_a_setting_tells_every_other_panel(listen, staff_client):
    """Two people on the settings screen used to overwrite each other in silence."""
    drain = listen(groups.PANEL)
    response = staff_client.patch(
        "/api/v1/settings", {"values": {"dispatch.mode": "selection"}}, format="json"
    )
    assert response.status_code == 200, response.data

    events = [message["event"] for message in drain(groups.PANEL)]
    assert "config.settings" in events


def test_editing_the_price_list_tells_every_other_panel(listen, staff_client):
    drain = listen(groups.PANEL)
    response = staff_client.post(
        "/api/v1/service-items",
        {"code": "TYRE-205", "name": "205/55R16 fitted", "kind": "part", "unit_price": "95.00"},
        format="json",
    )
    assert response.status_code == 201, response.data

    events = [message["event"] for message in drain(groups.PANEL)]
    assert "config.service-items" in events


def test_the_open_board_is_announced_to_every_technician(listen, make_job, driver, second_driver,
                                                         driver_client):
    """The board is shared, so it moves on every phone at once rather than on a poll."""
    from apps.dispatch.engine import dispatch_job

    drain = listen(groups.DRIVERS)
    job = make_job()
    assert [message["event"] for message in drain(groups.DRIVERS)] == ["board.open"]

    dispatch_job(job)
    driver_client.post(f"/api/v1/driver/jobs/{job.pk}/accept")
    assert "board.taken" in [message["event"] for message in drain(groups.DRIVERS)]
