from django.contrib import admin

from .models import DispatchAttempt, DispatchOffer


class DispatchOfferInline(admin.TabularInline):
    model = DispatchOffer
    extra = 0
    readonly_fields = ("driver", "rank", "eta_seconds", "distance_metres", "state", "reason",
                       "offered_at", "responded_at")
    can_delete = False


@admin.register(DispatchAttempt)
class DispatchAttemptAdmin(admin.ModelAdmin):
    list_display = ("job", "round_number", "mode", "outcome", "radius_km", "started_at", "resolved_at")
    list_filter = ("mode", "outcome")
    search_fields = ("job__reference",)
    readonly_fields = tuple(field.name for field in DispatchAttempt._meta.fields)
    inlines = [DispatchOfferInline]
