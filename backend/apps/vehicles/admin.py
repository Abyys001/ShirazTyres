from django.contrib import admin

from .models import CustomerVehicle, Vehicle


@admin.register(Vehicle)
class VehicleAdmin(admin.ModelAdmin):
    list_display = ("plate", "make", "model", "tyre_size_front", "tyre_source", "mot_status", "updated_at")
    list_filter = ("tyre_source", "fuel_type", "mot_status")
    search_fields = ("plate", "make", "model")
    readonly_fields = ("raw_dvla", "raw_tyre", "dvla_fetched_at", "tyre_fetched_at")


@admin.register(CustomerVehicle)
class CustomerVehicleAdmin(admin.ModelAdmin):
    list_display = ("customer", "vehicle", "nickname", "confirmation_path", "confirmed_at")
    list_filter = ("confirmation_path", "is_primary")
    search_fields = ("customer__phone", "customer__name", "vehicle__plate")
