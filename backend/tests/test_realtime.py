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
