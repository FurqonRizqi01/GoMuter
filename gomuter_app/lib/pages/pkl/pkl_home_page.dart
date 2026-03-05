import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/navigation/pkl_routes.dart';
import 'package:gomuter_app/utils/chat_badge_manager.dart';
import 'package:gomuter_app/utils/pkl_location_service.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';
import 'package:latlong2/latlong.dart';

class PklHomePage extends StatefulWidget {
  const PklHomePage({super.key});

  @override
  State<PklHomePage> createState() => _PklHomePageState();
}

class _PklHomePageState extends State<PklHomePage> {
  final ThemeManager _themeManager = ThemeManager();
  final PklLocationService _locationService = PklLocationService();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isNewProfile = false;
  bool _statusAktif = false;
  bool _isUpdatingStatusAktif = false;
  String? _error;

  String _namaUsaha = '';
  String _jenisDagangan = '';
  String _jamOperasional = '';
  String _alamatDomisili = '';
  String _statusVerifikasi = '';
  String? _profileImageUrl;

  double? _latestLatitude;
  double? _latestLongitude;

  int _liveViewsToday = 0;
  int _searchHitsToday = 0;
  int _autoUpdatesToday = 0;
  int _unreadChatCount = 0;
  int _completedOrdersToday = 0;
  int _todayRevenue = 0;
  int _pendingOrdersCount = 0;
  List<dynamic> _recentOrders = [];

  double? _ratingAvg;
  int? _ratingCount;

  DateTime? _lastLocationUpdate;
  bool _autoLocationEnabled = false;

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    _locationService.addListener(_onLocationServiceChanged);
    _locationService.initialize();
    _loadProfile();
    _loadChatBadge();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    _locationService.removeListener(_onLocationServiceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onLocationServiceChanged() {
    if (!mounted) return;
    setState(() {
      _lastLocationUpdate = _locationService.lastUpdate;
      _autoLocationEnabled = _locationService.isAutoMode;
    });
  }

  Future<String?> _getToken() async {
    return TokenManager.getValidAccessToken();
  }

  Future<void> _loadChatBadge() async {
    try {
      final token = await _getToken();
      if (token == null) return;
      final chats = await ApiService.getChats(token: token);
      final count = await ChatBadgeManager.countUnreadChats(
        chats,
        ChatRole.pkl,
      );
      if (!mounted) return;
      setState(() {
        _unreadChatCount = count;
      });
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
        });
        return;
      }

