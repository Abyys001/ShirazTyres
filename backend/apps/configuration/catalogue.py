"""The owner-editable settings catalogue (specification section 12).

Every knob the owner may turn is declared here with its type and default. The
``Setting`` table only ever holds overrides, so adding a knob is a one-line change
here rather than a data migration.
"""

from dataclasses import dataclass
from decimal import Decimal
from typing import Any

TYPE_BOOL = "bool"
TYPE_INT = "int"
TYPE_DECIMAL = "decimal"
TYPE_STRING = "string"
TYPE_TEXT = "text"
TYPE_CHOICE = "choice"
TYPE_JSON = "json"

GROUP_DISPATCH = "dispatch"
GROUP_PRICING = "pricing"
GROUP_SERVICE_AREAS = "service_areas"
GROUP_DRIVERS = "drivers"
GROUP_NOTIFICATIONS = "notifications"
GROUP_OPERATIONAL = "operational"

DISPATCH_MODE_AUTOMATIC = "automatic"
DISPATCH_MODE_SELECTION = "selection"

FALLBACK_RETRY = "retry"
FALLBACK_SWITCH_MODE = "switch_mode"
FALLBACK_UNCLAIMED = "unclaimed"


@dataclass(frozen=True)
class SettingSpec:
    key: str
    group: str
    type: str
    default: Any
    label: str
    help_text: str = ""
    choices: tuple[tuple[str, str], ...] = ()


