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

  double? _latestLatitude;
  double? _latestLongitude;

  int _liveViewsToday = 0;
  int _searchHitsToday = 0;
  int _autoUpdatesToday = 0;
  int _unreadChatCount = 0;

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

  String _formatDateTimeShort(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$min';
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
    } catch (_) {
      // Diamkan jika gagal, badge tidak kritikal.
    }
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
        });
        await _loadStats(token);
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
      });
    } catch (_) {
      // Biarkan tanpa perubahan bila statistik gagal dimuat.
    }
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
    final updated = await Navigator.of(context).pushNamed(PklRoutes.profile);
    if (updated == true) {
      _loadProfile();
    }
  }

  void _showProfileRequired() {
    showDialog<void>(
      context: context,
      builder: (_) {
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
              child: const Text('Isi Sekarang'),
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

  Widget _buildSectionHeading({required String title, String? subtitle}) {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.4,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: mutedText,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _resolveGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 11) return 'Selamat Pagi';
    if (hour >= 11 && hour < 15) return 'Selamat Siang';
    return 'Halo';
  }

  Widget _buildGreetingHeader() {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final borderColor = _themeManager.borderColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _resolveGreeting(),
            style: TextStyle(
              color: mutedText,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _namaUsaha.isEmpty ? 'Mitra PKL' : _namaUsaha,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: borderColor),
        ],
      ),
    );
  }

  Widget _buildStatusWarungCard() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _themeManager.accentSurfaceColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.store_mall_directory_outlined,
                color: _themeManager.primaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Warung',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Buka untuk menerima pesanan',
                    style: TextStyle(
                      color: mutedText,
                      fontWeight: FontWeight.w600,
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
              activeTrackColor: _themeManager.primaryGreen.withValues(
                alpha: 0.55,
              ),
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

  Widget _buildLocationPreviewCard() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;

    final overlayBase = isDark ? Colors.black : Colors.white;
    final overlayTextColor = textColor;

    final previewTint = Color.alphaBlend(
      _themeManager.primaryGreen.withValues(alpha: isDark ? 0.20 : 0.10),
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
                            _themeManager.primaryGreen.withValues(alpha: 0.90),
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
                              color: _themeManager.accentGold,
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
                                  _namaUsaha.isEmpty ? 'Mitra PKL' : _namaUsaha,
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
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: ElevatedButton.icon(
                      onPressed: _isNewProfile ? null : _openLocationPage,
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
                  if (_isNewProfile)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 74,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            _themeManager.accentGold.withValues(alpha: 0.20),
                            cardColor,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: _themeManager.accentGold,
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

  Widget _buildHeroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGreetingHeader(),
        _buildStatusWarungCard(),
        _buildLocationPreviewCard(),
      ],
    );
  }

  Widget _buildQuickMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          title: 'Menu Cepat',
          subtitle: 'Akses fitur utama dengan sekali tap.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildQuickMenuButton(
                  icon: Icons.storefront_outlined,
                  label: 'Produk',
                  onTap: _openEditInfoPage,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildQuickMenuButton(
                  icon: Icons.receipt_long_rounded,
                  label: 'Pesanan',
                  onTap: () =>
                      Navigator.of(context).pushNamed(PklRoutes.orders),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildQuickMenuButton(
                  icon: Icons.qr_code_2_rounded,
                  label: 'QRIS',
                  onTap: () =>
                      Navigator.of(context).pushNamed(PklRoutes.payment),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _themeManager.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Icon(icon, color: _themeManager.primaryGreen, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final borderColor = _themeManager.borderColor;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      color: _themeManager.cardColor,
      shadowColor: Colors.black.withValues(alpha: 0.1),
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
                      color: _themeManager.accentSurfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: _themeManager.primaryGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Informasi Dagangan',
                    style: TextStyle(
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

  Widget _buildStatsSection() {
    final borderColor = _themeManager.borderColor;
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
                      color: _themeManager.accentSurfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: _themeManager.accentGold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Statistik Hari Ini',
                    style: TextStyle(
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
              color: _themeManager.primaryGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildStatBox(
              title: 'Pencarian',
              subtitle: 'Muncul di hasil',
              value: _searchHitsToday.toString(),
              color: _themeManager.accentGold,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildStatBox(
              title: 'Auto-update',
              subtitle: 'Sinkronisasi',
              value: _autoUpdatesToday.toString(),
              color: _themeManager.primaryGreen,
              footnote: '$autoStatus • Terakhir $lastUpdateLabel',
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

  Widget _buildLocationMapPreview({
    required bool isDark,
    required Color previewTint,
  }) {
    final lat = _latestLatitude;
    final lng = _latestLongitude;
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
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                      color: _themeManager.accentGold,
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
        Container(color: previewTint.withValues(alpha: isDark ? 0.10 : 0.06)),
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
          _buildHeroSection(),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_isNewProfile)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Profil kamu belum diajukan. Lengkapi data dagangan agar pembeli dapat menemukanmu.',
                      style: TextStyle(color: Color(0xFFBF360C)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildQuickMenu(),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(),
                const SizedBox(height: 18),
                _buildStatsSection(),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
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

class _AnimatedButton extends StatefulWidget {
  const _AnimatedButton({required this.child});

  final Widget child;

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}
