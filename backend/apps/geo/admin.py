from django.contrib import admin

from .models import ServiceArea
from .services import invalidate_cache


@admin.register(ServiceArea)
class ServiceAreaAdmin(admin.ModelAdmin):
    list_display = ("name", "is_active", "priority", "updated_at")
    list_filter = ("is_active",)
    search_fields = ("name",)

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        invalidate_cache()
