from django_filters import rest_framework as filters

from .models import Job


class JobFilter(filters.FilterSet):
    status = filters.MultipleChoiceFilter(choices=Job.Status.choices)
    open_only = filters.BooleanFilter(method="filter_open_only")
    needs_attention = filters.BooleanFilter(method="filter_needs_attention")
    created_after = filters.DateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_before = filters.DateTimeFilter(field_name="created_at", lookup_expr="lte")

    class Meta:
        model = Job
        fields = ["status", "issue_type", "source", "driver", "assigned_staff", "service_area"]

    def filter_open_only(self, queryset, name, value):
        if value is None:
            return queryset
        lookup = queryset.exclude if value else queryset.filter
        return lookup(status__in=Job.TERMINAL_STATUSES)

    def filter_needs_attention(self, queryset, name, value):
        """The unclaimed queue — section 5 says these require staff intervention."""
        if not value:
            return queryset
        return queryset.filter(status=Job.Status.UNCLAIMED)
