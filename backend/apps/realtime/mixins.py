"""Making the panel's catalogue screens live.

Jobs, drivers and invoices already announce themselves; the catalogue the office
works *from* — the settings, the price list, the service areas, the staff list —
did not. Two people in the office on the same screen would silently disagree
about the call-out fee until one of them reloaded, which is the failure the rest
of the realtime design exists to prevent.
"""

from django.db import transaction


class AnnouncesConfigChange:
    """Mix in ahead of the viewset base, and set :attr:`config_kind`.

    A subclass that overrides ``perform_create`` and friends must call ``super()``
    — as the service-area and staff viewsets do — or the announcement is skipped.
    """

    #: The suffix of the published event, e.g. ``"service-areas"`` -> ``config.service-areas``.
    config_kind: str = ""

    def perform_create(self, serializer):
        super().perform_create(serializer)
        self.announce_config_change()

    def perform_update(self, serializer):
        super().perform_update(serializer)
        self.announce_config_change()

    def perform_destroy(self, instance):
        super().perform_destroy(instance)
        self.announce_config_change()

    def announce_config_change(self) -> None:
        from .publish import publish_config_event

        kind = self.config_kind
        transaction.on_commit(lambda: publish_config_event(kind))
