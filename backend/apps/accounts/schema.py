"""Teaches drf-spectacular about the three custom authentication classes.

Imported from AccountsConfig.ready() — extensions register on import.
"""

from drf_spectacular.extensions import OpenApiAuthenticationExtension


class _BearerScheme(OpenApiAuthenticationExtension):
    name = ""
    audience = ""

    def get_security_definition(self, auto_schema):
        return {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": f"JWT issued for the {self.audience} audience.",
        }


class StaffJWTScheme(_BearerScheme):
    target_class = "apps.accounts.authentication.StaffJWTAuthentication"
    name = "staffJWT"
    audience = "staff"


class CustomerJWTScheme(_BearerScheme):
    target_class = "apps.accounts.authentication.CustomerJWTAuthentication"
    name = "customerJWT"
    audience = "customer"


class DriverJWTScheme(_BearerScheme):
    target_class = "apps.accounts.authentication.DriverJWTAuthentication"
    name = "driverJWT"
    audience = "driver"
