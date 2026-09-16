from django.contrib.auth import authenticate
from rest_framework import serializers

from .models import Customer, OtpCode, SocialIdentity, StaffUser
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


class GoogleSignInSerializer(serializers.Serializer):
    id_token = serializers.CharField()


class AttachPhoneSerializer(serializers.Serializer):
    phone = PhoneField(max_length=32)
    code = serializers.CharField(max_length=12)


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


class StaffCreateSerializer(serializers.ModelSerializer):
    """
    Create a panel account.

    The password is write-only and validated through Django's own validators, so
    the rules the project already configures apply here rather than a second set
    invented for the panel.
    """

    password = serializers.CharField(write_only=True, min_length=8, max_length=128)

    class Meta:
        model = StaffUser
        fields = ("id", "name", "email", "role", "is_active", "password")
        read_only_fields = ("id",)

    def validate_email(self, value):
        value = value.strip().lower()
        if StaffUser.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("Somebody already signs in with that address.")
        return value

    def validate_password(self, value):
        from django.contrib.auth.password_validation import validate_password

        validate_password(value)
        return value

    def create(self, validated_data):
        password = validated_data.pop("password")
        return StaffUser.objects.create_user(password=password, **validated_data)


class StaffUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = StaffUser
        fields = ("name", "email", "role", "is_active")

    def validate_email(self, value):
        value = value.strip().lower()
        clash = StaffUser.objects.filter(email__iexact=value)
        if self.instance:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError("Somebody already signs in with that address.")
        return value


class PasswordChangeSerializer(serializers.Serializer):
    """Changing your own password. The current one is required — a borrowed
    session must not be enough to lock the real owner out of the panel."""

    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8, max_length=128)

    def validate_new_password(self, value):
        from django.contrib.auth.password_validation import validate_password

        validate_password(value, user=self.context.get("user"))
        return value


class PasswordResetSerializer(serializers.Serializer):
    """An administrator setting somebody else's password, without knowing the old one."""

    new_password = serializers.CharField(write_only=True, min_length=8, max_length=128)

    def validate_new_password(self, value):
        from django.contrib.auth.password_validation import validate_password

        validate_password(value)
        return value


class SocialIdentitySerializer(serializers.ModelSerializer):
    class Meta:
        model = SocialIdentity
        fields = ("id", "provider", "email", "created_at", "last_used_at")
        read_only_fields = fields


class CustomerSerializer(serializers.ModelSerializer):
    phone = PhoneField(max_length=32, required=False, allow_null=True)
    vehicle_count = serializers.IntegerField(read_only=True, default=0)
    job_count = serializers.IntegerField(read_only=True, default=0)
    identities = SocialIdentitySerializer(many=True, read_only=True)

    class Meta:
        model = Customer
        fields = (
            "id", "name", "phone", "email", "photo_url", "is_phone_verified", "is_email_verified",
            "is_active", "notes", "vehicle_count", "job_count", "identities",
            "created_at", "updated_at", "last_login_at",
        )
        read_only_fields = (
            "id", "photo_url", "is_phone_verified", "is_email_verified",
            "created_at", "updated_at", "last_login_at",
        )

    def validate_phone(self, value):
        queryset = Customer.objects.filter(phone=value)
        if self.instance:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError("A customer with this phone number already exists.")
        return value


class CustomerSelfSerializer(CustomerSerializer):
    """Customers may edit their own name and email, never their notes or active flag."""

    class Meta(CustomerSerializer.Meta):
        read_only_fields = CustomerSerializer.Meta.read_only_fields + ("phone", "notes", "is_active")
