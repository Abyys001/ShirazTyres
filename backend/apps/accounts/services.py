"""OTP issue/verify, and resolving a sign-in to exactly one Customer.

Codes are hashed at rest — a database leak must not hand over live codes.
"""

import logging
import secrets
from dataclasses import dataclass
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from .google import GoogleProfile
from .models import Customer, OtpCode, SocialIdentity

logger = logging.getLogger(__name__)


class OtpError(serializers.ValidationError):
    pass


@dataclass(frozen=True)
class OtpIssueResult:
    expires_at: timezone.datetime
    resend_after_seconds: int
    debug_code: str | None


def _generate_code() -> str:
    upper = 10**settings.OTP_CODE_LENGTH
    return str(secrets.randbelow(upper)).zfill(settings.OTP_CODE_LENGTH)


def issue_otp(phone: str, purpose: str = OtpCode.Purpose.LOGIN) -> OtpIssueResult:
    from apps.notifications.services import send_sms

    now = timezone.now()
    last = OtpCode.objects.filter(phone=phone, purpose=purpose).order_by("-created_at").first()
    if last:
        cooldown_ends = last.created_at + timedelta(seconds=settings.OTP_RESEND_COOLDOWN_SECONDS)
        if cooldown_ends > now:
            raise OtpError(
                {"phone": [f"Please wait {int((cooldown_ends - now).total_seconds())}s before requesting another code."]}
            )

    code = _generate_code()
    expires_at = now + timedelta(seconds=settings.OTP_TTL_SECONDS)

    with transaction.atomic():
        # Any earlier live code for this phone/purpose is retired so only one can be redeemed.
        OtpCode.objects.filter(phone=phone, purpose=purpose, consumed_at__isnull=True).update(consumed_at=now)
        OtpCode.objects.create(
            phone=phone, purpose=purpose, code_hash=make_password(code), expires_at=expires_at
        )

    send_sms(
        phone,
        f"Your ShirazTyres verification code is {code}. "
        f"It expires in {settings.OTP_TTL_SECONDS // 60} minutes.",
    )
    logger.info("otp.issued phone=%s purpose=%s", phone[-4:].rjust(len(phone), "*"), purpose)

    # The code itself is written down only where it is already public: with the
    # mock provider there is no text message to read it out of, so the API
    # returns it as `debug_code` and the sign-in screens print it. Against a real
    # provider it is a live credential and the log records only that one was sent.
    from apps.audit.services import otp_is_visible, record

    visible = otp_is_visible()
    record(
        "auth",
        f"Verification code sent to {phone} ({purpose})",
        actor="system",
        subject_type="phone",
        subject_id=phone,
        purpose=purpose,
        expires_at=expires_at.isoformat(),
        code=code if visible else "[not recorded — live SMS provider]",
    )

    return OtpIssueResult(
        expires_at=expires_at,
        resend_after_seconds=settings.OTP_RESEND_COOLDOWN_SECONDS,
        debug_code=code if settings.SMS_PROVIDER == "mock" else None,
    )


def verify_otp(phone: str, code: str, purpose: str = OtpCode.Purpose.LOGIN) -> None:
    """Attempt counters must survive the rejection, so the error is raised after the commit."""
    error: dict | None = None

    with transaction.atomic():
        otp = (
            OtpCode.objects.select_for_update()
            .filter(phone=phone, purpose=purpose, consumed_at__isnull=True)
            .order_by("-created_at")
            .first()
        )
        now = timezone.now()

        if otp is None:
            error = {"code": ["No verification code was requested for this number."]}
        elif otp.expires_at <= now:
            error = {"code": ["This code has expired. Request a new one."]}
        elif otp.attempts >= settings.OTP_MAX_ATTEMPTS:
            otp.consumed_at = now
            otp.save(update_fields=["consumed_at"])
            error = {"code": ["Too many incorrect attempts. Request a new code."]}
        else:
            otp.attempts += 1
            if check_password(code, otp.code_hash):
                otp.consumed_at = now
                otp.save(update_fields=["attempts", "consumed_at"])
            else:
                otp.save(update_fields=["attempts"])
                remaining = settings.OTP_MAX_ATTEMPTS - otp.attempts
                error = {"code": [f"Incorrect code. {remaining} attempt(s) remaining."]}

    from apps.audit.models import AuditEvent
    from apps.audit.services import record

    if error:
        # Repeated failures on one number are what a brute-force attempt looks
        # like from here, so they are logged at warning with the reason intact.
        record(
            "auth",
            f"Verification failed for {phone} ({purpose})",
            severity=AuditEvent.Severity.WARNING,
            actor="system",
            subject_type="phone",
            subject_id=phone,
            purpose=purpose,
            reason=next(iter(error.values()))[0],
        )
        raise OtpError(error)

    record(
        "auth",
        f"Verified {phone} ({purpose})",
        actor="system",
        subject_type="phone",
        subject_id=phone,
        purpose=purpose,
    )


