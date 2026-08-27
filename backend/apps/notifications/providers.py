"""SMS and push providers behind one interface, so dev/CI cost nothing and the swap is a setting."""

import json
import logging
from dataclasses import dataclass

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class ProviderError(Exception):
    pass


@dataclass
class SendResult:
    message_id: str = ""


class MockSmsProvider:
    def send(self, to: str, body: str) -> SendResult:
        logger.info("sms.mock to=%s body=%s", to, body)
        return SendResult(message_id="mock-sms")


class TwilioSmsProvider:
    def send(self, to: str, body: str) -> SendResult:
        if not (settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN and settings.TWILIO_FROM_NUMBER):
            raise ProviderError("Twilio credentials are not configured.")
        url = f"https://api.twilio.com/2010-04-01/Accounts/{settings.TWILIO_ACCOUNT_SID}/Messages.json"
        try:
            response = requests.post(
                url,
                data={"To": to, "From": settings.TWILIO_FROM_NUMBER, "Body": body},
                auth=(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN),
                timeout=settings.EXTERNAL_HTTP_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise ProviderError(f"Twilio request failed: {exc}") from exc

        if response.status_code >= 400:
            raise ProviderError(f"Twilio rejected the message: {response.text[:200]}")
        return SendResult(message_id=response.json().get("sid", ""))


class MockPushProvider:
    def send(self, token: str, title: str, body: str, data: dict | None = None) -> SendResult:
        logger.info("push.mock token=%s title=%s body=%s data=%s", token[:12], title, body, data)
        return SendResult(message_id="mock-push")


class FcmPushProvider:
    """FCM HTTP v1. Access token comes from the service-account file named in settings."""

    _SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

    def _access_token(self) -> str:
        try:
            from google.auth.transport.requests import Request
            from google.oauth2 import service_account
        except ImportError as exc:
            raise ProviderError("google-auth is required for the FCM provider.") from exc

        credentials = service_account.Credentials.from_service_account_file(
            settings.FCM_CREDENTIALS_FILE, scopes=[self._SCOPE]
        )
        credentials.refresh(Request())
        return credentials.token

    def send(self, token: str, title: str, body: str, data: dict | None = None) -> SendResult:
        if not (settings.FCM_PROJECT_ID and settings.FCM_CREDENTIALS_FILE):
            raise ProviderError("FCM is not configured.")
        url = f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send"
        payload = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": {key: str(value) for key, value in (data or {}).items()},
                "android": {"priority": "high"},
                "apns": {"headers": {"apns-priority": "10"}},
            }
        }
        try:
            response = requests.post(
                url,
                data=json.dumps(payload),
                headers={
                    "Authorization": f"Bearer {self._access_token()}",
                    "Content-Type": "application/json; UTF-8",
                },
                timeout=settings.EXTERNAL_HTTP_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise ProviderError(f"FCM request failed: {exc}") from exc

        if response.status_code >= 400:
            raise ProviderError(f"FCM rejected the message: {response.text[:200]}")
        return SendResult(message_id=response.json().get("name", ""))


def get_sms_provider():
    return TwilioSmsProvider() if settings.SMS_PROVIDER == "twilio" else MockSmsProvider()


def get_push_provider():
    return FcmPushProvider() if settings.PUSH_PROVIDER == "fcm" else MockPushProvider()
