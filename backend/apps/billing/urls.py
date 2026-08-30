from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import DriverServiceItemListView, InvoiceViewSet, ServiceItemViewSet

router = DefaultRouter(trailing_slash=False)
router.register("service-items", ServiceItemViewSet, basename="service-item")
router.register("invoices", InvoiceViewSet, basename="invoice")

urlpatterns = [
    path("driver/service-items", DriverServiceItemListView.as_view(), name="driver-service-items"),
    path("", include(router.urls)),
]
