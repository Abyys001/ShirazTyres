from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("vehicles", "0001_initial"),
        ("accounts", "0002_rename_driver_to_customer"),
    ]

    operations = [
        migrations.RemoveConstraint(model_name="drivervehicle", name="unique_driver_vehicle"),
        migrations.RenameModel(old_name="DriverVehicle", new_name="CustomerVehicle"),
        migrations.RenameField(model_name="customervehicle", old_name="driver", new_name="customer"),
        migrations.RenameField(model_name="vehicle", old_name="drivers", new_name="customers"),
    ]
