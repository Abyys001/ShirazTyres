from django.contrib import admin

from .models import Invoice, InvoiceLineItem, ServiceItem


@admin.register(ServiceItem)
class ServiceItemAdmin(admin.ModelAdmin):
    list_display = ("name", "code", "kind", "unit_price", "is_active", "sort_order")
    list_filter = ("kind", "is_active")
    search_fields = ("name", "code")


class InvoiceLineItemInline(admin.TabularInline):
    model = InvoiceLineItem
    extra = 0


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ("job", "status", "total", "payment_method", "issued_at", "paid_at")
    list_filter = ("status", "payment_method")
    search_fields = ("job__reference", "payment_reference")
    readonly_fields = ("subtotal", "vat_amount", "total")
    inlines = [InvoiceLineItemInline]
