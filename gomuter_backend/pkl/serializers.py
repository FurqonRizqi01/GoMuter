from django.db import models
from rest_framework import serializers
from .models import (
    PKL,
    LokasiPKL,
    Chat,
    ChatMessage,
    PreOrder,
    BuyerLocation,
    FavoritePKL,
    Notification,
    PKLDailyStats,
    PKLRating,
    ALLOWED_RADIUS_METERS,
)


class PKLSerializer(serializers.ModelSerializer):
    class Meta:
        model = PKL
        fields = [
            'id',
            'nama_usaha',
            'jenis_dagangan',
            'jam_operasional',
            'status_aktif',
            'alamat_domisili',
            'nama_rekening',
            'qris_image_url',
            'qris_link',
            'status_verifikasi',
            'catatan_verifikasi',
        ]


class LokasiPKLSerializer(serializers.ModelSerializer):
    class Meta:
        model = LokasiPKL
        fields = ['id', 'pkl', 'latitude', 'longitude', 'timestamp', 'status']
        read_only_fields = ['pkl', 'timestamp', 'status']


# ➜ Serializer khusus untuk pembeli / admin (list di peta + lokasi terakhir)
class PKLListSerializer(serializers.ModelSerializer):
    latest_latitude = serializers.SerializerMethodField()
    latest_longitude = serializers.SerializerMethodField()
    latest_timestamp = serializers.SerializerMethodField()
    average_rating = serializers.SerializerMethodField()
    rating_count = serializers.SerializerMethodField()

    class Meta:
        model = PKL
        fields = [
            'id',
            'nama_usaha',
            'jenis_dagangan',
            'jam_operasional',
            'status_aktif',
            'alamat_domisili',
            'nama_rekening',
            'qris_image_url',
            'qris_link',
            'status_verifikasi',
            'catatan_verifikasi',
            'latest_latitude',
            'latest_longitude',
            'latest_timestamp',
            'average_rating',
            'rating_count',
        ]

    def get_latest_latitude(self, obj):
        lokasi = obj.lokasi.order_by('-timestamp').first()
        return lokasi.latitude if lokasi else None

    def get_latest_longitude(self, obj):
        lokasi = obj.lokasi.order_by('-timestamp').first()
        return lokasi.longitude if lokasi else None

    def get_latest_timestamp(self, obj):
        lokasi = obj.lokasi.order_by('-timestamp').first()
        return lokasi.timestamp if lokasi else None

    def _resolve_annotation(self, obj, attr):
        if hasattr(obj, attr):
            return getattr(obj, attr)
        return None

    def get_average_rating(self, obj):
        value = self._resolve_annotation(obj, 'average_rating')
        if value is not None:
            return round(float(value), 1)
        agg = obj.ratings.aggregate(avg=models.Avg('score'))
        if agg['avg'] is None:
            return None
        return round(float(agg['avg']), 1)

    def get_rating_count(self, obj):
        value = self._resolve_annotation(obj, 'rating_count')
        if value is not None:
            return int(value)
        return obj.ratings.count()


class PKLVerifySerializer(serializers.ModelSerializer):
    class Meta:
        model = PKL
        fields = [
            'id',
            'nama_usaha',
            'status_verifikasi',
            'catatan_verifikasi',
            'status_aktif',
            'nama_rekening',
            'qris_image_url',
            'qris_link',
        ]


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_username = serializers.CharField(source='sender.username', read_only=True)

    class Meta:
        model = ChatMessage
        fields = ['id', 'sender', 'sender_username', 'content', 'created_at']
        read_only_fields = ['id', 'sender', 'created_at']


class ChatSerializer(serializers.ModelSerializer):
    pkl_nama_usaha = serializers.CharField(source='pkl.nama_usaha', read_only=True)
    pembeli_username = serializers.CharField(source='pembeli.username', read_only=True)

    class Meta:
        model = Chat
        fields = [
            'id',
            'pembeli',
            'pkl',
            'pkl_nama_usaha',
            'pembeli_username',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'pembeli']


class PreOrderSerializer(serializers.ModelSerializer):
    pkl_nama_usaha = serializers.CharField(source='pkl.nama_usaha', read_only=True)
    pembeli_username = serializers.CharField(source='pembeli.username', read_only=True)

    class Meta:
        model = PreOrder
        fields = [
            'id',
            'pembeli',
            'pembeli_username',
            'pkl',
            'pkl_nama_usaha',
            'deskripsi_pesanan',
            'catatan',
            'pickup_address',
            'pickup_latitude',
            'pickup_longitude',
            'status',
            'dp_amount',
            'dp_status',
            'bukti_dp_url',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'pembeli', 'pkl', 'status', 'created_at', 'updated_at']


class BuyerLocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = BuyerLocation
        fields = ['latitude', 'longitude', 'radius_m', 'updated_at']
        read_only_fields = ['updated_at']


class BuyerLocationUpdateSerializer(serializers.Serializer):
    latitude = serializers.FloatField()
    longitude = serializers.FloatField()
    radius_m = serializers.IntegerField(required=False)

    def validate_radius_m(self, value):
        if value is None:
            return value
        if value not in ALLOWED_RADIUS_METERS:
            raise serializers.ValidationError(
                f'Radius harus salah satu dari {", ".join(map(str, ALLOWED_RADIUS_METERS))} meter.'
            )
        return value


class FavoritePKLSerializer(serializers.ModelSerializer):
    pkl_nama_usaha = serializers.CharField(source='pkl.nama_usaha', read_only=True)
    jenis_dagangan = serializers.CharField(source='pkl.jenis_dagangan', read_only=True)

    class Meta:
        model = FavoritePKL
        fields = ['id', 'pkl', 'pkl_nama_usaha', 'jenis_dagangan', 'created_at']
        read_only_fields = ['id', 'created_at']


class NotificationSerializer(serializers.ModelSerializer):
    pkl_nama_usaha = serializers.CharField(source='pkl.nama_usaha', read_only=True)

    class Meta:
        model = Notification
        fields = [
            'id',
            'notif_type',
            'message',
            'pkl',
            'pkl_nama_usaha',
            'radius_m',
            'distance_m',
            'metadata',
            'is_read',
            'created_at',
        ]
        read_only_fields = fields


class PKLDailyStatsSerializer(serializers.ModelSerializer):
    class Meta:
        model = PKLDailyStats
        fields = ['date', 'live_views', 'search_hits', 'auto_updates']
        read_only_fields = fields


class PKLRatingSerializer(serializers.ModelSerializer):
    buyer_username = serializers.CharField(source='buyer.username', read_only=True)

    class Meta:
        model = PKLRating
        fields = [
            'id',
            'pkl',
            'buyer',
            'buyer_username',
            'score',
            'comment',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'buyer', 'pkl', 'buyer_username', 'created_at', 'updated_at']


class PKLRatingSummarySerializer(serializers.Serializer):
    average_rating = serializers.FloatField(allow_null=True)
    rating_count = serializers.IntegerField()
    user_rating = PKLRatingSerializer(allow_null=True)
