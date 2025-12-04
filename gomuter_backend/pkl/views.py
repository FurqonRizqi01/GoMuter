import uuid
from decimal import Decimal
from difflib import SequenceMatcher

from datetime import timedelta

from django.db.models import Q, F, Avg, Count, Sum, Max
from django.core.files.storage import default_storage
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.parsers import MultiPartParser, FormParser

from .models import (
    PKL,
    LokasiPKL,
    PreOrder,
    BuyerLocation,
    FavoritePKL,
    Notification,
    PKLDailyStats,
    PKLRating,
    PKLProduct,
    DEFAULT_RADIUS_METERS,
)
from .serializers import (
    PKLSerializer,
    LokasiPKLSerializer,
    PKLListSerializer,
    PKLDetailSerializer,
    PKLVerifySerializer,
    PreOrderSerializer,
    BuyerLocationSerializer,
    BuyerLocationUpdateSerializer,
    FavoritePKLSerializer,
    NotificationSerializer,
    PKLDailyStatsSerializer,
    PKLRatingSerializer,
    PKLRatingSummarySerializer,
    PKLProductSerializer,
    PKLProductWriteSerializer,
)
from .services import notify_nearby_pkls, notify_favorite_pkl_active


class IsPKL(permissions.BasePermission):
    """Hanya user dengan role PKL yang boleh akses."""
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role == 'PKL')


class IsPembeli(permissions.BasePermission):
    """Hanya user pembeli (role USER)."""
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role == 'USER')


def _increment_daily_stat(pkl: PKL, field: str) -> None:
    today = timezone.localdate()
    stats, _created = PKLDailyStats.objects.get_or_create(pkl=pkl, date=today)
    PKLDailyStats.objects.filter(pk=stats.pk).update(**{field: F(field) + 1})


def _get_today_stats(pkl: PKL) -> PKLDailyStats:
    today = timezone.localdate()
    stats, _ = PKLDailyStats.objects.get_or_create(pkl=pkl, date=today)
    return stats


