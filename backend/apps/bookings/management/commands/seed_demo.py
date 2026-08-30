"""Demo data: one owner, one office user, a London service area, four approved drivers,
three customers and a spread of jobs across the status machine.

Idempotent — running it twice does not duplicate anything.
"""

from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import Customer, StaffUser
from apps.billing.models import ServiceItem
from apps.bookings.models import Job
from apps.bookings.services import create_job
from apps.drivers.models import Driver, DriverDocument, DriverVehicle
from apps.geo.models import ServiceArea
from apps.geo.services import invalidate_cache as invalidate_geo_cache
from apps.vehicles.models import ConfirmationPath, CustomerVehicle
from apps.vehicles.services import lookup_plate

OWNER_EMAIL = "owner@shiraztyres.co.uk"
OWNER_PASSWORD = "shiraz1234"

# A deliberately coarse Greater London ring. Section 16 item 4 leaves the precise
# polygon open; this is enough to exercise in-area and out-of-area behaviour.
LONDON_BOUNDARY = {
    "type": "Polygon",
    "coordinates": [[
        [-0.5103, 51.4200], [-0.3300, 51.3300], [-0.0700, 51.2900], [0.1800, 51.3300],
        [0.3340, 51.4200], [0.3340, 51.5600], [0.2000, 51.6800], [-0.0500, 51.7100],
        [-0.3000, 51.6800], [-0.5103, 51.5600], [-0.5103, 51.4200],
    ]],
}

DRIVERS = [
    ("+447700900301", "Amir Hosseini", "AB12CDE", 51.5074, -0.1278),
    ("+447700900302", "Grace Okafor", "BD64FGH", 51.4820, -0.0100),
    ("+447700900303", "Tomasz Nowak", "CE18JKL", 51.5390, -0.1430),
    ("+447700900304", "Priya Raman", "DF20MNO", 51.4600, -0.1700),
]

CUSTOMERS = [
    ("+447700900101", "Sara Ahmadi", "sara@example.com", "AA19AAA"),
    ("+447700900102", "James Whitfield", "james@example.com", "BB20BBB"),
    ("+447700900103", "Nadia Rahimi", "nadia@example.com", "CC21CCC"),
]

SERVICE_ITEMS = [
    ("TYRE-16", "Tyre fitted — 16 inch", ServiceItem.Kind.PART, Decimal("89.00"), "each", 10),
    ("TYRE-17", "Tyre fitted — 17 inch", ServiceItem.Kind.PART, Decimal("104.00"), "each", 20),
    ("TYRE-18", "Tyre fitted — 18 inch", ServiceItem.Kind.PART, Decimal("128.00"), "each", 30),
    ("REPAIR", "Puncture repair", ServiceItem.Kind.LABOUR, Decimal("35.00"), "each", 40),
    ("SPARE", "Fit customer's spare", ServiceItem.Kind.LABOUR, Decimal("28.00"), "each", 50),
    ("LOCKNUT", "Locking wheel nut removal", ServiceItem.Kind.LABOUR, Decimal("45.00"), "each", 60),
    ("VALVE", "Valve replacement", ServiceItem.Kind.PART, Decimal("8.00"), "each", 70),
    ("DISPOSAL", "Old tyre disposal", ServiceItem.Kind.OTHER, Decimal("4.00"), "each", 80),
]


