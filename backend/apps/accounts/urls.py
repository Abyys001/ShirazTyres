from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    AttachPhoneView,
    CustomerMeView,
    CustomerOtpVerifyView,
    CustomerRefreshView,
    CustomerViewSet,
    DriverRefreshView,
    GoogleSignInView,
    OtpRequestView,
    StaffLoginView,
    StaffMeView,
    StaffRefreshView,
)

router = DefaultRouter(trailing_slash=False)
router.register("customers", CustomerViewSet, basename="customer")

urlpatterns = [
    path("auth/otp/request", OtpRequestView.as_view(), name="otp-request"),
    path("auth/customer/otp/verify", CustomerOtpVerifyView.as_view(), name="customer-otp-verify"),
    path("auth/customer/google", GoogleSignInView.as_view(), name="customer-google"),
    path("auth/customer/attach-phone", AttachPhoneView.as_view(), name="customer-attach-phone"),
    path("auth/customer/refresh", CustomerRefreshView.as_view(), name="customer-refresh"),
    path("auth/staff/login", StaffLoginView.as_view(), name="staff-login"),
    path("auth/staff/refresh", StaffRefreshView.as_view(), name="staff-refresh"),
    path("auth/staff/me", StaffMeView.as_view(), name="staff-me"),
    path("auth/driver/refresh", DriverRefreshView.as_view(), name="driver-refresh"),
    path("customers/me", CustomerMeView.as_view(), name="customer-me"),
    path("", include(router.urls)),
]
