"""WebSocket endpoints. Section 11.1 for the panel's live map; section 4.6 for the
customer's ETA feed; the driver's own channel for offers that must not wait on a poll.

The token is read from the query string because browsers cannot set headers on a
WebSocket handshake. It is the same scoped access token the REST API takes, and it is
verified the same way — the scope claim decides which groups the socket may join.
"""

import json
import logging
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError

from apps.accounts.tokens import SCOPE_CUSTOMER, SCOPE_DRIVER, SCOPE_STAFF, read_scoped_token

from . import groups

logger = logging.getLogger(__name__)

#: A wrong audience raises ``InvalidToken``, which is a DRF exception rather than a
#: ``TokenError`` — catching only the latter would turn a refusal into a 500.
TOKEN_ERRORS = (InvalidToken, TokenError, KeyError, ValueError)


class ScopedConsumer(AsyncWebsocketConsumer):
    scope_name: str = ""

    async def connect(self):
        token = self._token()
        if not token:
            await self.close(code=4401)
            return
        try:
            subject_id = read_scoped_token(token, self.scope_name)
        except TOKEN_ERRORS:
            await self.close(code=4401)
            return

        if not await self.authorise(subject_id):
            await self.close(code=4403)
            return

        self.subject_id = subject_id
        for group in await self.group_names(subject_id):
            await self.channel_layer.group_add(group, self.channel_name)
            self.joined = getattr(self, "joined", [])
            self.joined.append(group)

        await self.accept()
        await self.send(json.dumps({"event": "connected", "scope": self.scope_name}))

    async def disconnect(self, code):
        for group in getattr(self, "joined", []):
            await self.channel_layer.group_discard(group, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        """These sockets are one-way. A ping keeps intermediaries from closing them."""
        if text_data and text_data.strip() in {"ping", '{"type":"ping"}'}:
            await self.send(json.dumps({"event": "pong"}))

    async def broadcast(self, message):
        await self.send(json.dumps(message["payload"], default=str))

    def _token(self) -> str:
        query = parse_qs(self.scope.get("query_string", b"").decode())
        return (query.get("token") or [""])[0]

    async def authorise(self, subject_id: int) -> bool:
        return True

    async def group_names(self, subject_id: int) -> list[str]:
        raise NotImplementedError


class PanelConsumer(ScopedConsumer):
    """Live job queue and driver map for the owner panel."""

    scope_name = SCOPE_STAFF

    @database_sync_to_async
    def authorise(self, subject_id):
        from apps.accounts.models import StaffUser

        return StaffUser.objects.filter(pk=subject_id, is_active=True).exists()

    async def group_names(self, subject_id):
        return [groups.PANEL]


class CustomerConsumer(ScopedConsumer):
    """Status and ETA for this customer's own jobs. Never a driver position."""

    scope_name = SCOPE_CUSTOMER

    @database_sync_to_async
    def authorise(self, subject_id):
        from apps.accounts.models import Customer

        return Customer.objects.filter(pk=subject_id, is_active=True).exists()

    async def group_names(self, subject_id):
        return [groups.customer_group(subject_id)]


class DriverConsumer(ScopedConsumer):
    """Offers, withdrawals and status changes for one driver."""

    scope_name = SCOPE_DRIVER

    @database_sync_to_async
    def authorise(self, subject_id):
        from apps.drivers.models import Driver

        return Driver.objects.filter(pk=subject_id, is_active=True).exists()

    async def group_names(self, subject_id):
        return [groups.driver_group(subject_id)]
