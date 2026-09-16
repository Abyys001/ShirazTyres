from django.db.models import Count
from drf_spectacular.utils import extend_schema
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsStaff

from .filters import AuditEventFilter
from .health import snapshot
from .models import AuditEvent
from .serializers import AuditEventSerializer


@extend_schema(tags=["audit"])
class AuditEventListView(ListAPIView):
    """The operational log. Staff only — it carries phone numbers and job detail."""

    serializer_class = AuditEventSerializer
    permission_classes = [IsStaff]
    filterset_class = AuditEventFilter
    search_fields = ["message", "actor", "subject_id"]
    ordering_fields = ["created_at", "severity", "category"]
    queryset = AuditEvent.objects.all()


@extend_schema(tags=["audit"], responses={200: dict})
class AuditSummaryView(APIView):
    """Counts per category and severity, so the log page can show what is in it."""

    permission_classes = [IsStaff]

    def get(self, request):
        return Response(
            {
                "total": AuditEvent.objects.count(),
                "by_category": list(
                    AuditEvent.objects.values("category")
                    .annotate(count=Count("pk"))
                    .order_by("-count")
                ),
                "by_severity": list(
                    AuditEvent.objects.values("severity")
                    .annotate(count=Count("pk"))
                    .order_by("-count")
                ),
            }
        )


@extend_schema(tags=["audit"], responses={200: dict})
class HealthView(APIView):
    """
    Whether the system is actually working, rather than merely running.

    Staff-only: the reply names the broker, the database vendor and every
    configured provider, which is a map of the deployment and not something to
    hand to an unauthenticated caller. A load balancer wanting a liveness probe
    should hit a route that says nothing, not this one.
    """

    permission_classes = [IsStaff]

    def get(self, request):
        return Response(snapshot())
