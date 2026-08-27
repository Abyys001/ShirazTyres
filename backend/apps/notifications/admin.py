from django.contrib import admin

from .models import DeviceToken, Notification


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("platform", "driver", "staff", "is_active", "last_seen_at")
    list_filter = ("platform", "is_active")


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("channel", "recipient", "status", "booking", "created_at", "sent_at")
    list_filter = ("channel", "status")
    search_fields = ("recipient", "booking__reference")
    readonly_fields = tuple(field.name for field in Notification._meta.fields)
