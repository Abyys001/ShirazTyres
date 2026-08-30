from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    CustomerJobViewSet,
    DriverJobViewSet,
    DriverOfferListView,
    JobInvoiceView,
    JobViewSet,
)

router = DefaultRouter(trailing_slash=False)
router.register("jobs", JobViewSet, basename="job")
router.register("my/jobs", CustomerJobViewSet, basename="my-job")
router.register("driver/jobs", DriverJobViewSet, basename="driver-job")

urlpatterns = [
    path("driver/offers", DriverOfferListView.as_view(), name="driver-offers"),
    path("jobs/<int:pk>/invoice", JobInvoiceView.as_view(), name="job-invoice"),
    path("", include(router.urls)),
]
