"""Populate a usable demo: an owner login, a couple of drivers, vehicles and live call-outs."""

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.accounts.models import Driver, StaffUser
from apps.bookings.models import Booking
from apps.bookings.services import create_booking, transition_booking
from apps.vehicles.models import DriverVehicle
from apps.vehicles.services import lookup_plate

DEMO_PASSWORD = "shiraz1234"


class Command(BaseCommand):
    help = "Create demo staff, drivers, vehicles and bookings for local development."

    def add_arguments(self, parser):
        parser.add_argument("--email", default="owner@shiraztyres.co.uk")
        parser.add_argument("--password", default=DEMO_PASSWORD)

    @transaction.atomic
    def handle(self, *args, **options):
        owner, created = StaffUser.objects.get_or_create(
            email=options["email"],
            defaults={"name": "Shop Owner", "role": StaffUser.Role.OWNER, "is_superuser": True, "is_staff": True},
        )
        if created:
            owner.set_password(options["password"])
            owner.save(update_fields=["password"])
            self.stdout.write(self.style.SUCCESS(f"Owner: {owner.email} / {options['password']}"))

        fitter, _ = StaffUser.objects.get_or_create(
            email="fitter@shiraztyres.co.uk", defaults={"name": "Sam Fitter", "role": StaffUser.Role.STAFF}
        )
        fitter.set_password(options["password"])
        fitter.save(update_fields=["password"])

        specs = [
            ("+447700900001", "Alex Driver", "AB12CDE", Booking.Issue.PUNCTURE, "M1 Junction 12, southbound"),
            ("+447700900002", "Sam Courier", "LT68 ABC", Booking.Issue.BLOWOUT, "A34 near Winchester services"),
            ("+447700900003", "Jo Fleet", "WR19XYZ", Booking.Issue.TYRE_DAMAGE, "Unit 4, Shirley Industrial Estate"),
        ]

        for phone, name, plate, issue, location in specs:
            driver, _ = Driver.objects.get_or_create(
                phone=phone, defaults={"name": name, "is_phone_verified": True}
            )
            vehicle = lookup_plate(plate.replace(" ", ""))
            DriverVehicle.objects.get_or_create(driver=driver, vehicle=vehicle, defaults={"is_primary": True})

            if Booking.objects.filter(driver=driver).exists():
                continue

            create_booking(
                driver=driver,
                vehicle=vehicle,
                contact_name=name,
                contact_phone=phone,
                issue_type=issue,
                description="Front nearside tyre down, vehicle immobilised.",
                tyre_size=vehicle.tyre_size_front,
                location_text=location,
                source=Booking.Source.WEBSITE,
            )

        first = Booking.objects.order_by("created_at").first()
        if first and first.status == Booking.Status.RECEIVED:
            transition_booking(first, Booking.Status.ASSIGNED, changed_by=owner, assigned_to=fitter)

        self.stdout.write(self.style.SUCCESS(
            f"Seeded {StaffUser.objects.count()} staff, {Driver.objects.count()} drivers, "
            f"{Booking.objects.count()} bookings."
        ))
