from django.contrib import admin

from .models import Driver, DriverDocument, DriverLocation, DriverVehicle


class DriverVehicleInline(admin.TabularInline):
    model = DriverVehicle
    extra = 0


class DriverDocumentInline(admin.TabularInline):
    model = DriverDocument
    extra = 0
    readonly_fields = ("reviewed_by", "reviewed_at")


@admin.register(Driver)
class DriverAdmin(admin.ModelAdmin):
    list_display = ("name", "phone", "verification_status", "is_online", "is_active", "last_login_at")
    list_filter = ("verification_status", "is_online", "is_active", "service_areas")
    search_fields = ("name", "phone", "email", "employment_reference")
    filter_horizontal = ("service_areas",)
    readonly_fields = ("latitude", "longitude", "location_updated_at", "went_online_at")
    inlines = [DriverVehicleInline, DriverDocumentInline]


@admin.register(DriverDocument)
class DriverDocumentAdmin(admin.ModelAdmin):
    list_display = ("driver", "document_type", "status", "expiry_date", "reviewed_at")
    list_filter = ("document_type", "status")
    search_fields = ("driver__name", "driver__phone", "reference")


@admin.register(DriverLocation)
class DriverLocationAdmin(admin.ModelAdmin):
    list_display = ("driver", "latitude", "longitude", "accuracy_m", "recorded_at")
    list_filter = ("driver",)
    readonly_fields = tuple(field.name for field in DriverLocation._meta.fields)
