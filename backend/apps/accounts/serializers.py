from django.contrib.auth import authenticate
from rest_framework import serializers

from .models import Driver, OtpCode, StaffUser
from .phone import normalise_phone


class PhoneField(serializers.CharField):
    def to_internal_value(self, data):
        return normalise_phone(super().to_internal_value(data))


class OtpRequestSerializer(serializers.Serializer):
    phone = PhoneField(max_length=32)
    purpose = serializers.ChoiceField(choices=OtpCode.Purpose.choices, default=OtpCode.Purpose.LOGIN)


class OtpVerifySerializer(serializers.Serializer):
    phone = PhoneField(max_length=32)
    code = serializers.CharField(max_length=12)
    name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)


class TokenPairSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class StaffLoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, style={"input_type": "password"})

    def validate(self, attrs):
        user = authenticate(username=attrs["email"], password=attrs["password"])
        if user is None or not user.is_active:
            raise serializers.ValidationError({"detail": "Incorrect email or password."})
        attrs["user"] = user
        return attrs


class StaffUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = StaffUser
        fields = ("id", "name", "email", "role", "is_active", "date_joined")
        read_only_fields = ("id", "date_joined")


class DriverSerializer(serializers.ModelSerializer):
    phone = PhoneField(max_length=32)
    vehicle_count = serializers.IntegerField(read_only=True, default=0)

    class Meta:
        model = Driver
        fields = (
            "id", "name", "phone", "email", "is_phone_verified", "is_active",
            "notes", "vehicle_count", "created_at", "updated_at", "last_login_at",
        )
        read_only_fields = ("id", "is_phone_verified", "created_at", "updated_at", "last_login_at")

    def validate_phone(self, value):
        qs = Driver.objects.filter(phone=value)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("A driver with this phone number already exists.")
        return value


class DriverSelfSerializer(DriverSerializer):
    """Drivers may edit their own name/email but never their notes or active flag."""

    class Meta(DriverSerializer.Meta):
        read_only_fields = DriverSerializer.Meta.read_only_fields + ("phone", "notes", "is_active")
