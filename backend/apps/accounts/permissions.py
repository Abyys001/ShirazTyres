from rest_framework.permissions import BasePermission

from .models import Customer, StaffUser


class IsStaff(BasePermission):
    message = "Staff authentication required."

    def has_permission(self, request, view):
        return isinstance(request.user, StaffUser) and request.user.is_active


class IsOwner(BasePermission):
    message = "Owner role required."

    def has_permission(self, request, view):
        return isinstance(request.user, StaffUser) and request.user.is_active and request.user.is_owner


class IsCustomer(BasePermission):
    message = "Customer authentication required."

    def has_permission(self, request, view):
        return isinstance(request.user, Customer) and request.user.is_active


class IsDriver(BasePermission):
    message = "Driver authentication required."

    def has_permission(self, request, view):
        from apps.drivers.models import Driver

        return isinstance(request.user, Driver) and request.user.is_active


class IsApprovedDriver(IsDriver):
    """Section 8: a driver receives no jobs until an administrator approves them."""

    message = "Your account is still awaiting approval."

    def has_permission(self, request, view):
        return super().has_permission(request, view) and request.user.is_approved
