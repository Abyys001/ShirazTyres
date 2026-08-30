"""Booking becomes Job. The app label stays ``bookings`` so the migration history holds."""

from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("bookings", "0001_initial"),
        ("accounts", "0002_rename_driver_to_customer"),
    ]

    operations = [
        migrations.RemoveIndex(model_name="booking", name="bookings_bo_status_eb4fb1_idx"),
        migrations.RenameModel(old_name="Booking", new_name="Job"),
        migrations.RenameModel(old_name="BookingStatusEvent", new_name="JobStatusEvent"),
        migrations.RenameField(model_name="job", old_name="driver", new_name="customer"),
        migrations.RenameField(model_name="job", old_name="assigned_to", new_name="assigned_staff"),
        migrations.RenameField(model_name="jobstatusevent", old_name="booking", new_name="job"),
        migrations.RenameField(model_name="jobstatusevent", old_name="changed_by", new_name="changed_by_staff"),
    ]
