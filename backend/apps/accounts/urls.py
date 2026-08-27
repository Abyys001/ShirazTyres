from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    DriverMeView,
    DriverRefreshView,
    DriverViewSet,
    OtpRequestView,
    OtpVerifyView,
    StaffLoginView,
    StaffMeView,
    StaffRefreshView,
)

router = DefaultRouter(trailing_slash=False)
router.register("drivers", DriverViewSet, basename="driver")

urlpatterns = [
    path("auth/otp/request", OtpRequestView.as_view(), name="otp-request"),
    path("auth/otp/verify", OtpVerifyView.as_view(), name="otp-verify"),
    path("auth/staff/login", StaffLoginView.as_view(), name="staff-login"),
    path("auth/staff/refresh", StaffRefreshView.as_view(), name="staff-refresh"),
    path("auth/staff/me", StaffMeView.as_view(), name="staff-me"),
    path("auth/driver/refresh", DriverRefreshView.as_view(), name="driver-refresh"),
    path("drivers/me", DriverMeView.as_view(), name="driver-me"),
    path("", include(router.urls)),
]
