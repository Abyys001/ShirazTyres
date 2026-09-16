from django.urls import path

from .views import AuditEventListView, AuditSummaryView, HealthView

urlpatterns = [
    path("logs", AuditEventListView.as_view(), name="audit-logs"),
    path("logs/summary", AuditSummaryView.as_view(), name="audit-summary"),
    path("health", HealthView.as_view(), name="health"),
]
