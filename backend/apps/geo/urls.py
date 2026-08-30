from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import CoverageCheckView, ServiceAreaViewSet

router = DefaultRouter(trailing_slash=False)
router.register("service-areas", ServiceAreaViewSet, basename="service-area")

urlpatterns = [
    path("public/coverage", CoverageCheckView.as_view(), name="coverage-check"),
    path("", include(router.urls)),
]
