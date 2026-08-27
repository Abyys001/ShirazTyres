"""External vehicle data. Two sources, because DVLA does not return tyre sizes.

* DVLA Vehicle Enquiry Service — make/model/colour/fuel/tax/MOT. One key per company.
* A commercial tyre-fitment API (UK Vehicle Data or equivalent) — manufacturer tyre sizes.

Both sit behind a common shape so ``VEHICLE_LOOKUP_MOCK`` can serve dev and CI for free.
"""

import logging
from dataclasses import dataclass, field
from datetime import date, datetime

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class VehicleLookupError(Exception):
    """Raised when an upstream provider fails in a way the caller should surface."""

    def __init__(self, message: str, *, not_found: bool = False, upstream: str = ""):
        super().__init__(message)
        self.not_found = not_found
        self.upstream = upstream


@dataclass
class DvlaResult:
    make: str = ""
    model: str = ""
    colour: str = ""
    fuel_type: str = ""
    engine_capacity: int | None = None
    year_of_manufacture: int | None = None
    co2_emissions: int | None = None
    tax_status: str = ""
    tax_due_date: date | None = None
    mot_status: str = ""
    mot_expiry_date: date | None = None
    raw: dict = field(default_factory=dict)


@dataclass
class TyreResult:
    size_front: str = ""
    size_rear: str = ""
    load_index: str = ""
    speed_rating: str = ""
    pressure_front_psi: int | None = None
    pressure_rear_psi: int | None = None
    options: list[str] = field(default_factory=list)
    raw: dict = field(default_factory=dict)


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y-%m"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    return None


def _to_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


class DvlaVesProvider:
    """https://developer-portal.driver-vehicle-licensing.api.gov.uk — VES v1."""

    def fetch(self, plate: str) -> DvlaResult:
        if not settings.DVLA_API_KEY:
            raise VehicleLookupError("DVLA API key is not configured.", upstream="dvla")

        try:
            response = requests.post(
                settings.DVLA_VES_URL,
                json={"registrationNumber": plate},
                headers={"x-api-key": settings.DVLA_API_KEY, "Content-Type": "application/json"},
                timeout=settings.EXTERNAL_HTTP_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise VehicleLookupError("Could not reach the DVLA service.", upstream="dvla") from exc

        if response.status_code == 404:
            raise VehicleLookupError("No DVLA record for that registration.", not_found=True, upstream="dvla")
        if response.status_code == 429:
            raise VehicleLookupError("DVLA rate limit reached. Try again shortly.", upstream="dvla")
        if response.status_code >= 400:
            logger.warning("dvla.error status=%s body=%s", response.status_code, response.text[:400])
            raise VehicleLookupError("DVLA lookup failed.", upstream="dvla")

        data = response.json()
        return DvlaResult(
            make=data.get("make", "") or "",
            model=data.get("model", "") or "",
            colour=data.get("colour", "") or "",
            fuel_type=data.get("fuelType", "") or "",
            engine_capacity=_to_int(data.get("engineCapacity")),
            year_of_manufacture=_to_int(data.get("yearOfManufacture")),
            co2_emissions=_to_int(data.get("co2Emissions")),
            tax_status=data.get("taxStatus", "") or "",
            tax_due_date=_parse_date(data.get("taxDueDate")),
            mot_status=data.get("motStatus", "") or "",
            mot_expiry_date=_parse_date(data.get("motExpiryDate")),
            raw=data,
        )


class UkVehicleDataTyreProvider:
    """Commercial tyre-fitment lookup. Response shape is provider-specific — isolated here."""

    def fetch(self, plate: str) -> TyreResult:
        if not settings.TYRE_API_KEY:
            raise VehicleLookupError("Tyre data API key is not configured.", upstream="tyre")

        try:
            response = requests.get(
                settings.TYRE_API_URL,
                params={"v": 2, "api_nullitems": 1, "auth_apikey": settings.TYRE_API_KEY, "key_VRM": plate},
                timeout=settings.EXTERNAL_HTTP_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise VehicleLookupError("Could not reach the tyre data service.", upstream="tyre") from exc

        if response.status_code >= 400:
            logger.warning("tyre.error status=%s body=%s", response.status_code, response.text[:400])
            raise VehicleLookupError("Tyre lookup failed.", upstream="tyre")

        payload = response.json()
        status = (payload.get("Response") or {}).get("StatusCode")
        if status and status != "Success":
            raise VehicleLookupError("No tyre data for that registration.", not_found=True, upstream="tyre")

        results = ((payload.get("Response") or {}).get("DataItems") or {}).get("TyreDetails") or {}
        records = results.get("RecordList") or []
        if not records:
            raise VehicleLookupError("No tyre data for that registration.", not_found=True, upstream="tyre")

        primary = records[0]
        options = sorted({rec.get("Front", {}).get("Tyre", "") for rec in records if rec.get("Front", {}).get("Tyre")})
        front = primary.get("Front", {})
        rear = primary.get("Rear", {}) or front

        return TyreResult(
            size_front=front.get("Tyre", "") or "",
            size_rear=rear.get("Tyre", "") or "",
            load_index=str(front.get("LoadIndex", "") or ""),
            speed_rating=str(front.get("SpeedRating", "") or ""),
            pressure_front_psi=_to_int(front.get("PressurePsi")),
            pressure_rear_psi=_to_int(rear.get("PressurePsi")),
            options=options,
            raw=payload,
        )


class MockDvlaProvider:
    def fetch(self, plate: str) -> DvlaResult:
        if plate.startswith("XX"):
            raise VehicleLookupError("No DVLA record for that registration.", not_found=True, upstream="dvla")
        return DvlaResult(
            make="FORD",
            model="FOCUS",
            colour="Blue",
            fuel_type="PETROL",
            engine_capacity=1499,
            year_of_manufacture=2018,
            co2_emissions=124,
            tax_status="Taxed",
            tax_due_date=date(2026, 11, 1),
            mot_status="Valid",
            mot_expiry_date=date(2026, 6, 14),
            raw={"mock": True, "registrationNumber": plate},
        )


class MockTyreProvider:
    def fetch(self, plate: str) -> TyreResult:
        if plate.startswith("YY"):
            raise VehicleLookupError("No tyre data for that registration.", not_found=True, upstream="tyre")
        return TyreResult(
            size_front="205/55R16",
            size_rear="205/55R16",
            load_index="91",
            speed_rating="V",
            pressure_front_psi=33,
            pressure_rear_psi=32,
            options=["205/55R16", "215/50R17"],
            raw={"mock": True, "vrm": plate},
        )


def get_dvla_provider():
    return MockDvlaProvider() if settings.VEHICLE_LOOKUP_MOCK else DvlaVesProvider()


def get_tyre_provider():
    return MockTyreProvider() if settings.VEHICLE_LOOKUP_MOCK else UkVehicleDataTyreProvider()
