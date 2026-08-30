from drf_spectacular.utils import extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsOwner, IsStaff

from .public import public_configuration
from .serializers import SettingsDocumentSerializer, SettingsUpdateSerializer
from .services import set_many


@extend_schema(tags=["settings"], responses={200: SettingsDocumentSerializer})
class SettingsView(APIView):
    """Read is staff-wide; writing the business's behaviour is the owner's alone."""

    permission_classes = [IsStaff]

    def get(self, request):
        return Response(SettingsDocumentSerializer.build())

    @extend_schema(request=SettingsUpdateSerializer, responses={200: SettingsDocumentSerializer})
    def patch(self, request):
        if not IsOwner().has_permission(request, self):
            self.permission_denied(request, message=IsOwner.message)
        serializer = SettingsUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        set_many(serializer.validated_data["values"], updated_by=request.user)
        return Response(SettingsDocumentSerializer.build())


@extend_schema(tags=["settings"], responses={200: dict})
class PublicConfigurationView(APIView):
    """What the customer surfaces need before anyone has signed in — issue types,
    business hours, the call-out fee. Deliberately a whitelist, not the whole table."""

    authentication_classes: list = []
    permission_classes = [AllowAny]

    def get(self, request):
        return Response(public_configuration())
