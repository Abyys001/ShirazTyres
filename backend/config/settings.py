from datetime import timedelta
from pathlib import Path

from celery.schedules import crontab

from .env import env, env_bool, env_float, env_int, env_list

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = env("DJANGO_SECRET_KEY", "insecure-dev-key-change-me")
DEBUG = env_bool("DJANGO_DEBUG", True)
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,backend")

INSTALLED_APPS = [
    # Ahead of staticfiles so runserver serves ASGI and the WebSocket routes work in dev.
    "daphne",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "django_filters",
    "corsheaders",
    "drf_spectacular",
    "channels",
    "apps.configuration",
    "apps.geo",
    "apps.accounts",
    "apps.drivers",
    "apps.vehicles",
    "apps.bookings",
    "apps.dispatch",
    "apps.billing",
    "apps.notifications",
    "apps.realtime",
    "apps.audit",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

USE_SQLITE = env_bool("USE_SQLITE", False)

if USE_SQLITE:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": env("POSTGRES_DB", "shiraztyres"),
            "USER": env("POSTGRES_USER", "shiraztyres"),
            "PASSWORD": env("POSTGRES_PASSWORD", "shiraztyres"),
            "HOST": env("POSTGRES_HOST", "db"),
            "PORT": env_int("POSTGRES_PORT", 5432),
        }
    }

CACHES = {
    "default": (
        {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}
        if USE_SQLITE
        else {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": env("REDIS_URL", "redis://redis:6379/1"),
        }
    )
}

# The channel layer carries the panel's live map and the driver offer stream. In-memory
# is correct for tests and single-process dev; it does not span workers, so anything
# else needs Redis.
CHANNEL_LAYERS = {
    "default": (
        {"BACKEND": "channels.layers.InMemoryChannelLayer"}
        if USE_SQLITE
        else {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {"hosts": [env("CHANNEL_LAYER_URL", "redis://redis:6379/2")]},
        }
    )
}

AUTH_USER_MODEL = "accounts.StaffUser"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-gb"
TIME_ZONE = "Europe/London"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = Path(env("MEDIA_ROOT", str(BASE_DIR / "media")))
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Driver documents and photos. Uploads are capped so a phone camera cannot fill the disk.
DATA_UPLOAD_MAX_MEMORY_SIZE = env_int("MAX_UPLOAD_BYTES", 10 * 1024 * 1024)
FILE_UPLOAD_MAX_MEMORY_SIZE = DATA_UPLOAD_MAX_MEMORY_SIZE

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "apps.accounts.authentication.StaffJWTAuthentication",
        "apps.accounts.authentication.CustomerJWTAuthentication",
        "apps.accounts.authentication.DriverJWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.OrderingFilter",
        "rest_framework.filters.SearchFilter",
    ),
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 25,
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_THROTTLE_CLASSES": ("rest_framework.throttling.ScopedRateThrottle",),
    "DEFAULT_THROTTLE_RATES": {
        "otp_request": env("THROTTLE_OTP_REQUEST", "5/hour"),
        "otp_verify": env("THROTTLE_OTP_VERIFY", "10/hour"),
        "vehicle_lookup": env("THROTTLE_VEHICLE_LOOKUP", "30/hour"),
        "driver_lookup": env("THROTTLE_DRIVER_LOOKUP", "120/hour"),
        "job_create": env("THROTTLE_JOB_CREATE", "10/hour"),
    },
    "EXCEPTION_HANDLER": "config.exceptions.api_exception_handler",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "ShirazTyres API",
    "DESCRIPTION": (
        "Emergency tyre dispatch platform — customer website, customer app, "
        "owner panel and driver app, against one backend."
    ),
    "VERSION": "2.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "SCHEMA_PATH_PREFIX": "/api/v1",
    # Four surfaces generate clients from this schema; colliding enum names would
    # give two of them a "Status91fEnum" and no way to tell which one they hold.
    "ENUM_NAME_OVERRIDES": {
        "JobStatusEnum": "apps.bookings.models.Job.Status",
        "InvoiceStatusEnum": "apps.billing.models.Invoice.Status",
        "DocumentStatusEnum": "apps.drivers.models.DriverDocument.Status",
        "VerificationStatusEnum": "apps.drivers.models.Driver.Verification",
        "ConfirmationPathEnum": "apps.vehicles.models.ConfirmationPath.choices",
    },
}

