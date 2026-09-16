from django.db import models


class AuditEvent(models.Model):
    """
    One thing that happened, written down.

    The system already kept records of the things it was proud of —
    ``JobStatusEvent`` for the lifecycle, ``DispatchAttempt`` for offers,
    ``Notification`` for messages that went out. What it had nowhere to put was
    everything else: a verification code issued, an email that failed to send, a
    setting changed at two in the morning, a Stripe webhook arriving twice. Those
    only existed in the container's stdout, which is gone the moment it restarts.

    This is that place. It is an append-only operational record, not a second
    copy of the domain: the models above remain the authority on what a job or an
    invoice *is*, and this answers "what happened, when, and who did it" when
    somebody is trying to work out why the system behaved as it did.

    Deliberately not a foreign key to the subject. Events outlive the rows they
    describe — the interesting question is usually about something that has since
    been deleted — so the subject is recorded as type-and-id text and the payload
    carries whatever else mattered at the time.
    """

    class Category(models.TextChoices):
        AUTH = "auth", "Sign-in and OTP"
        SMS = "sms", "SMS"
        EMAIL = "email", "Email"
        PUSH = "push", "Push notification"
        JOB = "job", "Job"
        DISPATCH = "dispatch", "Dispatch"
        BILLING = "billing", "Billing"
        STRIPE = "stripe", "Stripe"
        SETTINGS = "settings", "Settings"
        DRIVER = "driver", "Driver"
        STAFF = "staff", "Staff"
        SYSTEM = "system", "System"

    class Severity(models.TextChoices):
        DEBUG = "debug", "Debug"
        INFO = "info", "Info"
        WARNING = "warning", "Warning"
        ERROR = "error", "Error"

    category = models.CharField(max_length=16, choices=Category.choices, db_index=True)
    severity = models.CharField(
        max_length=8, choices=Severity.choices, default=Severity.INFO, db_index=True
    )
    message = models.CharField(max_length=255)

    #: Who caused it, as free text — "Shop Owner", "driver:Amir Hosseini", "system".
    actor = models.CharField(max_length=120, blank=True, db_index=True)
    #: What it was about — "job", "invoice", "driver" — and that row's id.
    subject_type = models.CharField(max_length=40, blank=True, db_index=True)
    subject_id = models.CharField(max_length=64, blank=True, db_index=True)

    #: Anything else worth keeping. Never secrets — see ``services.record``.
    payload = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ("-created_at", "-id")
        indexes = [
            # The log is read newest-first, usually filtered to one category.
            models.Index(fields=["category", "-created_at"]),
            models.Index(fields=["severity", "-created_at"]),
        ]

    def __str__(self):
        return f"[{self.category}] {self.message}"
