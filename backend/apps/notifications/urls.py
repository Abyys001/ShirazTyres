from django.urls import path

from .views import DeviceTokenView, NotificationListView

urlpatterns = [
    path("devices", DeviceTokenView.as_view(), name="device-token"),
    path("notifications", NotificationListView.as_view(), name="notification-list"),
]
