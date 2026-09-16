from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    DocumentReviewView,
    DriverComplianceView,
    DriverDocumentViewSet,
    DriverLocationView,
    DriverMapView,
    DriverMeView,
    DriverOnlineView,
    DriverOtpVerifyView,
    DriverVehicleLookupView,
    DriverVehicleViewSet,
    DriverViewSet,
)

router = DefaultRouter(trailing_slash=False)
router.register("drivers", DriverViewSet, basename="driver")
router.register("driver/vehicles", DriverVehicleViewSet, basename="driver-vehicle")
router.register("driver/documents", DriverDocumentViewSet, basename="driver-document")

urlpatterns = [
    path("auth/driver/otp/verify", DriverOtpVerifyView.as_view(), name="driver-otp-verify"),
    path("driver/me", DriverMeView.as_view(), name="driver-me"),
    path("driver/online", DriverOnlineView.as_view(), name="driver-online"),
    path("driver/location", DriverLocationView.as_view(), name="driver-location"),
    path(
        "driver/vehicle-lookup/<str:plate>",
        DriverVehicleLookupView.as_view(),
        name="driver-vehicle-lookup",
    ),
    path("drivers/map", DriverMapView.as_view(), name="driver-map"),
    path("drivers/compliance", DriverComplianceView.as_view(), name="driver-compliance"),
    path("driver-documents/<int:pk>/review", DocumentReviewView.as_view(), name="document-review"),
    path("", include(router.urls)),
]
