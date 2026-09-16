from rest_framework import serializers

from .models import AuditEvent


class AuditEventSerializer(serializers.ModelSerializer):
    category_display = serializers.CharField(source="get_category_display", read_only=True)

    class Meta:
        model = AuditEvent
        fields = (
            "id", "category", "category_display", "severity", "message",
            "actor", "subject_type", "subject_id", "payload", "created_at",
        )
        read_only_fields = fields
