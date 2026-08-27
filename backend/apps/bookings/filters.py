from django_filters import rest_framework as filters

from .models import Booking


class BookingFilter(filters.FilterSet):
    status = filters.MultipleChoiceFilter(choices=Booking.Status.choices)
    open_only = filters.BooleanFilter(method="filter_open_only")
    created_after = filters.DateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_before = filters.DateTimeFilter(field_name="created_at", lookup_expr="lte")

    class Meta:
        model = Booking
        fields = ["status", "issue_type", "source", "assigned_to"]

    def filter_open_only(self, queryset, name, value):
        if value is None:
            return queryset
        lookup = queryset.exclude if value else queryset.filter
        return lookup(status__in=Booking.TERMINAL_STATUSES)
