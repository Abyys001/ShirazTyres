from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import MyVehicleViewSet, VehicleLookupView, VehicleViewSet

router = DefaultRouter(trailing_slash=False)
router.register("vehicles", VehicleViewSet, basename="vehicle")
router.register("my-vehicles", MyVehicleViewSet, basename="my-vehicle")

urlpatterns = [
    path("public/vehicle-lookup/<str:plate>", VehicleLookupView.as_view(), name="vehicle-lookup"),
    path("", include(router.urls)),
]
