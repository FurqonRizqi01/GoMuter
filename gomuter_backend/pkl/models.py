from django.db import models
from django.conf import settings
from django.core.validators import MinValueValidator, MaxValueValidator

from django.utils import timezone


DEFAULT_RADIUS_METERS = 300
ALLOWED_RADIUS_METERS = (300, 500, 1000, 1500)


# Model profil usaha Pedagang Kaki Lima (PKL) yang terhubung langsung ke akun user.
class PKL(models.Model):
    # Satu akun user role PKL memiliki tepat satu profil PKL (one-to-one).
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='pkl_profile'
    )
    nama_usaha = models.CharField(max_length=100)
    jenis_dagangan = models.CharField(max_length=100)
    jam_operasional = models.CharField(max_length=100)
    status_aktif = models.BooleanField(default=False)
    alamat_domisili = models.CharField(max_length=200, blank=True, null=True)
    tentang = models.TextField(blank=True, null=True)
    nama_rekening = models.CharField(max_length=100, blank=True, null=True)
    qris_image_url = models.CharField(max_length=255, blank=True, null=True)
    qris_link = models.CharField(max_length=255, blank=True, null=True)
    profile_image_url = models.CharField(max_length=255, blank=True, null=True)

    # Status verifikasi dipakai admin untuk menentukan kelayakan tampil di sistem.
    STATUS_VERIFIKASI_CHOICES = (
        ('PENDING', 'Pending'),
        ('DITERIMA', 'Diterima'),
        ('DITOLAK', 'Ditolak'),
    )
    status_verifikasi = models.CharField(
        max_length=20,
        choices=STATUS_VERIFIKASI_CHOICES,
        default='PENDING'
    )
    catatan_verifikasi = models.TextField(blank=True, null=True)
    

    def __str__(self):
        return self.nama_usaha


class LokasiPKL(models.Model):
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='lokasi'
    )
    # Extra precision helps when device reports >6 decimal digits
    latitude = models.DecimalField(max_digits=12, decimal_places=9)
    longitude = models.DecimalField(max_digits=12, decimal_places=9)
    timestamp = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=50, default='AKTIF')

    def __str__(self):
        return f"{self.pkl.nama_usaha} @ {self.latitude}, {self.longitude}"


class Chat(models.Model):
    # Pihak pembeli yang membuka percakapan.
    pembeli = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='chats_as_pembeli',
    )
    # PKL tujuan percakapan.
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='chats',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        # Satu pembeli hanya memiliki satu room chat per PKL.
        unique_together = ('pembeli', 'pkl')
        ordering = ['-updated_at']

    def __str__(self):
        return f'Chat {self.pembeli} - {self.pkl.nama_usaha}'


class ChatMessage(models.Model):
    chat = models.ForeignKey(
        Chat,
        on_delete=models.CASCADE,
        related_name='messages',
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
    )
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f'{self.sender} : {self.content[:20]}'


class PreOrder(models.Model):
    # Status alur pesanan dari sisi proses bisnis transaksi.
    STATUS_CHOICES = [
        ('PENDING', 'Pending'),
        ('DITERIMA', 'Diterima'),
        ('DITOLAK', 'Ditolak'),
        ('SELESAI', 'Selesai'),
    ]

    # Status pembayaran DP untuk mengontrol validasi bukti bayar.
    DP_STATUS_CHOICES = [
        ('BELUM_BAYAR', 'Belum Bayar'),
        ('MENUNGGU_KONFIRMASI', 'Menunggu Konfirmasi'),
        ('TERKONFIRMASI', 'Terkonfirmasi'),
    ]

    # Relasi pembeli sebagai pembuat transaksi pre-order.
    pembeli = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='preorders',
    )
    # Relasi PKL sebagai penerima pesanan.
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='preorders',
    )
    deskripsi_pesanan = models.TextField()
    catatan = models.TextField(blank=True, null=True)
    pickup_address = models.CharField(max_length=255, blank=True, null=True)
    pickup_latitude = models.FloatField(blank=True, null=True)
    pickup_longitude = models.FloatField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING')
    total_price = models.IntegerField(default=0)
    dp_amount = models.IntegerField(default=0)
    dp_status = models.CharField(max_length=30, choices=DP_STATUS_CHOICES, default='BELUM_BAYAR')
    bukti_dp_url = models.CharField(max_length=255, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'PreOrder {self.pembeli} -> {self.pkl.nama_usaha} ({self.status})'


class PreOrderItem(models.Model):
    preorder = models.ForeignKey(
        PreOrder,
        on_delete=models.CASCADE,
        related_name='items',
    )
    product = models.ForeignKey(
        'PKLProduct',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='order_items',
    )
    product_name = models.CharField(max_length=120)
    product_price = models.PositiveIntegerField()
    quantity = models.PositiveIntegerField(default=1)

    @property
    def subtotal(self):
        return self.product_price * self.quantity

    class Meta:
        ordering = ['id']

    def __str__(self):
        return f'{self.product_name} x{self.quantity} (PreOrder #{self.preorder_id})'


class BuyerLocation(models.Model):
    buyer = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='buyer_location',
    )
    latitude = models.FloatField()
    longitude = models.FloatField()
    radius_m = models.PositiveIntegerField(default=DEFAULT_RADIUS_METERS)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.buyer.username} @ {self.latitude},{self.longitude}'


