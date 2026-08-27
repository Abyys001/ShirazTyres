from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import Driver, OtpCode, StaffUser


@admin.register(StaffUser)
class StaffUserAdmin(UserAdmin):
    list_display = ("email", "name", "role", "is_active", "date_joined")
    list_filter = ("role", "is_active", "is_superuser")
    search_fields = ("email", "name")
    ordering = ("name",)
    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Profile", {"fields": ("name", "role")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("email", "name", "role", "password1", "password2")}),
    )


@admin.register(Driver)
class DriverAdmin(admin.ModelAdmin):
    list_display = ("phone", "name", "is_phone_verified", "is_active", "created_at")
    list_filter = ("is_phone_verified", "is_active")
    search_fields = ("phone", "name", "email")


@admin.register(OtpCode)
class OtpCodeAdmin(admin.ModelAdmin):
    list_display = ("phone", "purpose", "attempts", "expires_at", "consumed_at", "created_at")
    list_filter = ("purpose",)
    search_fields = ("phone",)
    readonly_fields = ("code_hash",)
