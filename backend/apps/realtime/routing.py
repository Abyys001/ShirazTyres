from django.urls import path

from .consumers import CustomerConsumer, DriverConsumer, PanelConsumer

websocket_urlpatterns = [
    path("ws/panel", PanelConsumer.as_asgi()),
    path("ws/customer", CustomerConsumer.as_asgi()),
    path("ws/driver", DriverConsumer.as_asgi()),
]
