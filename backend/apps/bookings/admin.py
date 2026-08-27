from django.contrib import admin

from .models import Booking, BookingStatusEvent


class BookingStatusEventInline(admin.TabularInline):
    model = BookingStatusEvent
    extra = 0
    readonly_fields = ("from_status", "to_status", "note", "changed_by", "created_at")
    can_delete = False


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("reference", "contact_name", "contact_phone", "plate", "issue_type", "status", "source", "created_at")
    list_filter = ("status", "issue_type", "source")
    search_fields = ("reference", "contact_name", "contact_phone", "vehicle__plate")
    readonly_fields = ("reference", "created_at", "updated_at", "assigned_at", "completed_at")
    inlines = [BookingStatusEventInline]
    autocomplete_fields = ("driver", "vehicle", "assigned_to")
