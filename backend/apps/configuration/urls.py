from django.urls import path

from .views import PublicConfigurationView, SettingsView

urlpatterns = [
    path("settings", SettingsView.as_view(), name="settings"),
    path("public/config", PublicConfigurationView.as_view(), name="public-config"),
]
