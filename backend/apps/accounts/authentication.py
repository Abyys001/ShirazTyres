from django.utils.translation import gettext_lazy as _
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed, InvalidToken

from .models import Driver, StaffUser
from .tokens import SCOPE_CLAIM, SCOPE_DRIVER, SCOPE_STAFF, SUBJECT_CLAIM


class ScopedJWTAuthentication(JWTAuthentication):
    scope: str = ""
    model = None

    def authenticate(self, request):
        header = self.get_header(request)
        if header is None:
            return None
        raw_token = self.get_raw_token(header)
        if raw_token is None:
            return None

        validated_token = self.get_validated_token(raw_token)
        if validated_token.get(SCOPE_CLAIM) != self.scope:
            # Another audience's token — returning None lets the next class try it.
            return None
        return self.get_user(validated_token), validated_token

    def get_user(self, validated_token):
        try:
            subject_id = validated_token[SUBJECT_CLAIM]
        except KeyError as exc:
            raise InvalidToken(_("Token contained no recognisable subject.")) from exc

        try:
            subject = self.model.objects.get(pk=subject_id)
        except self.model.DoesNotExist as exc:
            raise AuthenticationFailed(_("Account not found."), code="user_not_found") from exc

        if not subject.is_active:
            raise AuthenticationFailed(_("Account is disabled."), code="user_inactive")
        return subject


class StaffJWTAuthentication(ScopedJWTAuthentication):
    scope = SCOPE_STAFF
    model = StaffUser


class DriverJWTAuthentication(ScopedJWTAuthentication):
    scope = SCOPE_DRIVER
    model = Driver
