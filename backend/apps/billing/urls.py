from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import DriverServiceItemListView, InvoiceViewSet, ServiceItemViewSet
from .webhooks import StripeWebhookView

router = DefaultRouter(trailing_slash=False)
router.register("service-items", ServiceItemViewSet, basename="service-item")
router.register("invoices", InvoiceViewSet, basename="invoice")

urlpatterns = [
    path("driver/service-items", DriverServiceItemListView.as_view(), name="driver-service-items"),
    # Unauthenticated by necessity — Stripe has no session. The signature is the
    # gate; see apps/billing/webhooks.py.
    path("billing/stripe/webhook", StripeWebhookView.as_view(), name="stripe-webhook"),
    path("", include(router.urls)),
]
