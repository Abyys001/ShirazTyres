from django.contrib import admin

from .models import DeviceToken, Notification


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("platform", "customer", "driver", "staff", "is_active", "last_seen_at")
    list_filter = ("platform", "is_active")


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("channel", "event", "recipient", "status", "job", "created_at", "sent_at")
    list_filter = ("channel", "status", "event")
    search_fields = ("recipient", "job__reference")
    readonly_fields = tuple(field.name for field in Notification._meta.fields)
