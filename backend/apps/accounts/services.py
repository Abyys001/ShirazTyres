"""OTP issue/verify. Codes are hashed at rest — a database leak must not hand over live codes."""

import logging
import secrets
from dataclasses import dataclass
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from .models import Driver, OtpCode

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

    send_sms(phone, f"Your ShirazTyres verification code is {code}. It expires in {settings.OTP_TTL_SECONDS // 60} minutes.")
    logger.info("otp.issued phone=%s purpose=%s", phone[-4:].rjust(len(phone), "*"), purpose)

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

    if error:
        raise OtpError(error)


def get_or_create_driver(phone: str, name: str = "", email: str = "") -> tuple[Driver, bool]:
    driver, created = Driver.objects.get_or_create(
        phone=phone, defaults={"name": name, "email": email, "is_phone_verified": True}
    )
    updates = []
    if not driver.is_phone_verified:
        driver.is_phone_verified = True
        updates.append("is_phone_verified")
    if name and not driver.name:
        driver.name = name
        updates.append("name")
    if email and not driver.email:
        driver.email = email
        updates.append("email")
    driver.last_login_at = timezone.now()
    updates.append("last_login_at")
    driver.save(update_fields=updates)
    return driver, created