CATALOGUE: tuple[SettingSpec, ...] = (
    # --- Dispatch ----------------------------------------------------------
    SettingSpec(
        "dispatch.mode", GROUP_DISPATCH, TYPE_CHOICE, DISPATCH_MODE_AUTOMATIC,
        "Dispatch mode",
        "Automatic assignment picks the best-ranked driver. Driver selection offers the job to several at once.",
        ((DISPATCH_MODE_AUTOMATIC, "Automatic assignment"), (DISPATCH_MODE_SELECTION, "Driver selection")),
    ),
    SettingSpec("dispatch.offer_batch_size", GROUP_DISPATCH, TYPE_INT, 5,
                "Drivers per offer batch", "How many drivers a driver-selection round is offered to."),
    SettingSpec("dispatch.initial_radius_km", GROUP_DISPATCH, TYPE_DECIMAL, Decimal("5"),
                "Initial offer radius (km)"),
    SettingSpec("dispatch.radius_increment_km", GROUP_DISPATCH, TYPE_DECIMAL, Decimal("3"),
                "Radius increment per round (km)"),
    SettingSpec("dispatch.selection_timeout_seconds", GROUP_DISPATCH, TYPE_INT, 60,
                "Driver selection acceptance timeout (s)"),
    SettingSpec("dispatch.automatic_timeout_seconds", GROUP_DISPATCH, TYPE_INT, 90,
                "Automatic assignment response timeout (s)"),
    SettingSpec("dispatch.max_attempts", GROUP_DISPATCH, TYPE_INT, 3,
                "Maximum escalation attempts", "After this many rounds the job is marked unclaimed."),
    SettingSpec(
        "dispatch.escalation_fallback", GROUP_DISPATCH, TYPE_CHOICE, FALLBACK_UNCLAIMED,
        "Escalation fallback",
        "What happens once the attempts are exhausted.",
        ((FALLBACK_RETRY, "Retry the same mode"),
         (FALLBACK_SWITCH_MODE, "Switch to the other mode"),
         (FALLBACK_UNCLAIMED, "Mark the job unclaimed")),
    ),
    SettingSpec("dispatch.max_candidate_pool", GROUP_DISPATCH, TYPE_INT, 25,
                "Candidate pool cap", "Upper bound on drivers sent to the routing engine per round."),

    # --- Pricing -----------------------------------------------------------
    SettingSpec("pricing.callout_fee_enabled", GROUP_PRICING, TYPE_BOOL, True, "Call-out fee enabled"),
    SettingSpec("pricing.callout_fee", GROUP_PRICING, TYPE_DECIMAL, Decimal("60.00"),
                "Call-out fee (GBP, excluding VAT)"),
    SettingSpec("pricing.vat_rate", GROUP_PRICING, TYPE_DECIMAL, Decimal("20.00"),
                "VAT rate (%)", "Tyre services are standard-rated in the UK."),
    SettingSpec("pricing.currency", GROUP_PRICING, TYPE_STRING, "GBP", "Currency"),

    # --- Service areas -----------------------------------------------------
    SettingSpec("service_areas.enforce", GROUP_SERVICE_AREAS, TYPE_BOOL, True,
                "Refuse out-of-area requests"),
    SettingSpec("service_areas.out_of_area_message", GROUP_SERVICE_AREAS, TYPE_TEXT,
                "We're sorry — that location is outside the area we currently cover. "
                "Call us on 020 0000 0000 and we'll see what we can do.",
                "Out-of-area message"),

    # --- Drivers -----------------------------------------------------------
    SettingSpec("drivers.required_documents", GROUP_DRIVERS, TYPE_JSON,
                ["insurance", "licence", "mot"],
                "Document types required for approval"),
    SettingSpec("drivers.expiry_warning_days", GROUP_DRIVERS, TYPE_INT, 30,
                "Document expiry warning threshold (days)"),
    SettingSpec("drivers.suspend_on_expiry", GROUP_DRIVERS, TYPE_BOOL, True,
                "Automatically suspend a driver whose documents expire"),
    SettingSpec("drivers.max_concurrent_jobs", GROUP_DRIVERS, TYPE_INT, 1,
                "Maximum concurrent jobs per driver"),
    SettingSpec("drivers.location_retention_days", GROUP_DRIVERS, TYPE_INT, 90,
                "Driver location retention (days)", "UK GDPR: tracking data is purged after this period."),

    # --- Notifications -----------------------------------------------------
    SettingSpec("notifications.owner_events", GROUP_NOTIFICATIONS, TYPE_JSON,
                ["submitted", "unclaimed", "completed"],
                "Job events that notify the owner"),
    SettingSpec("notifications.owner_channels", GROUP_NOTIFICATIONS, TYPE_JSON,
                ["push", "sms", "email"], "Owner notification channels"),
    SettingSpec("notifications.customer_events", GROUP_NOTIFICATIONS, TYPE_JSON,
                ["accepted", "en_route", "arrived", "completed", "cancelled"],
                "Job events that notify the customer"),
    SettingSpec("notifications.customer_channels", GROUP_NOTIFICATIONS, TYPE_JSON,
                ["sms", "push"], "Customer notification channels"),
    SettingSpec("notifications.templates", GROUP_NOTIFICATIONS, TYPE_JSON,
                {
                    "accepted": "ShirazTyres {reference}: {driver_name} is assigned to you and will be with you in about {eta_minutes} minutes.",
                    "en_route": "ShirazTyres {reference}: {driver_name} is on the way in a {driver_vehicle} ({driver_plate}). ETA {eta_minutes} minutes.",
                    "arrived": "ShirazTyres {reference}: your technician has arrived.",
                    "completed": "ShirazTyres {reference}: the work is complete. Total {total}. Thank you.",
                    "cancelled": "ShirazTyres {reference}: your call-out has been cancelled. Call us if this is wrong.",
                    "unclaimed": "ShirazTyres {reference} could not be assigned automatically and needs attention.",
                },
                "Message templates", "Placeholders: {reference} {driver_name} {driver_vehicle} {driver_plate} {eta_minutes} {total}"),

    # --- Operational -------------------------------------------------------
    SettingSpec("operational.business_hours", GROUP_OPERATIONAL, TYPE_JSON,
                {
                    "mon": ["07:00", "22:00"], "tue": ["07:00", "22:00"], "wed": ["07:00", "22:00"],
                    "thu": ["07:00", "22:00"], "fri": ["07:00", "22:00"], "sat": ["08:00", "20:00"],
                    "sun": ["09:00", "18:00"],
                },
                "Business hours", "Empty list for a closed day."),
    SettingSpec("operational.out_of_hours_behaviour", GROUP_OPERATIONAL, TYPE_CHOICE, "accept",
                "Out-of-hours behaviour", "",
                (("accept", "Accept as normal"),
                 ("accept_with_notice", "Accept but warn the customer"),
                 ("refuse", "Refuse the request"))),
    SettingSpec("operational.out_of_hours_message", GROUP_OPERATIONAL, TYPE_TEXT,
                "We're outside our normal hours, so it may take us longer than usual to reach you.",
                "Out-of-hours message"),
    SettingSpec("operational.issue_types", GROUP_OPERATIONAL, TYPE_JSON,
                [
                    {"value": "puncture", "label": "Puncture"},
                    {"value": "blowout", "label": "Blowout"},
                    {"value": "tyre_damage", "label": "Tyre damage"},
                    {"value": "wheel_change", "label": "Wheel change"},
                    {"value": "locking_nut", "label": "Locking wheel nut"},
                    {"value": "other", "label": "Something else"},
                ],
                "Issue types offered on the request form"),
    SettingSpec("operational.customer_cancel_until", GROUP_OPERATIONAL, TYPE_CHOICE, "en_route",
                "Customers may cancel until", "",
                (("accepted", "A driver accepts"),
                 ("en_route", "The driver is en route"),
                 ("arrived", "The driver arrives"),
                 ("never", "Never — staff only"))),
)

BY_KEY: dict[str, SettingSpec] = {spec.key: spec for spec in CATALOGUE}
