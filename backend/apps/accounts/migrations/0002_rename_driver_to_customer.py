"""Specification section 2: 'driver' now means the employee technician.

The motorist this table used to hold is a Customer. Renaming rather than recreating keeps
every existing row and every foreign key pointing at it.
"""

from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0001_initial"),
        ("vehicles", "0001_initial"),
        ("bookings", "0001_initial"),
        ("notifications", "0001_initial"),
    ]

    operations = [
        migrations.RenameModel(old_name="Driver", new_name="Customer"),
    ]
