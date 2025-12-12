from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('pkl', '0010_pklproduct'),
    ]

    operations = [
        migrations.AddField(
            model_name='pkl',
            name='tentang',
            field=models.TextField(blank=True, null=True),
        ),
    ]
