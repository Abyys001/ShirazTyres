from django.contrib import admin

from .models import AuditEvent


@admin.register(AuditEvent)
class AuditEventAdmin(admin.ModelAdmin):
    list_display = ("created_at", "category", "severity", "message", "actor")
    list_filter = ("category", "severity")
    search_fields = ("message", "actor", "subject_id")
    date_hierarchy = "created_at"

    def has_add_permission(self, request):
        """Append-only, and only ever by the system."""
        return False

    def has_change_permission(self, request, obj=None):
        return False
