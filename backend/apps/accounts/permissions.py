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


class IsAdminStaff(BasePermission):
    """
    Owner or shop owner.

    Sits between ``IsStaff`` and ``IsOwner``: the office can work the board all
    day, but changing settings, creating staff accounts or voiding money is a
    different kind of act and belongs to whoever answers for the business.
    """

    message = "Owner or shop owner role required."

    def has_permission(self, request, view):
        return isinstance(request.user, StaffUser) and request.user.is_active and request.user.is_admin


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
    """Section 8: a driver receives no jobs until an administrator approves them.

    The refusal is read out loud by the driver app, so it says which of the three
    standings it actually is. "Awaiting approval" told a suspended technician to
    keep waiting for something that had already happened and gone the other way.
    """

    message = "Your account is still awaiting approval."

    def has_permission(self, request, view):
        if not super().has_permission(request, view):
            return False
        if request.user.is_approved:
            return True

        from apps.drivers.models import Driver

        self.message = {
            Driver.Verification.SUSPENDED: (
                "Your account is suspended, so no jobs can be sent to you. "
                "The office can tell you what is needed to lift it."
            ),
            Driver.Verification.REJECTED: "Your account is not approved for dispatch.",
        }.get(
            request.user.verification_status,
            "Your account is still awaiting approval by the office. "
            "You will be able to accept shifts as soon as it is approved.",
        )
        return False
