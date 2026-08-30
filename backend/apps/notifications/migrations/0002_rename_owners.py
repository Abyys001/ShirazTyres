from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("notifications", "0001_initial"),
        ("accounts", "0002_rename_driver_to_customer"),
        ("bookings", "0002_rename_booking_to_job"),
    ]

    operations = [
        migrations.RemoveConstraint(model_name="devicetoken", name="device_token_has_owner"),
        # The old `driver` on a device was the motorist — that is the customer now. The
        # technician's device gets its own column in the migration that follows.
        migrations.RenameField(model_name="devicetoken", old_name="driver", new_name="customer"),
        migrations.RenameField(model_name="notification", old_name="booking", new_name="job"),
    ]
