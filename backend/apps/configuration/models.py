from django.db import models

from .catalogue import BY_KEY


class Setting(models.Model):
    """Overrides only. Anything absent falls back to the catalogue default."""

    key = models.CharField(max_length=64, unique=True)
    value = models.JSONField()
    updated_by = models.ForeignKey(
        "accounts.StaffUser", null=True, blank=True, on_delete=models.SET_NULL, related_name="setting_changes"
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("key",)

    def __str__(self):
        return f"{self.key} = {self.value!r}"

    @property
    def spec(self):
        return BY_KEY.get(self.key)
