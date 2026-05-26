from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('pkl', '0014_preorder_total_price'),
    ]

    operations = [
        migrations.AlterField(
            model_name='pklproduct',
            name='image',
            field=models.ImageField(
                blank=True,
                max_length=500,
                null=True,
                upload_to='pkl_products/',
            ),
        ),
    ]