def _touch_login(customer: Customer, updates: list[str]) -> None:
    customer.last_login_at = timezone.now()
    updates.append("last_login_at")
    customer.save(update_fields=list(dict.fromkeys(updates)))


def get_or_create_customer_by_phone(phone: str, name: str = "", email: str = "") -> tuple[Customer, bool]:
    customer, created = Customer.objects.get_or_create(
        phone=phone, defaults={"name": name, "email": email, "is_phone_verified": True}
    )
    updates: list[str] = []
    if not customer.is_phone_verified:
        customer.is_phone_verified = True
        updates.append("is_phone_verified")
    if name and not customer.name:
        customer.name = name
        updates.append("name")
    if email and not customer.email:
        customer.email = email
        updates.append("email")
    _touch_login(customer, updates)
    return customer, created


def get_or_create_customer_by_google(profile: GoogleProfile) -> tuple[Customer, bool]:
    """Section 4.1: Google and phone OTP must resolve to the same account.

    Matching on a *verified* Google email is what joins the two routes. An unverified
    Google email is not evidence of ownership, so it starts a fresh account instead.
    """
    identity = (
        SocialIdentity.objects.select_related("customer")
        .filter(provider=SocialIdentity.Provider.GOOGLE, subject=profile.subject)
        .first()
    )
    if identity is not None:
        customer = identity.customer
        identity.last_used_at = timezone.now()
        identity.save(update_fields=["last_used_at"])
        _touch_login(customer, [])
        return customer, False

    created = False
    with transaction.atomic():
        customer = None
        if profile.email and profile.email_verified:
            customer = Customer.objects.filter(email__iexact=profile.email).first()

        if customer is None:
            customer = Customer.objects.create(
                name=profile.name,
                email=profile.email,
                photo_url=profile.picture,
                is_email_verified=profile.email_verified,
            )
            created = True

        SocialIdentity.objects.create(
            customer=customer,
            provider=SocialIdentity.Provider.GOOGLE,
            subject=profile.subject,
            email=profile.email,
            last_used_at=timezone.now(),
        )

    updates: list[str] = []
    if profile.name and not customer.name:
        customer.name = profile.name
        updates.append("name")
    if profile.email and not customer.email:
        customer.email = profile.email
        updates.append("email")
    if profile.email_verified and not customer.is_email_verified:
        customer.is_email_verified = True
        updates.append("is_email_verified")
    if profile.picture and not customer.photo_url:
        customer.photo_url = profile.picture
        updates.append("photo_url")
    _touch_login(customer, updates)
    return customer, created


def attach_phone_to_customer(customer: Customer, phone: str) -> Customer:
    """A Google-first customer adding their number. If that number already belongs to
    another account the two are merged, so the customer keeps one job history."""
    existing = Customer.objects.filter(phone=phone).exclude(pk=customer.pk).first()
    if existing is not None:
        merge_customers(keep=customer, absorb=existing)
    customer.phone = phone
    customer.is_phone_verified = True
    customer.save(update_fields=["phone", "is_phone_verified"])
    return customer


def merge_customers(*, keep: Customer, absorb: Customer) -> Customer:
    """Move everything the absorbed account owns onto the surviving one, then delete it."""
    from apps.bookings.models import Job
    from apps.notifications.models import DeviceToken
    from apps.vehicles.models import CustomerVehicle

    with transaction.atomic():
        Job.objects.filter(customer=absorb).update(customer=keep)
        DeviceToken.objects.filter(customer=absorb).update(customer=keep)
        SocialIdentity.objects.filter(customer=absorb).update(customer=keep)

        kept_vehicle_ids = set(
            CustomerVehicle.objects.filter(customer=keep).values_list("vehicle_id", flat=True)
        )
        for link in CustomerVehicle.objects.filter(customer=absorb):
            if link.vehicle_id in kept_vehicle_ids:
                link.delete()
            else:
                link.customer = keep
                link.save(update_fields=["customer"])

        if not keep.name and absorb.name:
            keep.name = absorb.name
        if not keep.email and absorb.email:
            keep.email = absorb.email
        keep.save(update_fields=["name", "email"])

        absorb_id = absorb.pk
        absorb.delete()

    logger.info("customer.merged kept=%s absorbed=%s", keep.pk, absorb_id)
    return keep
