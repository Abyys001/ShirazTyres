"""The subset of configuration the customer website and app may read anonymously."""

from decimal import Decimal

from apps.geo.services import service_area_summary

from .hours import business_hours_status
from .services import get_setting


def public_configuration() -> dict:
    hours = business_hours_status()
    callout_enabled = get_setting("pricing.callout_fee_enabled")
    vat_rate: Decimal = get_setting("pricing.vat_rate")

    return {
        "issue_types": get_setting("operational.issue_types"),
        "callout_fee": str(get_setting("pricing.callout_fee")) if callout_enabled else None,
        "callout_fee_enabled": callout_enabled,
        "vat_rate": str(vat_rate),
        "currency": get_setting("pricing.currency"),
        "business_hours": get_setting("operational.business_hours"),
        "is_open": hours.is_open,
        "out_of_hours_behaviour": hours.behaviour,
        "out_of_hours_message": hours.message,
        "out_of_area_message": get_setting("service_areas.out_of_area_message"),
        "customer_cancel_until": get_setting("operational.customer_cancel_until"),
        "service_areas": service_area_summary(),
    }
