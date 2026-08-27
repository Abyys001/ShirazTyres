from rest_framework.permissions import BasePermission

from .models import Driver, StaffUser


class IsStaff(BasePermission):
    message = "Staff authentication required."

    def has_permission(self, request, view):
        return isinstance(request.user, StaffUser) and request.user.is_active


class IsOwner(BasePermission):
    message = "Owner role required."

    def has_permission(self, request, view):
        return isinstance(request.user, StaffUser) and request.user.is_owner


class IsDriver(BasePermission):
    message = "Driver authentication required."

    def has_permission(self, request, view):
        return isinstance(request.user, Driver) and request.user.is_active
