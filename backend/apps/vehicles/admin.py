from django.contrib import admin

from .models import DriverVehicle, Vehicle


@admin.register(Vehicle)
class VehicleAdmin(admin.ModelAdmin):
    list_display = ("plate", "make", "model", "tyre_size_front", "tyre_source", "mot_status", "updated_at")
    list_filter = ("tyre_source", "fuel_type", "mot_status")
    search_fields = ("plate", "make", "model")
    readonly_fields = ("raw_dvla", "raw_tyre", "dvla_fetched_at", "tyre_fetched_at")


@admin.register(DriverVehicle)
class DriverVehicleAdmin(admin.ModelAdmin):
    list_display = ("driver", "vehicle", "nickname", "is_primary", "created_at")
    search_fields = ("driver__phone", "vehicle__plate")
