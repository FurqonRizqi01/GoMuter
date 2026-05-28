from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('pkl', '0015_alter_pklproduct_image'),
    ]

    operations = [
        migrations.AddField(
            model_name='pkl',
            name='ewallet_number',
            field=models.CharField(blank=True, max_length=50, null=True),
        ),
        migrations.AddField(
            model_name='pkl',
            name='ewallet_provider',
            field=models.CharField(blank=True, max_length=50, null=True),
        ),
        migrations.AddField(
            model_name='pkl',
            name='nomor_rekening',
            field=models.CharField(blank=True, max_length=80, null=True),
        ),
        migrations.AddField(
            model_name='pkl',
            name='whatsapp_number',
            field=models.CharField(blank=True, max_length=30, null=True),
        ),
    ]