# The apps are installed on one phone and sign in once. `refresh_pair` mints a
# brand-new refresh on every use, so the window slides for anyone who opens the
# app; the lifetime below is really "how long a phone may sit untouched".
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env_int("JWT_ACCESS_MINUTES", 30)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env_int("JWT_REFRESH_DAYS", 180)),
    "SIGNING_KEY": SECRET_KEY,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

CORS_ALLOWED_ORIGINS = env_list("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:3001")
CSRF_TRUSTED_ORIGINS = env_list("CSRF_TRUSTED_ORIGINS", "http://localhost:3000,http://localhost:3001")

CELERY_BROKER_URL = env("CELERY_BROKER_URL", "redis://redis:6379/0")
CELERY_RESULT_BACKEND = env("CELERY_RESULT_BACKEND", "redis://redis:6379/0")
CELERY_TASK_ALWAYS_EAGER = env_bool("CELERY_TASK_ALWAYS_EAGER", False)
CELERY_TASK_EAGER_PROPAGATES = True
CELERY_TIMEZONE = TIME_ZONE

CELERY_BEAT_SCHEDULE = {
    # A lost countdown task would strand a job in `dispatching` with nobody waiting on it.
    "dispatch-sweep-expired": {
        "task": "apps.dispatch.tasks.sweep_expired_attempts",
        "schedule": timedelta(seconds=env_int("DISPATCH_SWEEP_SECONDS", 30)),
    },
    "drivers-warn-expiring-documents": {
        "task": "apps.drivers.tasks.warn_expiring_documents",
        "schedule": crontab(hour=8, minute=0),
    },
    "drivers-suspend-expired": {
        "task": "apps.drivers.tasks.suspend_drivers_with_expired_documents",
        "schedule": crontab(hour=0, minute=15),
    },
    "drivers-purge-locations": {
        "task": "apps.drivers.tasks.purge_driver_locations",
        "schedule": crontab(hour=3, minute=0),
    },
    "notifications-purge-otps": {
        "task": "apps.notifications.tasks.purge_expired_otps",
        "schedule": crontab(hour=3, minute=20),
    },
    "notifications-purge-old": {
        "task": "apps.notifications.tasks.purge_old_notifications",
        "schedule": crontab(hour=3, minute=40),
    },
}

# --- OTP -------------------------------------------------------------------
OTP_CODE_LENGTH = env_int("OTP_CODE_LENGTH", 6)
OTP_TTL_SECONDS = env_int("OTP_TTL_SECONDS", 300)
OTP_MAX_ATTEMPTS = env_int("OTP_MAX_ATTEMPTS", 5)
OTP_RESEND_COOLDOWN_SECONDS = env_int("OTP_RESEND_COOLDOWN_SECONDS", 10)

