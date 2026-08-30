from django.contrib import admin

from .models import Setting
from .services import invalidate_cache


@admin.register(Setting)
class SettingAdmin(admin.ModelAdmin):
    list_display = ("key", "value", "updated_by", "updated_at")
    search_fields = ("key",)

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        invalidate_cache()

    def delete_model(self, request, obj):
        super().delete_model(request, obj)
        invalidate_cache()
