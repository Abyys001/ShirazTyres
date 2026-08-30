"""The audit trail for dispatch.

Specification section 13: when a job goes unclaimed this must show exactly which drivers
were contacted, when, and whether each rejected or simply never responded.
"""

from django.db import models

from apps.bookings.models import Job
from apps.drivers.models import Driver
from apps.geo.models import ServiceArea


class DispatchAttempt(models.Model):
    """One round of dispatch: one automatic assignment, or one batch of offers."""

    class Mode(models.TextChoices):
        AUTOMATIC = "automatic", "Automatic assignment"
        SELECTION = "selection", "Driver selection"

    class Outcome(models.TextChoices):
        PENDING = "pending", "Awaiting a response"
        ACCEPTED = "accepted", "A driver accepted"
        REJECTED = "rejected", "Every driver rejected"
        TIMED_OUT = "timed_out", "Nobody responded in time"
        NO_CANDIDATES = "no_candidates", "No eligible driver was available"
        SUPERSEDED = "superseded", "Overtaken by a later round or a manual change"

    job = models.ForeignKey(Job, on_delete=models.CASCADE, related_name="dispatch_attempts")
    round_number = models.PositiveSmallIntegerField()
    mode = models.CharField(max_length=16, choices=Mode.choices)
    outcome = models.CharField(
        max_length=16, choices=Outcome.choices, default=Outcome.PENDING, db_index=True
    )
    radius_km = models.DecimalField(max_digits=6, decimal_places=2)
    timeout_seconds = models.PositiveIntegerField()
    service_area = models.ForeignKey(
        ServiceArea, null=True, blank=True, on_delete=models.SET_NULL, related_name="dispatch_attempts"
    )
    candidates_considered = models.PositiveSmallIntegerField(default=0)
    note = models.CharField(max_length=255, blank=True)
    started_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-started_at",)
        constraints = [
            models.UniqueConstraint(fields=["job", "round_number"], name="unique_dispatch_round")
        ]
        indexes = [models.Index(fields=["outcome", "expires_at"])]

    def __str__(self):
        return f"{self.job.reference} round {self.round_number} ({self.get_outcome_display()})"

    @property
    def is_live(self) -> bool:
        return self.outcome == self.Outcome.PENDING


class DispatchOffer(models.Model):
    """One driver's side of a round. Rejection is a first-class outcome — section 6.3."""

    class State(models.TextChoices):
        OFFERED = "offered", "Offered"
        ACCEPTED = "accepted", "Accepted"
        REJECTED = "rejected", "Rejected"
        WITHDRAWN = "withdrawn", "Withdrawn — taken by another driver"
        TIMED_OUT = "timed_out", "No response"

    attempt = models.ForeignKey(DispatchAttempt, on_delete=models.CASCADE, related_name="offers")
    driver = models.ForeignKey(Driver, on_delete=models.CASCADE, related_name="dispatch_offers")
    rank = models.PositiveSmallIntegerField(help_text="1 is the best-ranked driver of the round.")
    eta_seconds = models.PositiveIntegerField(null=True, blank=True)
    distance_metres = models.PositiveIntegerField(null=True, blank=True)
    state = models.CharField(max_length=16, choices=State.choices, default=State.OFFERED, db_index=True)
    reason = models.CharField(max_length=255, blank=True)
    offered_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("rank",)
        constraints = [
            models.UniqueConstraint(fields=["attempt", "driver"], name="unique_offer_per_attempt")
        ]
        indexes = [models.Index(fields=["driver", "state"])]

    def __str__(self):
        return f"{self.attempt.job.reference} → {self.driver} ({self.get_state_display()})"

    @property
    def is_live(self) -> bool:
        return self.state == self.State.OFFERED