class PKLProfileView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPKL]

    def get(self, request):
        try:
            pkl = PKL.objects.get(user=request.user)
        except PKL.DoesNotExist:
            return Response(
                {"detail": "Profil PKL belum dibuat."},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = PKLSerializer(pkl)
        return Response(serializer.data)

    def post(self, request):
        if PKL.objects.filter(user=request.user).exists():
            return Response(
                {"detail": "Profil PKL sudah ada."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = PKLSerializer(data=request.data)
        if serializer.is_valid():
            pkl = serializer.save(
                user=request.user,
                status_verifikasi='PENDING',
                status_aktif=False,
            )
            return Response(PKLSerializer(pkl).data, status=status.HTTP_201_CREATED)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    def put(self, request):
        try:
            pkl = PKL.objects.get(user=request.user)
        except PKL.DoesNotExist:
            return Response(
                {"detail": "Profil PKL belum dibuat."},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = PKLSerializer(pkl, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class PKLUpdateLocationView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPKL]

    def post(self, request):
        try:
            pkl = PKL.objects.get(user=request.user)
        except PKL.DoesNotExist:
            return Response(
                {"detail": "Profil PKL belum dibuat."},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = LokasiPKLSerializer(data=request.data)
        if serializer.is_valid():
            was_active = pkl.status_aktif
            lokasi = serializer.save(pkl=pkl, status='AKTIF')
            # tandai PKL aktif setelah update lokasi
            pkl.status_aktif = True
            pkl.save(update_fields=['status_aktif'])
            if not was_active and pkl.status_aktif:
                notify_favorite_pkl_active(pkl)
            _increment_daily_stat(pkl, 'auto_updates')
            return Response(LokasiPKLSerializer(lokasi).data, status=status.HTTP_201_CREATED)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class PKLTodayStatsView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPKL]

    def get(self, request):
        try:
            pkl = PKL.objects.get(user=request.user)
        except PKL.DoesNotExist:
            return Response(
                {"detail": "Profil PKL belum dibuat."},
                status=status.HTTP_404_NOT_FOUND,
            )

        stats = _get_today_stats(pkl)
        serializer = PKLDailyStatsSerializer(stats)
        return Response(serializer.data)


class BuyerLocationView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPembeli]

    def get(self, request):
        try:
            location = BuyerLocation.objects.get(buyer=request.user)
        except BuyerLocation.DoesNotExist:
            return Response(
                {"detail": "Lokasi belum tersimpan."},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(BuyerLocationSerializer(location).data, status=status.HTTP_200_OK)

    def post(self, request):
        serializer = BuyerLocationUpdateSerializer(data=request.data)
        if serializer.is_valid():
            latitude = serializer.validated_data['latitude']
            longitude = serializer.validated_data['longitude']
            radius_m = serializer.validated_data.get('radius_m')

            if radius_m is None:
                try:
                    radius_m = request.user.buyer_location.radius_m
                except BuyerLocation.DoesNotExist:  # type: ignore[attr-defined]
                    radius_m = DEFAULT_RADIUS_METERS

            location, created = BuyerLocation.objects.update_or_create(
                buyer=request.user,
                defaults={
                    'latitude': latitude,
                    'longitude': longitude,
                    'radius_m': radius_m,
                },
            )

            notify_nearby_pkls(location)
            return Response(
                BuyerLocationSerializer(location).data,
                status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
            )

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

# === VIEW UNTUK PEMBELI ===

class ActivePKLListView(generics.ListAPIView):
    """Daftar PKL aktif dengan dukungan filter query param + fuzzy search."""

    serializer_class = PKLListSerializer
    permission_classes = [permissions.AllowAny]
    fuzzy_limit = 200
    fuzzy_threshold = 0.45

    def get_queryset(self):
        return PKL.objects.filter(
            status_aktif=True,
            status_verifikasi='DITERIMA',
        ).annotate(
            average_rating=Avg('ratings__score'),
            rating_count=Count('ratings', distinct=True),
        )

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()
        jenis = request.query_params.get('jenis')
        search_query = request.query_params.get('q')

        if jenis:
            queryset = queryset.filter(jenis_dagangan__icontains=jenis)

        queryset = self.filter_queryset(queryset)

        if search_query:
            results = self._apply_fuzzy_search(queryset, search_query)
        else:
            results = list(queryset)

        serializer = self.get_serializer(results, many=True)

        if jenis or search_query:
            self._record_search_hits(results)

        return Response(serializer.data)

    def _apply_fuzzy_search(self, queryset, raw_query):
        normalized_query = self._normalize_term(raw_query)
        if not normalized_query:
            return list(queryset[:50])

        candidates = list(queryset[: self.fuzzy_limit])
        if not candidates:
            return candidates

        scored = []
        for pkl in candidates:
            best_score = self._best_similarity(normalized_query, pkl)
            scored.append((best_score, pkl))

        scored.sort(key=lambda item: item[0], reverse=True)
        filtered = [pkl for score, pkl in scored if score >= self.fuzzy_threshold]

        if not filtered:
            filtered = [pkl for _, pkl in scored[:20]]

        return filtered

    def _best_similarity(self, normalized_query, pkl):
        fields = [
            self._normalize_term(getattr(pkl, 'nama_usaha', '') or ''),
            self._normalize_term(getattr(pkl, 'jenis_dagangan', '') or ''),
        ]
        scores = [self._similarity(normalized_query, field) for field in fields if field]
        if not scores:
            return 0.0
        exact_hit = any(normalized_query in field for field in fields)
        return 1.0 if exact_hit else max(scores)

    def _record_search_hits(self, pkls):
        limited = pkls[:20] if isinstance(pkls, list) else list(pkls[:20])
        for pkl in limited:
            _increment_daily_stat(pkl, 'search_hits')

    @staticmethod
    def _normalize_term(value):
        return ''.join(value.lower().split()) if value else ''

    @staticmethod
    def _similarity(source, target):
        if not source or not target:
            return 0.0
        return SequenceMatcher(None, source, target).ratio()


class FavoritePKLListCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPembeli]

    def get(self, request):
        favorites = FavoritePKL.objects.filter(buyer=request.user).select_related('pkl')
        serializer = FavoritePKLSerializer(favorites, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request):
        pkl_id = request.data.get('pkl_id')
        if not pkl_id:
            return Response(
                {"detail": "pkl_id wajib diisi."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            pkl = PKL.objects.get(id=pkl_id, status_verifikasi='DITERIMA')
        except PKL.DoesNotExist:
            return Response(
                {"detail": "PKL tidak ditemukan."},
                status=status.HTTP_404_NOT_FOUND,
            )

        favorite, created = FavoritePKL.objects.get_or_create(buyer=request.user, pkl=pkl)
        serializer = FavoritePKLSerializer(favorite)
        return Response(
            serializer.data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class FavoritePKLDeleteView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPembeli]

    def delete(self, request, pkl_id):
        deleted, _ = FavoritePKL.objects.filter(buyer=request.user, pkl_id=pkl_id).delete()
        if not deleted:
            return Response(
                {"detail": "PKL favorit tidak ditemukan."},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(status=status.HTTP_204_NO_CONTENT)


class PKLDetailView(generics.RetrieveAPIView):
    """
    GET /api/pkl/<id>/
    Detail 1 PKL + lokasi terakhir.
    """
    queryset = PKL.objects.annotate(
        average_rating=Avg('ratings__score'),
        rating_count=Count('ratings', distinct=True),
    ).prefetch_related('products')
    serializer_class = PKLDetailSerializer
    permission_classes = [permissions.AllowAny]

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        _increment_daily_stat(instance, 'live_views')
        serializer = self.get_serializer(instance)
        return Response(serializer.data)


class PKLRatingView(APIView):
    permission_classes = [permissions.AllowAny]

    def get_permissions(self):
        if self.request.method in ('POST', 'DELETE'):
            return [permissions.IsAuthenticated(), IsPembeli()]
        return [permission() for permission in self.permission_classes]

    def _get_pkl(self, pkl_id):
        return get_object_or_404(PKL, pk=pkl_id, status_verifikasi='DITERIMA')

    def get(self, request, pkl_id):
        pkl = self._get_pkl(pkl_id)
        summary = pkl.ratings.aggregate(
            avg=Avg('score'),
            count=Count('id'),
        )
        user_rating = None
        if request.user.is_authenticated:
            user_rating = PKLRating.objects.filter(
                pkl=pkl,
                buyer=request.user,
            ).first()

        data = {
            'average_rating': None if summary['avg'] is None else round(float(summary['avg']), 1),
            'rating_count': summary['count'] or 0,
            'user_rating': user_rating,
        }
        serializer = PKLRatingSummarySerializer(data)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request, pkl_id):
        pkl = self._get_pkl(pkl_id)
        score = request.data.get('score')
        comment = request.data.get('comment', '') or ''

        try:
            score_value = Decimal(str(score))
        except Exception:
            return Response(
                {'detail': 'score harus berupa angka.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if score_value < 0 or score_value > 5:
            return Response(
                {'detail': 'score harus di antara 0 - 5.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        rating, created = PKLRating.objects.update_or_create(
            buyer=request.user,
            pkl=pkl,
            defaults={'score': score_value, 'comment': comment.strip()},
        )

        serializer = PKLRatingSerializer(rating)
        return Response(
            serializer.data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def delete(self, request, pkl_id):
        pkl = self._get_pkl(pkl_id)
        deleted, _ = PKLRating.objects.filter(pkl=pkl, buyer=request.user).delete()
        if not deleted:
            return Response(
                {'detail': 'Rating belum dibuat.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(status=status.HTTP_204_NO_CONTENT)


class PKLProductListCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPKL]
    parser_classes = [MultiPartParser, FormParser]

    def _get_pkl(self, request):
        return get_object_or_404(PKL, user=request.user)

    def get(self, request):
        pkl = self._get_pkl(request)
        products = pkl.products.order_by('-updated_at')
        serializer = PKLProductSerializer(
            products,
            many=True,
            context={'request': request},
        )
        return Response(serializer.data)

    def post(self, request):
        pkl = self._get_pkl(request)
        serializer = PKLProductWriteSerializer(data=request.data)
        if serializer.is_valid():
            product = serializer.save(pkl=pkl)
            read_serializer = PKLProductSerializer(
                product,
                context={'request': request},
            )
            return Response(read_serializer.data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class PKLProductDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPKL]
    parser_classes = [MultiPartParser, FormParser]

    def _get_object(self, request, product_id):
        return get_object_or_404(
            PKLProduct,
            pk=product_id,
            pkl__user=request.user,
        )

    def patch(self, request, product_id):
        product = self._get_object(request, product_id)
        serializer = PKLProductWriteSerializer(
            product,
            data=request.data,
            partial=True,
        )
        if serializer.is_valid():
            product = serializer.save()
            read_serializer = PKLProductSerializer(
                product,
                context={'request': request},
            )
            return Response(read_serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    def delete(self, request, product_id):
        product = self._get_object(request, product_id)
        if product.image:
            product.image.delete(save=False)
        product.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

class IsAdmin(permissions.IsAdminUser):
    """Admin = user.is_staff == True (superuser juga is_staff)."""
    pass

# === VIEW ADMIN ===

class AdminPKLListView(generics.ListAPIView):
    """Daftar PKL untuk admin dengan dukungan filter status & pencarian."""

    serializer_class = PKLListSerializer
    permission_classes = [IsAdmin]

    def get_queryset(self):
        queryset = PKL.objects.all().annotate(
            average_rating=Avg('ratings__score'),
            rating_count=Count('ratings', distinct=True),
        )

        status_verifikasi = self.request.query_params.get('status_verifikasi')
        if status_verifikasi:
            queryset = queryset.filter(status_verifikasi=status_verifikasi.upper())

        status_aktif = self.request.query_params.get('status_aktif')
        if status_aktif is not None:
            normalized = status_aktif.lower()
            if normalized in ('true', '1'):  # pragma: no cover - defensive
                queryset = queryset.filter(status_aktif=True)
            elif normalized in ('false', '0'):
                queryset = queryset.filter(status_aktif=False)

        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(
                Q(nama_usaha__icontains=search) |
                Q(jenis_dagangan__icontains=search)
            )

        return queryset.order_by('-status_aktif', '-id')


class AdminPKLPendingListView(generics.ListAPIView):
    """
    GET /api/pkl/admin/pending/
    List semua PKL dengan status_verifikasi = PENDING
    """
    queryset = PKL.objects.filter(status_verifikasi='PENDING').annotate(
        average_rating=Avg('ratings__score'),
        rating_count=Count('ratings', distinct=True),
    )
    serializer_class = PKLListSerializer
    permission_classes = [IsAdmin]


class AdminPKLVerifyView(generics.UpdateAPIView):
    """
    PATCH /api/pkl/admin/<id>/verify/
    Body contoh:
    {
      "status_verifikasi": "DITERIMA",
      "catatan_verifikasi": "Data sesuai hasil survei lapangan",
      "status_aktif": true
    }
    """
    queryset = PKL.objects.all()
    serializer_class = PKLVerifySerializer
    permission_classes = [IsAdmin]


class AdminMonitoringPKLView(generics.ListAPIView):
    """
    GET /api/pkl/admin/monitor/
    List semua PKL aktif + lokasi terakhir (buat dashboard admin)
    """
    queryset = PKL.objects.filter(
        status_aktif=True,
        status_verifikasi='DITERIMA',
    ).annotate(
        average_rating=Avg('ratings__score'),
        rating_count=Count('ratings', distinct=True),
    )
    serializer_class = PKLListSerializer
    permission_classes = [IsAdmin]


class AdminDashboardView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        today = timezone.localdate()
        trend_start = today - timedelta(days=6)
        trend_rows = (
            PKLDailyStats.objects.filter(date__gte=trend_start)
            .values('date')
            .annotate(
                live_views=Sum('live_views'),
                search_hits=Sum('search_hits'),
                auto_updates=Sum('auto_updates'),
            )
        )
        trend_map = {row['date']: row for row in trend_rows}
        trend_data = []
        for offset in range(6, -1, -1):
            current_date = today - timedelta(days=offset)
            row = trend_map.get(current_date, {})
            trend_data.append({
                'date': current_date.isoformat(),
                'live_views': row.get('live_views', 0) or 0,
                'search_hits': row.get('search_hits', 0) or 0,
                'auto_updates': row.get('auto_updates', 0) or 0,
            })

        prev_range_end = trend_start - timedelta(days=1)
        prev_range_start = prev_range_end - timedelta(days=6)
        prev_stats = (
            PKLDailyStats.objects.filter(date__gte=prev_range_start, date__lte=prev_range_end)
            .aggregate(
                live_views=Sum('live_views'),
                search_hits=Sum('search_hits'),
                auto_updates=Sum('auto_updates'),
            )
        )

        pkls = PKL.objects.all()
        total_pkl = pkls.count()
        pending_pkl = pkls.filter(status_verifikasi='PENDING').count()
        verified_pkl = pkls.filter(status_verifikasi='DITERIMA').count()
        rejected_pkl = pkls.filter(status_verifikasi='DITOLAK').count()
        active_pkl = pkls.filter(status_aktif=True).count()
        inactive_pkl = total_pkl - active_pkl

        now = timezone.now()
        current_week_cutoff = now - timedelta(days=7)
        previous_week_cutoff = current_week_cutoff - timedelta(days=7)
        new_pkls_week = pkls.filter(user__date_joined__gte=current_week_cutoff).count()
        prev_new_pkls = pkls.filter(
            user__date_joined__gte=previous_week_cutoff,
            user__date_joined__lt=current_week_cutoff,
        ).count()

        location_updates_week = sum(item['auto_updates'] for item in trend_data)
        prev_location_updates = prev_stats.get('auto_updates') or 0

        rating_summary = PKLRating.objects.aggregate(
            average=Avg('score'),
            count=Count('id'),
        )

        top_pkls = (
            PKL.objects.filter(status_verifikasi='DITERIMA')
            .annotate(
                average_rating=Avg('ratings__score'),
                rating_count=Count('ratings', distinct=True),
            )
            .filter(average_rating__isnull=False)
            .order_by('-average_rating', '-rating_count', 'nama_usaha')[:5]
        )

        pending_preview = pkls.filter(status_verifikasi='PENDING').order_by('-user__date_joined')[:5]

        overdue_cutoff = now - timedelta(days=7)
        overdue_pending = pkls.filter(
            status_verifikasi='PENDING',
            user__date_joined__lt=overdue_cutoff,
        ).count()

        stale_cutoff = now - timedelta(days=3)
        stale_active = (
            PKL.objects.filter(status_verifikasi='DITERIMA', status_aktif=True)
            .annotate(latest_location=Max('lokasi__timestamp'))
            .filter(Q(latest_location__lt=stale_cutoff) | Q(latest_location__isnull=True))
            .count()
        )

        low_rating_count = (
            PKL.objects.filter(status_verifikasi='DITERIMA')
            .annotate(avg_rating=Avg('ratings__score'))
            .filter(avg_rating__lt=3, avg_rating__isnull=False)
            .count()
        )

        inactive_verified = pkls.filter(status_verifikasi='DITERIMA', status_aktif=False).count()

        reports = []
        if overdue_pending:
            reports.append({
                'id': 'pending_overdue',
                'title': 'PKL menunggu verifikasi',
                'description': f'{overdue_pending} PKL belum diproses lebih dari 7 hari.',
                'severity': 'warning',
                'action': 'Periksa tab Data PKL > Pending',
            })
        if stale_active:
            reports.append({
                'id': 'stale_locations',
                'title': 'Lokasi PKL tidak diperbarui',
                'description': f'{stale_active} PKL aktif belum memperbarui lokasi dalam 3 hari.',
                'severity': 'info',
                'action': 'Hubungi PKL terkait untuk update lokasi',
            })
        if low_rating_count:
            reports.append({
                'id': 'low_rating',
                'title': 'Rating PKL perlu perhatian',
                'description': f'{low_rating_count} PKL memiliki rating di bawah 3.',
                'severity': 'danger',
                'action': 'Tinjau ulasan pembeli untuk PKL terkait',
            })
        if inactive_verified:
            reports.append({
                'id': 'inactive_verified',
                'title': 'PKL terverifikasi tetapi non-aktif',
                'description': f'{inactive_verified} PKL terverifikasi sedang offline.',
                'severity': 'info',
                'action': 'Pertimbangkan kampanye aktivasi PKL',
            })

        response_data = {
            'summary': {
                'total_pkl': total_pkl,
                'verified_pkl': verified_pkl,
                'pending_pkl': pending_pkl,
                'rejected_pkl': rejected_pkl,
                'active_pkl': active_pkl,
                'inactive_pkl': inactive_pkl,
                'new_pkls_week': new_pkls_week,
                'prev_new_pkls': prev_new_pkls,
                'location_updates_week': location_updates_week,
                'prev_location_updates': prev_location_updates,
                'average_rating': None if rating_summary['average'] is None else round(float(rating_summary['average']), 1),
                'rating_count': rating_summary['count'] or 0,
            },
            'trend': trend_data,
            'top_pkls': PKLListSerializer(top_pkls, many=True).data,
            'pending_preview': PKLListSerializer(pending_preview, many=True).data,
            'reports': reports,
        }

        return Response(response_data, status=status.HTTP_200_OK)


# === PRE-ORDER ===

class CreatePreOrderView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        pkl_id = request.data.get('pkl_id')
        if not pkl_id:
            return Response(
                {"detail": "pkl_id wajib diisi."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            pkl = PKL.objects.get(id=pkl_id, status_aktif=True, status_verifikasi='DITERIMA')
        except PKL.DoesNotExist:
            return Response(
                {"detail": "PKL tidak ditemukan / belum aktif."},
                status=status.HTTP_404_NOT_FOUND,
            )

        payload = request.data.copy()
        perkiraan_total = payload.pop('perkiraan_total', None)
        dp_amount = payload.get('dp_amount')

        if dp_amount in (None, '', 0, '0'):
            computed_dp = 5000
            if perkiraan_total:
                try:
                    total_float = float(perkiraan_total)
                    computed_dp = max(5000, int(total_float * 0.2))
                except (TypeError, ValueError):
                    computed_dp = 5000
            payload['dp_amount'] = computed_dp
        else:
            try:
                payload['dp_amount'] = int(dp_amount)
            except (TypeError, ValueError):
                payload['dp_amount'] = 5000

        serializer = PreOrderSerializer(data=payload)
        if serializer.is_valid():
            preorder = serializer.save(
                pembeli=request.user,
                pkl=pkl,
                status='PENDING',
                dp_status='BELUM_BAYAR',
            )
            return Response(PreOrderSerializer(preorder).data, status=status.HTTP_201_CREATED)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class MyPreOrderListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        preorders = PreOrder.objects.filter(pembeli=request.user).order_by('-created_at')
        serializer = PreOrderSerializer(preorders, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class PKLPreOrderListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        try:
            pkl = PKL.objects.get(user=request.user)
        except PKL.DoesNotExist:
            return Response(
                {"detail": "Profil PKL belum dibuat."},
                status=status.HTTP_404_NOT_FOUND,
            )

        preorders = PreOrder.objects.filter(pkl=pkl).order_by('-created_at')
        serializer = PreOrderSerializer(preorders, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class UpdatePreOrderStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, preorder_id):
        try:
            preorder = PreOrder.objects.select_related('pkl').get(id=preorder_id)
        except PreOrder.DoesNotExist:
            return Response(
                {"detail": "Pre-order tidak ditemukan."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if preorder.pkl.user != request.user:
            return Response(
                {"detail": "Tidak punya akses."},
                status=status.HTTP_403_FORBIDDEN,
            )

        new_status = request.data.get('status')
        if new_status not in ['DITERIMA', 'DITOLAK', 'SELESAI']:
            return Response(
                {"detail": "Status tidak valid."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        preorder.status = new_status
        preorder.save(update_fields=['status'])
        serializer = PreOrderSerializer(preorder)
        return Response(serializer.data, status=status.HTTP_200_OK)


class SubmitDPProofView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, preorder_id):
        try:
            preorder = PreOrder.objects.get(id=preorder_id, pembeli=request.user)
        except PreOrder.DoesNotExist:
            return Response(
                {"detail": "Pre-order tidak ditemukan."},
                status=status.HTTP_404_NOT_FOUND,
            )

        bukti_url = request.data.get('bukti_dp_url')
        if not bukti_url:
            return Response(
                {"detail": "bukti_dp_url wajib diisi."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        preorder.bukti_dp_url = bukti_url
        preorder.dp_status = 'MENUNGGU_KONFIRMASI'
        preorder.save(update_fields=['bukti_dp_url', 'dp_status', 'updated_at'])

        return Response(PreOrderSerializer(preorder).data, status=status.HTTP_200_OK)


class PKLDPVerificationView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, preorder_id):
        try:
            pkl = PKL.objects.get(user=request.user)
        except PKL.DoesNotExist:
            return Response(
                {"detail": "Profil PKL belum dibuat."},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            preorder = PreOrder.objects.get(id=preorder_id, pkl=pkl)
        except PreOrder.DoesNotExist:
            return Response(
                {"detail": "Pre-order tidak ditemukan."},
                status=status.HTTP_404_NOT_FOUND,
            )

        action = request.data.get('action')
        if action not in ['TERIMA', 'TOLAK']:
            return Response(
                {"detail": "Action tidak valid."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if action == 'TERIMA':
            preorder.dp_status = 'TERKONFIRMASI'
            preorder.status = 'DITERIMA'
        else:
            preorder.dp_status = 'BELUM_BAYAR'
            preorder.status = 'DITOLAK'

        preorder.save(update_fields=['dp_status', 'status', 'updated_at'])
        return Response(PreOrderSerializer(preorder).data, status=status.HTTP_200_OK)


class DPProofUploadView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        file_obj = request.FILES.get('file')
        if not file_obj:
            return Response(
                {"detail": "File tidak ditemukan."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        extension = file_obj.name.split('.')[-1]
        filename = f"dp_proofs/{uuid.uuid4().hex}.{extension}"
        saved_path = default_storage.save(filename, file_obj)
        file_url = request.build_absolute_uri(default_storage.url(saved_path))

        return Response({'url': file_url}, status=status.HTTP_201_CREATED)


class NotificationListView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPembeli]

    def get(self, request):
        unread_only = request.query_params.get('unread')
        limit_param = request.query_params.get('limit')
        queryset = Notification.objects.filter(buyer=request.user)
        if unread_only and unread_only.lower() in ('1', 'true', 'yes'):
            queryset = queryset.filter(is_read=False)

        try:
            limit = int(limit_param) if limit_param else 50
        except ValueError:
            limit = 50

        notifications = queryset.order_by('-created_at')[:max(1, min(limit, 100))]
        serializer = NotificationSerializer(notifications, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class NotificationMarkReadView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPembeli]

    def post(self, request, notification_id):
        try:
            notification = Notification.objects.get(id=notification_id, buyer=request.user)
        except Notification.DoesNotExist:
            return Response(
                {"detail": "Notifikasi tidak ditemukan."},
                status=status.HTTP_404_NOT_FOUND,
            )

        notification.is_read = True
        notification.save(update_fields=['is_read'])
        return Response(NotificationSerializer(notification).data, status=status.HTTP_200_OK)