import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/navigation/pkl_routes.dart';
import 'package:gomuter_app/utils/chat_badge_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';

class PklHomePage extends StatefulWidget {
  const PklHomePage({super.key});

  @override
  State<PklHomePage> createState() => _PklHomePageState();
}

class _PklHomePageState extends State<PklHomePage> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isNewProfile = false;
  bool _statusAktif = false;
  bool _isUpdatingLocation = false;
  String? _error;
  String? _hoveredActionCard;
  String? _pressedActionCard;

  String _namaUsaha = '';
  String _jenisDagangan = '';
  String _jamOperasional = '';
  String _alamatDomisili = '';
  String _statusVerifikasi = '';

  String? _locationMessage;
  Timer? _locationTimer;
  DateTime? _lastAutoUpdate;
  int _liveViewsToday = 0;
  int _searchHitsToday = 0;
  int _autoUpdatesToday = 0;
  int _unreadChatCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadChatBadge();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _locationTimer?.cancel();
    super.dispose();
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
          _locationMessage ??= 'Belum pernah update lokasi.';
          _liveViewsToday = 0;
          _searchHitsToday = 0;
          _autoUpdatesToday = 0;
        });
      } else {
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
          _locationMessage ??=
              'Bagikan lokasi agar pembeli tahu posisi terbaru kamu.';
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

  Future<void> _updateLocation() async {
    if (_isUpdatingLocation) return;

    final token = await _getToken();
    if (token == null) {
      setState(() {
        _error = 'Token tidak ditemukan. Silakan login ulang.';
      });
      return;
    }

    final hasAccess = await _ensureLocationAccess();
    if (!hasAccess) return;

    setState(() {
      _isUpdatingLocation = true;
      _locationMessage = 'Mengambil lokasi perangkat...';
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await ApiService.updatePKLLocation(
        token: token,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _locationMessage = 'Lokasi diperbarui ${_formatTime(now)}';
        _lastAutoUpdate = now;
        _autoUpdatesToday += 1;
      });
      _showSnack('Lokasi berhasil diperbarui.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationMessage = 'Gagal memperbarui lokasi.';
      });
      _showSnack('Gagal memperbarui lokasi. $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingLocation = false;
        });
      }
    }
  }

  Future<bool> _ensureLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Aktifkan layanan lokasi terlebih dahulu.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showSnack('Izin lokasi ditolak. Buka pengaturan untuk mengaktifkannya.');
      return false;
    }
    return true;
  }

  Future<void> _toggleAutoSync() async {
    if (_locationTimer != null) {
      _stopAutoSync();
    } else {
      await _startAutoSync();
    }
  }

  Future<void> _startAutoSync() async {
    final hasAccess = await _ensureLocationAccess();
    if (!hasAccess) return;

    _locationTimer?.cancel();
    await _updateLocation();
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _updateLocation();
    });
    setState(() {});
    _showSnack('Auto-update lokasi aktif.');
  }

  void _stopAutoSync() {
    _locationTimer?.cancel();
    _locationTimer = null;
    setState(() {});
    _showSnack('Auto-update lokasi dimatikan.');
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Keluar'),
        content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TokenManager.clearTokens();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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

  String _formatTime(DateTime time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  Widget _buildHeroSection() {
    const overlap = 12.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16 + overlap),
          Transform.translate(
            offset: const Offset(0, -overlap),
            child: _buildLocationPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final status = _statusVerifikasi.isEmpty ? 'PENDING' : _statusVerifikasi;
    final colors = _statusChipColors(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B7332), Color(0xFF10A14D), Color(0xFF25D366)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D8A3A).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF0D8A3A).withValues(alpha: 0.1),
            blurRadius: 48,
            offset: const Offset(0, 20),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.store_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _namaUsaha.isEmpty
                          ? 'Selamat datang, Mitra PKL!'
                          : _namaUsaha,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _jenisDagangan.isEmpty
                          ? 'Lengkapi kategori daganganmu.'
                          : _jenisDagangan,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.background.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status == 'DITERIMA'
                            ? Icons.verified_rounded
                            : status == 'DITOLAK'
                            ? Icons.cancel_rounded
                            : Icons.schedule_rounded,
                        color: colors.text,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          status,
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildLiveStatusChip(),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alamat Basecamp',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _alamatDomisili.isEmpty
                            ? 'Tambahkan alamat domisili agar pembeli tahu basecamp kamu.'
                            : _alamatDomisili,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _StatusChipColors _statusChipColors(String status) {
    switch (status) {
      case 'DITERIMA':
        return const _StatusChipColors(
          background: Color(0xFFB9F6CA),
          text: Color(0xFF1B5E20),
        );
      case 'DITOLAK':
        return const _StatusChipColors(
          background: Color(0xFFFFCDD2),
          text: Color(0xFFB71C1C),
        );
      default:
        return const _StatusChipColors(
          background: Color(0xFFFFF9C4),
          text: Color(0xFFF57F17),
        );
    }
  }

  Widget _buildLiveStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
        color: Colors.white.withValues(alpha: 0.12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusAktif ? Colors.greenAccent : Colors.white70,
              shape: BoxShape.circle,
              boxShadow: _statusAktif
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _statusAktif ? 'Live' : 'Offline',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildActionCard(
              icon: Icons.navigation_outlined,
              title: 'Update Lokasi',
              subtitle: 'Bagikan posisi terbaru',
              color: const Color(0xFFE6F6EE),
              iconColor: const Color(0xFF0D8A3A),
              onTap: _isNewProfile
                  ? _showProfileRequired
                  : () => _updateLocation(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildActionCard(
              icon: Icons.storefront_outlined,
              title: 'Edit Dagangan',
              subtitle: 'Nama usaha & menu',
              color: const Color(0xFFFFF2E0),
              iconColor: const Color(0xFFE65100),
              onTap: _openEditInfoPage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final isHovered = _hoveredActionCard == title;
    final isPressed = _pressedActionCard == title;
    final cardColor = isHovered ? _darkenColor(color, 0.05) : color;

    return AnimatedScale(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      scale: isPressed ? 0.96 : (isHovered ? 1.02 : 1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: isHovered
              ? [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            onTapDown: (_) {
              setState(() => _pressedActionCard = title);
            },
            onTapUp: (_) {
              setState(() => _pressedActionCard = null);
            },
            onTapCancel: () {
              setState(() => _pressedActionCard = null);
            },
            onHover: (hovering) {
              if (!mounted) return;
              setState(() {
                _hoveredActionCard = hovering ? title : null;
              });
            },
            splashColor: Colors.black.withValues(alpha: 0.05),
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minHeight: 160),
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.65),
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
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

  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  Widget _buildInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
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
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF0D8A3A),
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
                color: Colors.black.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
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
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.analytics_outlined,
                      color: Color(0xFF1976D2),
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
    final autoStatus = _locationTimer != null ? 'Aktif' : 'Nonaktif';
    final lastUpdate = _lastAutoUpdate != null
        ? _formatTime(_lastAutoUpdate!)
        : '--:--';

    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _buildStatBox(
              title: 'Live',
              subtitle: 'Tampilan',
              value: _liveViewsToday.toString(),
              color: const Color(0xFF5C6BC0),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildStatBox(
              title: 'Pencarian',
              subtitle: 'Muncul di hasil',
              value: _searchHitsToday.toString(),
              color: const Color(0xFF00ACC1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildStatBox(
              title: 'Auto-update',
              subtitle: 'Sinkronisasi',
              value: _autoUpdatesToday.toString(),
              color: const Color(0xFFFF8A00),
              footnote: '$autoStatus • Terakhir $lastUpdate',
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
              color: Colors.black.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (footnote != null) ...[
            const Spacer(),
            Text(
              footnote,
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLocationPanel() {
    final autoActive = _locationTimer != null;
    final lastUpdateLabel = _lastAutoUpdate != null
        ? 'Terakhir ${_formatTime(_lastAutoUpdate!)}'
        : 'Belum ada riwayat';
    final statusMessage =
        _locationMessage ??
        'Bagikan lokasi agar pembeli tahu posisi terbaru kamu.';

    return Material(
      color: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D8A3A).withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 16),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F9EF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.pin_drop_outlined,
                    color: Color(0xFF0D8A3A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kontrol Lokasi',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        lastUpdateLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildAutoStatusChip(autoActive),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              statusMessage,
              style: const TextStyle(color: Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _AnimatedButton(
                    child: ElevatedButton.icon(
                      onPressed: _isUpdatingLocation
                          ? null
                          : () {
                              if (_isNewProfile) {
                                _showProfileRequired();
                              } else {
                                _updateLocation();
                              }
                            },
                      icon: _isUpdatingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.navigation_outlined),
                      label: Text(
                        _isUpdatingLocation
                            ? 'Memperbarui...'
                            : 'Update Sekali',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AnimatedButton(
                    child: OutlinedButton.icon(
                      onPressed: _isNewProfile
                          ? _showProfileRequired
                          : _toggleAutoSync,
                      icon: Icon(
                        autoActive
                            ? Icons.pause_circle_filled
                            : Icons.autorenew,
                      ),
                      label: Text(autoActive ? 'Matikan Auto' : 'Auto-update'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoStatusChip(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE6F6EE) : const Color(0xFFFFF2E0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.offline_bolt_outlined,
            size: 16,
            color: active ? const Color(0xFF0D8A3A) : const Color(0xFFE65100),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Auto-update aktif' : 'Auto-update mati',
            style: TextStyle(
              color: active ? const Color(0xFF0D8A3A) : const Color(0xFFE65100),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                _buildActionRow(),
                const SizedBox(height: 18),
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
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Beranda PKL',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
            onPressed: _logout,
            tooltip: 'Keluar',
          ),
          const SizedBox(width: 8),
        ],
      ),
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

class _StatusChipColors {
  const _StatusChipColors({required this.background, required this.text});

  final Color background;
  final Color text;
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
