"""Business hours, evaluated against the configured week."""

from dataclasses import dataclass
from datetime import datetime, time

from django.utils import timezone

from .services import get_setting

_DAY_KEYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


@dataclass(frozen=True)
class HoursStatus:
    is_open: bool
    behaviour: str
    message: str


def _parse(value: str) -> time | None:
    try:
        hour, minute = value.split(":")
        return time(int(hour), int(minute))
    except (AttributeError, ValueError):
        return None


def is_open_at(moment: datetime | None = None) -> bool:
    moment = timezone.localtime(moment or timezone.now())
    window = (get_setting("operational.business_hours") or {}).get(_DAY_KEYS[moment.weekday()]) or []
    if len(window) != 2:
        return False
    opens, closes = _parse(window[0]), _parse(window[1])
    if opens is None or closes is None:
        return False
    now = moment.time()
    if closes <= opens:  # A window that runs past midnight.
        return now >= opens or now < closes
    return opens <= now < closes


def business_hours_status(moment: datetime | None = None) -> HoursStatus:
    open_now = is_open_at(moment)
    behaviour = get_setting("operational.out_of_hours_behaviour")
    return HoursStatus(
        is_open=open_now,
        behaviour=behaviour,
        message="" if open_now else get_setting("operational.out_of_hours_message"),
    )
