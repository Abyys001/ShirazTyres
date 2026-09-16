from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone


class StaffUserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError("Staff users require an email address.")
        user = self.model(email=self.normalize_email(email), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("role", StaffUser.Role.OWNER)
        if not extra["is_staff"] or not extra["is_superuser"]:
            raise ValueError("Superuser must have is_staff and is_superuser set.")
        return self.create_user(email, password, **extra)


class StaffUser(AbstractBaseUser, PermissionsMixin):
    """Owner and office staff. A separate audience from customers and from drivers."""

    class Role(models.TextChoices):
        OWNER = "owner", "Owner"
        SHOP_OWNER = "shop_owner", "Shop owner"
        STAFF = "staff", "Office"

    #: Roles that may administer the business rather than merely work in it —
    #: manage staff, change settings, void invoices. Section 17 keeps multi-branch
    #: out of version 1, so a shop owner is a role, not a tenant: they see the
    #: same single business the owner does, and the distinction is what they may
    #: change, not what they may see.
    ADMIN_ROLES = frozenset({Role.OWNER, Role.SHOP_OWNER})

    email = models.EmailField(unique=True)
    name = models.CharField(max_length=120)
    role = models.CharField(max_length=16, choices=Role.choices, default=Role.STAFF)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=True)
    date_joined = models.DateTimeField(default=timezone.now)

    objects = StaffUserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["name"]

    class Meta:
        verbose_name = "staff user"
        ordering = ("name",)

    def __str__(self):
        return f"{self.name} <{self.email}>"

    @property
    def is_owner(self):
        return self.role == self.Role.OWNER

    @property
    def is_admin(self):
        """Owner or shop owner — allowed to change how the business runs."""
        return self.role in self.ADMIN_ROLES


class Customer(models.Model):
    """The stranded motorist. Not a Django user — a separate audience with its own tokens.

    Both sign-in routes land here: Google resolves through ``SocialIdentity``, phone OTP
    through ``phone``. Specification section 4.1 requires that they reach the same record.
    """

    phone = models.CharField(max_length=20, unique=True, null=True, blank=True, db_index=True)
    name = models.CharField(max_length=120, blank=True)
    email = models.EmailField(blank=True, db_index=True)
    photo_url = models.URLField(blank=True)
    is_phone_verified = models.BooleanField(default=False)
    is_email_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    notes = models.TextField(blank=True, help_text="Internal notes, visible to staff only.")
    created_by_staff = models.ForeignKey(
        StaffUser, null=True, blank=True, on_delete=models.SET_NULL, related_name="created_customers"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_login_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.name or 'Customer'} ({self.phone or self.email or self.pk})"

    @property
    def is_authenticated(self):
        """Lets DRF permission classes treat a Customer like an authenticated principal."""
        return True

    @property
    def display_name(self):
        return self.name or self.phone or self.email or f"Customer #{self.pk}"


class SocialIdentity(models.Model):
    """One row per external identity. Unique on (provider, subject) so a second Google
    sign-in reaches the existing customer instead of forking a new account."""

    class Provider(models.TextChoices):
        GOOGLE = "google", "Google"

    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name="identities")
    provider = models.CharField(max_length=16, choices=Provider.choices)
    subject = models.CharField(max_length=191, help_text="The provider's stable user id.")
    email = models.EmailField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["provider", "subject"], name="unique_social_identity")
        ]
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.get_provider_display()} identity for {self.customer}"


class OtpCode(models.Model):
    class Purpose(models.TextChoices):
        LOGIN = "login", "Login or registration"
        JOB = "job", "Confirm emergency request"
        DRIVER = "driver", "Driver sign-in"

    phone = models.CharField(max_length=20, db_index=True)
    purpose = models.CharField(max_length=16, choices=Purpose.choices, default=Purpose.LOGIN)
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    consumed_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["phone", "purpose", "-created_at"])]

    def __str__(self):
        return f"OTP {self.purpose} for {self.phone}"

    @property
    def is_usable(self):
        from django.conf import settings

        return (
            self.consumed_at is None
            and self.expires_at > timezone.now()
            and self.attempts < settings.OTP_MAX_ATTEMPTS
        )
