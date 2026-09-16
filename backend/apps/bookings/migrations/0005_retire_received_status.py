"""Migration 0003 replaced the ``received`` status with ``submitted`` and never moved
the rows that were already on it.

A job left on the old value is not merely mislabelled: it is outside
``Job.Status``, so it counts towards no dashboard bucket, has no entry in
``ALLOWED_TRANSITIONS``, and the panel prints the raw column value where a label
should be. The status events are rewritten too, because the customer's timeline
reads them back through ``Job.Status(...)``.
"""

from django.db import migrations

LEGACY = "received"
REPLACEMENT = "submitted"


def forwards(apps, schema_editor):
    Job = apps.get_model("bookings", "Job")
    JobStatusEvent = apps.get_model("bookings", "JobStatusEvent")

    Job.objects.filter(status=LEGACY).update(status=REPLACEMENT)
    JobStatusEvent.objects.filter(from_status=LEGACY).update(from_status=REPLACEMENT)
    JobStatusEvent.objects.filter(to_status=LEGACY).update(to_status=REPLACEMENT)


def backwards(apps, schema_editor):
    """Deliberately a no-op: ``submitted`` rows created after this ran are
    indistinguishable from the ones it converted, and sending them all back to a
    value the code no longer knows would be the more destructive answer."""


class Migration(migrations.Migration):
    dependencies = [("bookings", "0004_job_damaged_positions")]

    operations = [migrations.RunPython(forwards, backwards)]
