from django.contrib.auth.models import AbstractUser
from django.db import models


# Model pengguna utama sistem yang mewarisi field bawaan Django (username, email, password, dll).
class User(AbstractUser):
    # Klasifikasi peran untuk membedakan hak akses admin, PKL, dan pembeli.
    ROLE_CHOICES = (
        ('ADMIN', 'Admin'),
        ('PKL', 'Pedagang Kaki Lima'),
        ('USER', 'Pembeli'),
    )
    # Field peran dipakai untuk kontrol otorisasi berbasis role di level API.
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='USER')
    # Token Firebase Cloud Messaging untuk push notification ke perangkat user.
    fcm_token = models.CharField(max_length=255, blank=True, null=True)

    def __str__(self):
        # Representasi ringkas user saat ditampilkan di admin/log.
        return f"{self.username} ({self.role})"
