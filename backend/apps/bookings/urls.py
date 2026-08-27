from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    BookingViewSet,
    DriverBookingDetailView,
    DriverBookingCreateView,
    DriverBookingListView,
    PublicBookingCreateView,
)

router = DefaultRouter(trailing_slash=False)
router.register("bookings", BookingViewSet, basename="booking")

urlpatterns = [
    path("public/bookings", PublicBookingCreateView.as_view(), name="public-booking-create"),
    path("my/bookings", DriverBookingListView.as_view(), name="my-bookings"),
    path("my/bookings/create", DriverBookingCreateView.as_view(), name="my-booking-create"),
    path("my/bookings/<int:pk>", DriverBookingDetailView.as_view(), name="my-booking-detail"),
    path("", include(router.urls)),
]
