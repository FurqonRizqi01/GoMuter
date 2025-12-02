from datetime import timedelta
from typing import Optional, Tuple

from django.utils import timezone

from .models import (
    PKL,
    LokasiPKL,
    BuyerLocation,
    FavoritePKL,
    Notification,
    DEFAULT_RADIUS_METERS,
)
from .utils import haversine_distance_km

NOTIFICATION_COOLDOWN_MINUTES = 30


def _latest_coordinates(pkl: PKL) -> Optional[Tuple[float, float]]:
    lokasi = pkl.lokasi.order_by('-timestamp').first()
    if not lokasi:
        return None
    return float(lokasi.latitude), float(lokasi.longitude)


def _should_skip_notification(buyer, pkl, notif_type: str) -> bool:
    cutoff = timezone.now() - timedelta(minutes=NOTIFICATION_COOLDOWN_MINUTES)
    queryset = Notification.objects.filter(
        buyer=buyer,
        notif_type=notif_type,
        created_at__gte=cutoff,
    )
    if pkl:
        queryset = queryset.filter(pkl=pkl)
    return queryset.exists()


def _create_notification(*, buyer, pkl, notif_type: str, message: str, radius_m: int, distance_m: Optional[float], metadata: Optional[dict] = None):
    if _should_skip_notification(buyer, pkl, notif_type):
        return None

    return Notification.objects.create(
        buyer=buyer,
        pkl=pkl,
        notif_type=notif_type,
        message=message,
        radius_m=radius_m,
        distance_m=distance_m,
        metadata=metadata or {},
    )


def notify_nearby_pkls(location: BuyerLocation) -> list[Notification]:
    """Check all active PKL and notify buyer when within radius."""
    if not location:
        return []

    radius_m = location.radius_m or DEFAULT_RADIUS_METERS
    radius_km = radius_m / 1000.0
    created_notifications: list[Notification] = []

    pkls = PKL.objects.filter(status_aktif=True, status_verifikasi='DITERIMA').prefetch_related('lokasi')
    for pkl in pkls:
        coords = _latest_coordinates(pkl)
        if not coords:
            continue
        latest_lat, latest_lng = coords
        distance_km = haversine_distance_km(location.latitude, location.longitude, latest_lat, latest_lng)
        if distance_km <= radius_km:
            distance_m = distance_km * 1000
            notif = _create_notification(
                buyer=location.buyer,
                pkl=pkl,
                notif_type=Notification.TYPE_NEARBY,
                message=f"PKL {pkl.nama_usaha} berada sekitar {distance_m:.0f} m dari lokasimu.",
                radius_m=radius_m,
                distance_m=distance_m,
                metadata={'distance_m': distance_m, 'pkl_id': pkl.id},
            )
            if notif:
                created_notifications.append(notif)
    return created_notifications


def notify_favorite_pkl_active(pkl: PKL) -> list[Notification]:
    favorites = FavoritePKL.objects.filter(pkl=pkl).select_related('buyer', 'buyer__buyer_location')
    coords = _latest_coordinates(pkl)
    if not coords:
        return []

    latest_lat, latest_lng = coords
    created: list[Notification] = []

    for favorite in favorites:
        location = getattr(favorite.buyer, 'buyer_location', None)
        if not location:
            continue
        radius_m = location.radius_m or DEFAULT_RADIUS_METERS
        radius_km = radius_m / 1000.0
        distance_km = haversine_distance_km(location.latitude, location.longitude, latest_lat, latest_lng)
        if distance_km <= radius_km:
            distance_m = distance_km * 1000
            notif = _create_notification(
                buyer=favorite.buyer,
                pkl=pkl,
                notif_type=Notification.TYPE_FAVORITE_ACTIVE,
                message=f"PKL favoritmu {pkl.nama_usaha} baru saja aktif di dekatmu.",
                radius_m=radius_m,
                distance_m=distance_m,
                metadata={'distance_m': distance_m, 'pkl_id': pkl.id},
            )
            if notif:
                created.append(notif)
    return created