class FavoritePKL(models.Model):
    buyer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='favorite_pkls',
    )
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='favorited_by',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('buyer', 'pkl')

    def __str__(self):
        return f'{self.buyer.username} ❤️ {self.pkl.nama_usaha}'


class Notification(models.Model):
    # Tipe notifikasi inti: PKL terdekat dan PKL favorit aktif.
    TYPE_NEARBY = 'NEARBY_PKL'
    TYPE_FAVORITE_ACTIVE = 'FAVORITE_ACTIVE'
    TYPE_CHOICES = (
        (TYPE_NEARBY, 'PKL Terdekat'),
        (TYPE_FAVORITE_ACTIVE, 'PKL Favorit Aktif'),
    )

    # User pembeli penerima notifikasi.
    buyer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    # PKL sumber notifikasi; boleh kosong untuk notifikasi umum.
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='notifications',
    )
    notif_type = models.CharField(max_length=32, choices=TYPE_CHOICES)
    message = models.CharField(max_length=255)
    radius_m = models.PositiveIntegerField(default=DEFAULT_RADIUS_METERS)
    distance_m = models.FloatField(null=True, blank=True)
    # Penanda apakah notifikasi sudah dibaca di aplikasi.
    is_read = models.BooleanField(default=False)
    # Metadata fleksibel (JSON) untuk payload tambahan notifikasi.
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.notif_type} -> {self.buyer.username}'


class PKLDailyStats(models.Model):
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='daily_stats',
    )
    date = models.DateField()
    live_views = models.PositiveIntegerField(default=0)
    search_hits = models.PositiveIntegerField(default=0)
    auto_updates = models.PositiveIntegerField(default=0)

    class Meta:
        unique_together = ('pkl', 'date')
        ordering = ['-date']

    def __str__(self):
        return f'Stats {self.pkl.nama_usaha} - {self.date.isoformat()}'

    @classmethod
    def today_for(cls, pkl: "PKL") -> "PKLDailyStats":
        today = timezone.localdate()
        stats, _ = cls.objects.get_or_create(pkl=pkl, date=today)
        return stats


class PKLProduct(models.Model):
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='products',
    )
    name = models.CharField(max_length=120)
    price = models.PositiveIntegerField()
    description = models.TextField(blank=True)
    image = models.ImageField(
        upload_to='pkl_products/',
        blank=True,
        null=True,
        max_length=500,
    )
    is_featured = models.BooleanField(default=False)
    is_available = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-is_featured', 'name']

    def __str__(self):
        return f'{self.name} ({self.pkl.nama_usaha})'


class PKLRating(models.Model):
    buyer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='pkl_ratings',
    )
    pkl = models.ForeignKey(
        PKL,
        on_delete=models.CASCADE,
        related_name='ratings',
    )
    score = models.DecimalField(
        max_digits=2,
        decimal_places=1,
        validators=[MinValueValidator(0), MaxValueValidator(5)],
    )
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('buyer', 'pkl')
        ordering = ['-updated_at']

    def __str__(self):
        return f'{self.buyer.username} rated {self.pkl.nama_usaha}: {self.score}'
