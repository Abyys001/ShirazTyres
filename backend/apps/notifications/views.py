from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Customer, StaffUser
from apps.accounts.permissions import IsStaff
from apps.drivers.models import Driver

from .models import DeviceToken, Notification
from .serializers import DeviceTokenSerializer, NotificationSerializer


@extend_schema(tags=["notifications"], request=DeviceTokenSerializer, responses={201: DeviceTokenSerializer})
class DeviceTokenView(APIView):
    """Registered by both Flutter apps and by the panel for web push."""

    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        owner = {"customer": None, "driver": None, "staff": None}
        if isinstance(request.user, Customer):
            owner["customer"] = request.user
        elif isinstance(request.user, Driver):
            owner["driver"] = request.user
        elif isinstance(request.user, StaffUser):
            owner["staff"] = request.user

        device, created = DeviceToken.objects.update_or_create(
            token=serializer.validated_data["token"],
            defaults={"platform": serializer.validated_data["platform"], "is_active": True, **owner},
        )
        return Response(
            DeviceTokenSerializer(device).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def delete(self, request):
        token = request.data.get("token") or request.query_params.get("token")
        DeviceToken.objects.filter(token=token).update(is_active=False)
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(tags=["notifications"], responses={200: NotificationSerializer})
class NotificationListView(ListAPIView):
    """Lets the owner answer 'did the alert actually go out?' without a shell."""

    queryset = Notification.objects.select_related("job")
    serializer_class = NotificationSerializer
    permission_classes = [IsStaff]
    filterset_fields = ["channel", "status", "job", "event"]
    ordering_fields = ["created_at"]
