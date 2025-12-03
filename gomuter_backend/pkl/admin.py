from django.contrib import admin
from .models import (
    PKL,
    LokasiPKL,
    BuyerLocation,
    FavoritePKL,
    Notification,
    PKLDailyStats,
    PKLProduct,
)

@admin.register(PKL)
class PKLAdmin(admin.ModelAdmin):
    list_display = ('nama_usaha', 'jenis_dagangan', 'status_aktif', 'jam_operasional')
    search_fields = ('nama_usaha', 'jenis_dagangan')

@admin.register(LokasiPKL)
class LokasiPKLAdmin(admin.ModelAdmin):
    list_display = ('pkl', 'latitude', 'longitude', 'timestamp', 'status')
    list_filter = ('status',)


@admin.register(BuyerLocation)
class BuyerLocationAdmin(admin.ModelAdmin):
    list_display = ('buyer', 'latitude', 'longitude', 'radius_m', 'updated_at')
    search_fields = ('buyer__username',)


@admin.register(FavoritePKL)
class FavoritePKLAdmin(admin.ModelAdmin):
    list_display = ('buyer', 'pkl', 'created_at')
    search_fields = ('buyer__username', 'pkl__nama_usaha')


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ('buyer', 'notif_type', 'pkl', 'is_read', 'created_at')
    list_filter = ('notif_type', 'is_read')
    search_fields = ('buyer__username', 'pkl__nama_usaha', 'message')


@admin.register(PKLDailyStats)
class PKLDailyStatsAdmin(admin.ModelAdmin):
    list_display = ('pkl', 'date', 'live_views', 'search_hits', 'auto_updates')
    list_filter = ('date',)
    search_fields = ('pkl__nama_usaha',)


@admin.register(PKLProduct)
class PKLProductAdmin(admin.ModelAdmin):
    list_display = ('name', 'pkl', 'price', 'is_available', 'is_featured', 'updated_at')
    list_filter = ('is_available', 'is_featured')
    search_fields = ('name', 'pkl__nama_usaha')