class Command(BaseCommand):
    help = "Populate the database with a coherent demo dataset."

    @transaction.atomic
    def handle(self, *args, **options):
        owner = self._staff()
        area = self._service_area()
        self._service_items()
        drivers = self._drivers(area)
        customers = self._customers()
        self._jobs(customers, drivers, owner)

        invalidate_geo_cache()
        self.stdout.write(self.style.SUCCESS(
            f"Seeded. Owner: {OWNER_EMAIL} / {OWNER_PASSWORD}\n"
            f"Drivers sign in with phone + OTP; mock SMS returns the code as debug_code."
        ))

    def _staff(self) -> StaffUser:
        owner = StaffUser.objects.filter(email=OWNER_EMAIL).first()
        if owner is None:
            owner = StaffUser.objects.create_user(
                email=OWNER_EMAIL, password=OWNER_PASSWORD, name="Shiraz Owner",
                role=StaffUser.Role.OWNER, is_superuser=True, is_staff=True,
            )
        StaffUser.objects.get_or_create(
            email="office@shiraztyres.co.uk",
            defaults={"name": "Office Desk", "role": StaffUser.Role.STAFF},
        )
        return owner

    def _service_area(self) -> ServiceArea:
        area, _ = ServiceArea.objects.update_or_create(
            name="Greater London",
            defaults={"boundary": LONDON_BOUNDARY, "is_active": True, "priority": 10},
        )
        return area

    def _service_items(self) -> None:
        for code, name, kind, price, unit, order in SERVICE_ITEMS:
            ServiceItem.objects.update_or_create(
                code=code,
                defaults={"name": name, "kind": kind, "unit_price": price,
                          "unit": unit, "sort_order": order, "is_active": True},
            )

    def _drivers(self, area: ServiceArea) -> list[Driver]:
        today = timezone.localdate()
        drivers = []
        for index, (phone, name, plate, latitude, longitude) in enumerate(DRIVERS):
            driver, _ = Driver.objects.update_or_create(
                phone=phone,
                defaults={
                    "name": name,
                    "employment_reference": f"ST-EMP-{index + 1:03d}",
                    "verification_status": Driver.Verification.APPROVED,
                    "approved_at": timezone.now(),
                    "is_active": True,
                    "is_online": True,
                    "went_online_at": timezone.now(),
                    "latitude": Decimal(str(latitude)),
                    "longitude": Decimal(str(longitude)),
                    "location_accuracy_m": 12,
                    "location_updated_at": timezone.now(),
                },
            )
            driver.service_areas.set([area])
            DriverVehicle.objects.update_or_create(
                driver=driver, plate=plate,
                defaults={"make": "FORD", "model": "TRANSIT CUSTOM", "colour": "White",
                          "year_of_manufacture": 2021, "is_primary": True},
            )
            for document_type in (DriverDocument.DocumentType.INSURANCE,
                                  DriverDocument.DocumentType.LICENCE,
                                  DriverDocument.DocumentType.MOT):
                DriverDocument.objects.update_or_create(
                    driver=driver, document_type=document_type,
                    defaults={
                        "file": f"drivers/demo/{document_type}.pdf",
                        "expiry_date": today + timedelta(days=180 + index * 10),
                        "status": DriverDocument.Status.APPROVED,
                        "reviewed_at": timezone.now(),
                    },
                )
            drivers.append(driver)

        # One driver waiting in the onboarding queue, so the panel has something to review.
        pending, _ = Driver.objects.update_or_create(
            phone="+447700900305",
            defaults={"name": "Daniel Cole", "verification_status": Driver.Verification.PENDING},
        )
        DriverDocument.objects.update_or_create(
            driver=pending, document_type=DriverDocument.DocumentType.INSURANCE,
            defaults={"file": "drivers/demo/insurance.pdf",
                      "expiry_date": today + timedelta(days=20),
                      "status": DriverDocument.Status.PENDING},
        )
        return drivers

    def _customers(self) -> list[Customer]:
        customers = []
        for phone, name, email, plate in CUSTOMERS:
            customer, _ = Customer.objects.update_or_create(
                phone=phone,
                defaults={"name": name, "email": email, "is_phone_verified": True},
            )
            vehicle = lookup_plate(plate)
            CustomerVehicle.objects.update_or_create(
                customer=customer, vehicle=vehicle,
                defaults={"is_primary": True, "confirmation_path": ConfirmationPath.CONFIRMED,
                          "looked_up_tyre_size": vehicle.tyre_size_front,
                          "confirmed_at": timezone.now()},
            )
            customers.append(customer)
        return customers

    def _jobs(self, customers: list[Customer], drivers: list[Driver], owner: StaffUser) -> None:
        if Job.objects.exists():
            self.stdout.write("Jobs already present — leaving them alone.")
            return

        specs = [
            (customers[0], "puncture", "Nearside front, slow deflation.", 51.5155, -0.1420, Job.Source.WEBSITE),
            (customers[1], "blowout", "Offside rear blew on the A40.", 51.5200, -0.2100, Job.Source.APP),
            (customers[2], "wheel_change", "Spare in the boot, no jack.", 51.4700, -0.0900, Job.Source.PHONE),
        ]

        for customer, issue, description, latitude, longitude, source in specs:
            link = customer.vehicle_links.first()
            create_job(
                customer=customer,
                vehicle=link.vehicle if link else None,
                customer_vehicle=link,
                contact_name=customer.name,
                contact_phone=customer.phone,
                contact_email=customer.email,
                issue_type=issue,
                description=description,
                latitude=Decimal(str(latitude)),
                longitude=Decimal(str(longitude)),
                location_text="Roadside, central London",
                location_source=Job.LocationSource.BROWSER,
                looked_up_tyre_size=link.vehicle.tyre_size_front if link else "",
                tyre_size=link.vehicle.tyre_size_front if link else "",
                tyre_confirmation_path=ConfirmationPath.CONFIRMED,
                source=source,
                created_by_staff=owner if source == Job.Source.PHONE else None,
                auto_dispatch=False,
            )
        self.stdout.write(f"Created {Job.objects.count()} demo jobs (dispatch not run).")