      final profile = await ApiService.getPKLProfile(token);
      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _isNewProfile = true;
          _statusAktif = false;
          _liveViewsToday = 0;
          _searchHitsToday = 0;
          _autoUpdatesToday = 0;
          _latestLatitude = null;
          _latestLongitude = null;
        });
      } else {
        final lat = (profile['latest_latitude'] as num?)?.toDouble();
        final lng = (profile['latest_longitude'] as num?)?.toDouble();
        setState(() {
          _isNewProfile = false;
          _namaUsaha = profile['nama_usaha'] ?? '';
          _jenisDagangan = profile['jenis_dagangan'] ?? '';
          _jamOperasional = profile['jam_operasional'] ?? '';
          _alamatDomisili = profile['alamat_domisili'] ?? '';
          _statusVerifikasi = (profile['status_verifikasi'] ?? 'PENDING')
              .toString()
              .toUpperCase();
          _statusAktif = profile['status_aktif'] ?? false;
          _latestLatitude = lat;
          _latestLongitude = lng;
          _profileImageUrl =
              (profile['profile_image_url'] as String?)?.trim();
        });

        final pklId = (profile['id'] as num?)?.toInt();
        if (pklId != null) {
          try {
            final rating =
                await ApiService.getPKLRatingSummary(pklId: pklId);
            _ratingAvg =
                (rating['average_rating'] as num?)?.toDouble();
            _ratingCount =
                (rating['rating_count'] as num?)?.toInt();
          } catch (_) {}
        }

        await _loadStats(token);
        await _loadOrders(token);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat profil PKL. $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    await _loadChatBadge();
  }

  Future<void> _loadOrders(String token) async {
    try {
      final orders = await ApiService.getPKLPreOrders(token: token);
      if (!mounted) return;
      final pending = orders
          .whereType<Map<String, dynamic>>()
          .where((o) =>
              (o['status'] as String?)?.toUpperCase() == 'PENDING' ||
              (o['status'] as String?)?.toUpperCase() == 'DITERIMA')
          .toList();
      setState(() {
        _recentOrders = pending.take(5).toList();
        _pendingOrdersCount = pending.length;
      });
    } catch (_) {}
  }

  Future<void> _openLocationPage() async {
    await Navigator.of(context).pushNamed(PklRoutes.location);
    if (!mounted) return;
    await _loadProfile();
  }

  Future<void> _loadStats(String token) async {
    try {
      final stats = await ApiService.getPKLDailyStats(token: token);
      if (!mounted) return;
      setState(() {
        _liveViewsToday = (stats['live_views'] as num?)?.toInt() ?? 0;
        _searchHitsToday = (stats['search_hits'] as num?)?.toInt() ?? 0;
        _autoUpdatesToday = (stats['auto_updates'] as num?)?.toInt() ?? 0;
        _todayRevenue = (stats['today_revenue'] as num?)?.toInt() ?? 0;
        _completedOrdersToday = (stats['today_completed'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _setStatusAktif(bool value) async {
    if (_isUpdatingStatusAktif) return;
    if (_isNewProfile) {
      _showProfileRequired();
      return;
    }

    final token = await _getToken();
    if (token == null) {
      _showSnack('Token tidak ditemukan. Silakan login ulang.');
      return;
    }

    final previous = _statusAktif;

    setState(() {
      _isUpdatingStatusAktif = true;
      _statusAktif = value;
    });

    try {
      final updated = await ApiService.savePKLProfile(
        token: token,
        data: {'status_aktif': value},
        isNew: false,
      );

      if (!mounted) return;
      setState(() {
        _statusAktif = updated['status_aktif'] == true;
      });

      _showSnack(
        _statusAktif
            ? 'Status aktif dihidupkan. Kamu akan terlihat oleh pembeli.'
            : 'Status aktif dimatikan. Kamu tidak tampil di pembeli.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusAktif = previous;
      });
      _showSnack('Gagal mengubah status aktif. $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStatusAktif = false;
        });
      }
    }
  }

  Future<void> _openEditInfoPage() async {
    final updated = await Navigator.of(context).pushNamed(PklRoutes.manage);
    if (updated == true) {
      _loadProfile();
    }
  }

  void _showProfileRequired() {
    showDialog<void>(
      context: context,
      builder: (_) {
        final orange = _themeManager.pklPrimary;
        return AlertDialog(
          title: const Text('Lengkapi Profil'),
          content: const Text(
            'Isi informasi dagangan terlebih dahulu agar fitur ini bisa digunakan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Nanti'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _openEditInfoPage();
              },
              style: ElevatedButton.styleFrom(backgroundColor: orange),
              child: const Text('Isi Sekarang',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Header with avatar, name, rating, notification ───
  Widget _buildHeader() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final orange = _themeManager.pklPrimary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      color: cardColor,
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _themeManager.pklAccentSurface,
              border: Border.all(
                color: orange.withValues(alpha: 0.3),
                width: 2,
              ),
              image: _profileImageUrl != null &&
                      _profileImageUrl!.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(_profileImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: (_profileImageUrl == null || _profileImageUrl!.isEmpty)
                ? Icon(Icons.storefront_rounded,
                    color: orange, size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          // Name + Rating
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _namaUsaha.isEmpty ? 'Mitra PKL' : _namaUsaha,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.star_rounded,
                        color: orange, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _ratingAvg != null
                          ? _ratingAvg!.toStringAsFixed(1)
                          : '-',
                      style: TextStyle(
                        color: orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (_ratingCount != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${_ratingCount! >= 1000 ? '${(_ratingCount! / 1000).toStringAsFixed(1)}k' : _ratingCount.toString()} Rating)',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Notification bell
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey[100],
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.notifications_outlined,
                      color: textColor, size: 24),
                ),
                if (_unreadChatCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: cardColor, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Status Toko Card ───
  Widget _buildStatusTokoCard() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final orange = _themeManager.pklPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Toko',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusAktif
                        ? 'Terima pesanan sekarang'
                        : 'Toko sedang tutup',
                    style: TextStyle(
                      color: mutedText,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: _statusAktif,
              onChanged: _isUpdatingStatusAktif
                  ? null
                  : (value) {
                      if (_isNewProfile) {
                        _showProfileRequired();
                        return;
                      }
                      _setStatusAktif(value);
                    },
              activeThumbColor: Colors.white,
              activeTrackColor: orange,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.black.withValues(
                alpha: isDark ? 0.35 : 0.18,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Summary Cards (Pendapatan + Selesai) ───
  Widget _buildSummaryCards() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final orange = _themeManager.pklPrimary;
    final lightOrangeBg = _themeManager.pklAccentSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          // PENDAPATAN card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDark ? 0.15 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: lightOrangeBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.account_balance_wallet_rounded,
                            color: orange, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PENDAPATAN',
                        style: TextStyle(
                          color: mutedText,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Rp ${_formatCurrency(_todayRevenue)}',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // SELESAI card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDark ? 0.15 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: lightOrangeBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.inventory_2_rounded,
                            color: orange, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SELESAI',
                        style: TextStyle(
                          color: mutedText,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$_completedOrdersToday Pesanan',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  // ─── Quick Menu (4 items: Stok, Riwayat, QRIS, Setelan) ───
  Widget _buildQuickMenu() {
    final orange = _themeManager.pklPrimary;
    final lightOrangeBg = _themeManager.pklAccentSurface;
    final textColor = _themeManager.textColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _buildQuickMenuItem(
            icon: Icons.inventory_rounded,
            label: 'Stok',
            color: orange,
            bgColor: lightOrangeBg,
            textColor: textColor,
            onTap: _openEditInfoPage,
          ),
          const SizedBox(width: 16),
          _buildQuickMenuItem(
            icon: Icons.history_rounded,
            label: 'Riwayat',
            color: orange,
            bgColor: lightOrangeBg,
            textColor: textColor,
            onTap: () =>
                Navigator.of(context).pushNamed(PklRoutes.orders),
          ),
          const SizedBox(width: 16),
          _buildQuickMenuItem(
            icon: Icons.qr_code_2_rounded,
            label: 'QRIS',
            color: orange,
            bgColor: lightOrangeBg,
            textColor: textColor,
            onTap: () =>
                Navigator.of(context).pushNamed(PklRoutes.payment),
          ),
          const SizedBox(width: 16),
          _buildQuickMenuItem(
            icon: Icons.location_on_rounded,
            label: 'Update Lokasi',
            color: orange,
            bgColor: lightOrangeBg,
            textColor: textColor,
            onTap: () =>
                Navigator.of(context).pushNamed(PklRoutes.location),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Pesanan Langsung Section ───
  Widget _buildPesananLangsungSection() {
    final textColor = _themeManager.textColor;
    final orange = _themeManager.pklPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Text(
                'Pesanan Langsung',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
              if (_pendingOrdersCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_pendingOrdersCount Baru',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              InkWell(
                onTap: () =>
                    Navigator.of(context).pushNamed(PklRoutes.orders),
                child: Text(
                  'Lihat Semua',
                  style: TextStyle(
                    color: orange,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Order cards
          if (_recentOrders.isEmpty)
            _buildEmptyOrderState()
          else
            ..._recentOrders.map<Widget>((order) {
              final o = order as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildOrderCard(o),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildEmptyOrderState() {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final orange = _themeManager.pklPrimary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _themeManager.borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _themeManager.pklAccentSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_rounded,
                size: 36, color: orange),
          ),
          const SizedBox(height: 14),
          Text(
            'Belum ada pesanan baru',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pesanan dari pembeli akan tampil di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final orange = _themeManager.pklPrimary;

    final pembeli = order['pembeli_username'] as String? ?? '-';
    final deskripsi = order['deskripsi_pesanan'] as String? ?? '-';
    final status = (order['status'] as String? ?? 'PENDING').toUpperCase();
    final orderId = (order['id'] as num?)?.toInt() ?? 0;
    final createdAt =
        DateTime.tryParse(order['created_at'] as String? ?? '');
    final totalPrice = order['total_price'] as int? ?? 0;

    // Time display
    String timeLabel = '';
    if (createdAt != null) {
      final diff = DateTime.now().difference(createdAt.toLocal());
      if (diff.inMinutes < 60) {
        timeLabel = '${diff.inMinutes} min lalu';
      } else if (diff.inHours < 24) {
        timeLabel = '${diff.inHours}j lalu';
      } else {
        timeLabel =
            '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}';
      }
    }

    // Status label
    String statusLabel;
    Color statusColor;
    if (status == 'PENDING') {
      statusLabel = 'Baru';
      statusColor = orange;
    } else if (status == 'DITERIMA') {
      statusLabel = 'Dimasak';
      statusColor = orange;
    } else {
      statusLabel = status;
      statusColor = mutedText;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Orange left accent
            Container(width: 4, color: orange),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
            // Buyer avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _themeManager.pklAccentSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.person_rounded,
                  color: orange, size: 22),
            ),
            const SizedBox(width: 12),
            // Name + items
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pembeli,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deskripsi,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (totalPrice > 0) ...[
                        Text(
                          'Rp ${_formatCurrency(totalPrice)}',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '#$orderId',
                          style: TextStyle(
                            color: mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ] else
                        Text(
                          'Order #$orderId',
                          style: TextStyle(
                            color: mutedText,
                            fontSize: 12,
                          ),
                        ),
                      const Spacer(),
                      if (timeLabel.isNotEmpty)
                        Text(
                          timeLabel,
                          style: TextStyle(
                            color: mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTimeShort(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$min';
  }

  // ─── Info Card (Informasi Dagangan) ───
  Widget _buildInfoCard() {
    final borderColor = _themeManager.borderColor;
    final orange = _themeManager.pklPrimary;
    final lightOrangeBg = _themeManager.pklAccentSurface;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      color: _themeManager.cardColor,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: lightOrangeBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Informasi Dagangan',
                    style: TextStyle(
                      color: _themeManager.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildInfoRow('Nama', _namaUsaha.isEmpty ? '-' : _namaUsaha),
              _buildInfoRow(
                'Kategori',
                _jenisDagangan.isEmpty ? '-' : _jenisDagangan,
              ),
              _buildInfoRow(
                'Jam Operasional',
                _jamOperasional.isEmpty ? '-' : _jamOperasional,
              ),
              _buildInfoRow(
                'Alamat',
                _alamatDomisili.isEmpty ? '-' : _alamatDomisili,
              ),
              _buildInfoRow(
                'Status Verifikasi',
                _statusVerifikasi.isEmpty ? 'PENDING' : _statusVerifikasi,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Stats Section ───
  Widget _buildStatsSection() {
    final borderColor = _themeManager.borderColor;
    final orange = _themeManager.pklPrimary;
    final lightOrangeBg = _themeManager.pklAccentSurface;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      color: _themeManager.cardColor,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: lightOrangeBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Statistik Hari Ini',
                    style: TextStyle(
                      color: _themeManager.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _buildStatsRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final orange = _themeManager.pklPrimary;
    final secondaryOrange = _themeManager.pklSecondary;
    final autoStatus = _autoLocationEnabled ? 'Aktif' : 'Nonaktif';
    final lastUpdateLabel = _lastLocationUpdate != null
        ? _formatDateTimeShort(_lastLocationUpdate!)
        : '--/-- --:--';

    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _buildStatBox(
              title: 'Live',
              subtitle: 'Tampilan',
              value: _liveViewsToday.toString(),
              color: orange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildStatBox(
              title: 'Pencarian',
              subtitle: 'Muncul di hasil',
              value: _searchHitsToday.toString(),
              color: secondaryOrange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildStatBox(
              title: 'Auto-update',
              subtitle: 'Sinkronisasi',
              value: _autoUpdatesToday.toString(),
              color: orange,
              footnote: '$autoStatus \u00b7 Terakhir $lastUpdateLabel',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String title,
    required String subtitle,
    required String value,
    required Color color,
    String? footnote,
  }) {
    final isDark = _themeManager.isDarkMode;
    final mutedText = _themeManager.mutedTextColor;
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minHeight: 160),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 14),
            Text(
              footnote,
              style: TextStyle(
                fontSize: 11,
                color: mutedText.withValues(alpha: isDark ? 0.85 : 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Location Preview Card ───
  Widget _buildLocationPreviewCard() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final orange = _themeManager.pklPrimary;

    final overlayBase = isDark ? Colors.black : Colors.white;
    final overlayTextColor = textColor;

    final previewTint = Color.alphaBlend(
      orange.withValues(alpha: isDark ? 0.20 : 0.10),
      cardColor,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isNewProfile ? _showProfileRequired : _openLocationPage,
            child: Container(
              height: 240,
              decoration: BoxDecoration(
                color: previewTint,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.08),
                    blurRadius: 26,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: AbsorbPointer(
                        child: _buildLocationMapPreview(
                          isDark: isDark,
                          previewTint: previewTint,
                        ),
                      ),
                    ),
                  ),
                  // LIVE badge
                  Positioned(
                    left: 16,
                    top: 16,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _statusAktif ? 1 : 0.0,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 110),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            orange.withValues(alpha: 0.90),
                            cardColor,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.circle, size: 10, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom overlay with name + address
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            overlayBase.withValues(alpha: 0.0),
                            overlayBase.withValues(alpha: isDark ? 0.82 : 0.92),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: orange,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _namaUsaha.isEmpty
                                      ? 'Mitra PKL'
                                      : _namaUsaha,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: overlayTextColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _alamatDomisili.isEmpty
                                      ? 'Tambahkan alamat domisili kamu'
                                      : _alamatDomisili,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: overlayTextColor.withValues(
                                      alpha: isDark ? 0.85 : 0.75,
                                    ),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _jenisDagangan.isNotEmpty
                                  ? _jenisDagangan
                                  : 'Lengkapi kategori',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: overlayTextColor.withValues(
                                  alpha: _jenisDagangan.isNotEmpty
                                      ? 0.85
                                      : (isDark ? 0.75 : 0.70),
                                ),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Verification badge
                  Positioned(
                    right: 16,
                    top: 16,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          (isDark
                                  ? Colors.black
                                  : _themeManager.overlayScrimColor)
                              .withValues(alpha: isDark ? 0.45 : 0.92),
                          isDark ? cardColor : Colors.white,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (_statusVerifikasi.isEmpty
                                          ? 'PENDING'
                                          : _statusVerifikasi) ==
                                      'DITERIMA'
                                  ? Icons.verified_rounded
                                  : (_statusVerifikasi.isEmpty
                                            ? 'PENDING'
                                            : _statusVerifikasi) ==
                                        'DITOLAK'
                                  ? Icons.cancel_rounded
                                  : Icons.schedule_rounded,
                              size: 16,
                              color: overlayTextColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (_statusVerifikasi.isEmpty
                                      ? 'PENDING'
                                      : _statusVerifikasi)
                                  .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: overlayTextColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Update location button
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isNewProfile ? null : _openLocationPage,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Update'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  // New profile hint
                  if (_isNewProfile)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 74,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            orange.withValues(alpha: 0.20),
                            cardColor,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: orange,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Lengkapi profil dagangan untuk mengaktifkan fitur lokasi.',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Location Map Preview ───
  Widget _buildLocationMapPreview({
    required bool isDark,
    required Color previewTint,
  }) {
    final lat = _latestLatitude;
    final lng = _latestLongitude;
    final orange = _themeManager.pklPrimary;

    if (lat == null || lng == null) {
      return Opacity(
        opacity: isDark ? 0.20 : 0.12,
        child: const Center(child: Icon(Icons.map_outlined, size: 220)),
      );
    }

    final point = LatLng(lat, lng);
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.gomuter_app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      color: orange,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.9 : 0.95,
                        ),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        Container(
            color: previewTint.withValues(alpha: isDark ? 0.10 : 0.06)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _themeManager.backgroundColor;

    final bodyContent = SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildLocationPreviewCard(),
          _buildStatusTokoCard(),
          _buildSummaryCards(),
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: _themeManager.borderColor,
            ),
          ),
          const SizedBox(height: 4),
          _buildQuickMenu(),
          // Divider
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Divider(
              height: 1,
              thickness: 1,
              color: _themeManager.borderColor,
            ),
          ),
          // Error / New profile banner
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          if (_isNewProfile)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _themeManager.pklAccentSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _themeManager.pklPrimary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: _themeManager.pklPrimary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lengkapi profil dagangan untuk mengaktifkan fitur.',
                        style: TextStyle(
                          color: _themeManager.textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _buildPesananLangsungSection(),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildInfoCard(),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildStatsSection(),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: _themeManager.pklPrimary,
              ),
            )
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: _themeManager.pklPrimary,
                onRefresh: _loadProfile,
                child: bodyContent,
              ),
            ),
      bottomNavigationBar: PklBottomNavBar(
        current: PklNavItem.home,
        chatBadgeCount: _unreadChatCount,
      ),
    );
  }
}