# --- Providers -------------------------------------------------------------
SMS_PROVIDER = env("SMS_PROVIDER", "mock")  # mock | twilio
TWILIO_ACCOUNT_SID = env("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = env("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM_NUMBER = env("TWILIO_FROM_NUMBER", "")

PUSH_PROVIDER = env("PUSH_PROVIDER", "mock")  # mock | fcm
FCM_PROJECT_ID = env("FCM_PROJECT_ID", "")
FCM_CREDENTIALS_FILE = env("FCM_CREDENTIALS_FILE", "")

GOOGLE_OAUTH_MOCK = env_bool("GOOGLE_OAUTH_MOCK", True)
GOOGLE_OAUTH_CLIENT_IDS = env_list("GOOGLE_OAUTH_CLIENT_IDS", "")

VEHICLE_LOOKUP_MOCK = env_bool("VEHICLE_LOOKUP_MOCK", True)
DVLA_VES_URL = env("DVLA_VES_URL", "https://driver-vehicle-licensing.api.gov.uk/vehicle-enquiry/v1/vehicles")
DVLA_API_KEY = env("DVLA_API_KEY", "")
TYRE_API_URL = env("TYRE_API_URL", "https://uk1.ukvehicledata.co.uk/api/datapackage/TyreData")
TYRE_API_KEY = env("TYRE_API_KEY", "")
VEHICLE_LOOKUP_TTL_DAYS = env_int("VEHICLE_LOOKUP_TTL_DAYS", 30)
EXTERNAL_HTTP_TIMEOUT = env_int("EXTERNAL_HTTP_TIMEOUT", 10)

# --- Maps and routing (section 10) -----------------------------------------
# mock | osrm | valhalla | graphhopper. Never point production at OSM's own servers.
ROUTING_PROVIDER = env("ROUTING_PROVIDER", "mock")
ROUTING_BASE_URL = env("ROUTING_BASE_URL", "http://osrm:5000")
ROUTING_API_KEY = env("ROUTING_API_KEY", "")
ROUTING_TIMEOUT = env_int("ROUTING_TIMEOUT", 8)

# Section 10.2: a stock routing profile is optimistic in central London. Calibrate these
# against observed journey times before launch — a consistently wrong ETA is worse than none.
ROUTING_TRAFFIC_FACTORS = {
    "default": env_float("TRAFFIC_FACTOR_DEFAULT", 1.15),
    "morning_peak": env_float("TRAFFIC_FACTOR_MORNING", 1.45),
    "evening_peak": env_float("TRAFFIC_FACTOR_EVENING", 1.50),
    "overnight": env_float("TRAFFIC_FACTOR_OVERNIGHT", 0.95),
    "weekend": env_float("TRAFFIC_FACTOR_WEEKEND", 1.10),
}

MAP_TILE_URL = env("MAP_TILE_URL", "")
MAP_TILE_ATTRIBUTION = env(
    "MAP_TILE_ATTRIBUTION", "© OpenStreetMap contributors"
)

# --- Where call-outs land ---------------------------------------------------
SHOP_NOTIFY_SMS = env_list("SHOP_NOTIFY_SMS", "")
SHOP_NOTIFY_EMAIL = env_list("SHOP_NOTIFY_EMAIL", "")
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", "no-reply@shiraztyres.co.uk")
EMAIL_BACKEND = env(
    "EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend" if DEBUG else "django.core.mail.backends.smtp.EmailBackend",
)
# --------------------------------------------------------------- Stripe -----
# Section 7.2: payment capture. `mock` needs no keys and touches no network, so
# the whole invoice flow runs locally and in tests with no spend. Never deploy on
# mock — /health reports the mode for exactly that reason.
STRIPE_MODE = env("STRIPE_MODE", "mock")  # mock | test | live
STRIPE_SECRET_KEY = env("STRIPE_SECRET_KEY", "")
STRIPE_PUBLISHABLE_KEY = env("STRIPE_PUBLISHABLE_KEY", "")
STRIPE_WEBHOOK_SECRET = env("STRIPE_WEBHOOK_SECRET", "")

EMAIL_HOST = env("EMAIL_HOST", "")
EMAIL_PORT = env_int("EMAIL_PORT", 587)
EMAIL_HOST_USER = env("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", True)

PANEL_BASE_URL = env("PANEL_BASE_URL", "http://localhost:3000")
CUSTOMER_BASE_URL = env("CUSTOMER_BASE_URL", "http://localhost:3001")

if not DEBUG:
    SECURE_SSL_REDIRECT = env_bool("SECURE_SSL_REDIRECT", True)
    SECURE_HSTS_SECONDS = env_int("SECURE_HSTS_SECONDS", 31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"simple": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "simple"}},
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", "INFO")},
}
