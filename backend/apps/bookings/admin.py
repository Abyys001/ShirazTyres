from django.contrib import admin

from .models import Job, JobStatusEvent


class JobStatusEventInline(admin.TabularInline):
    model = JobStatusEvent
    extra = 0
    readonly_fields = ("from_status", "to_status", "note", "actor_type",
                       "changed_by_staff", "changed_by_driver", "created_at")
    can_delete = False


@admin.register(Job)
class JobAdmin(admin.ModelAdmin):
    list_display = ("reference", "contact_name", "contact_phone", "plate", "issue_type",
                    "status", "driver", "source", "created_at")
    list_filter = ("status", "source", "service_area", "tyre_confirmation_path")
    search_fields = ("reference", "contact_name", "contact_phone", "vehicle__plate")
    readonly_fields = ("reference", "created_at", "updated_at", "dispatch_started_at",
                       "assigned_at", "accepted_at", "en_route_at", "arrived_at",
                       "started_at", "completed_at", "cancelled_at")
    inlines = [JobStatusEventInline]
    autocomplete_fields = ("customer", "vehicle", "driver", "assigned_staff")
