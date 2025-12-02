import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pkl/pkl_chat_list_page.dart';
import 'package:gomuter_app/pages/pkl/pkl_edit_info_page.dart';
import 'package:gomuter_app/pages/pkl/pkl_payment_settings_page.dart';
import 'package:gomuter_app/pages/pkl/pkl_preorder_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String _namaUsaha = '';
  String _jenisDagangan = '';
  String _jamOperasional = '';
  String _alamatDomisili = '';
  String _statusVerifikasi = '';

  String? _locationMessage;
  Timer? _locationTimer;
  DateTime? _lastAutoUpdate;
  int _selectedNavIndex = 0;
  int _liveViewsToday = 0;
  int _searchHitsToday = 0;
  int _autoUpdatesToday = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
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

  void _openEditInfoPage() async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PklEditInfoPage()));
    if (updated == true) {
      _loadProfile();
    }
  }

  void _openPaymentSettingsPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PklPaymentSettingsPage()));
  }

  void _openChatList() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PklChatListPage()));
  }

  void _openPreOrderPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PklPreOrderPage()));
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
    const overlap = 42.0;
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D8A3A), Color(0xFF35C481)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D8A3A).withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _namaUsaha.isEmpty ? 'Selamat datang, Mitra PKL!' : _namaUsaha,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _jenisDagangan.isEmpty
                ? 'Lengkapi kategori daganganmu.'
                : _jenisDagangan,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Text(
                  'Status Verifikasi: $status',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildLiveStatusChip(),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.location_pin, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _alamatDomisili.isEmpty
                        ? 'Tambahkan alamat domisili agar pembeli tahu basecamp kamu.'
                        : _alamatDomisili,
                    style: const TextStyle(color: Colors.white, height: 1.3),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
        color: Colors.white.withOpacity(0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _statusAktif
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            _statusAktif ? 'Live di GoMuter' : 'Belum Live',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
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
    final cardColor = isHovered ? _darkenColor(color, 0.08) : color;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      onHover: (hovering) {
        if (!mounted) return;
        setState(() {
          _hoveredActionCard = hovering ? title : null;
        });
      },
      splashColor: Colors.black.withOpacity(0.08),
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isHovered
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informasi Dagangan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
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
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistik Hari Ini',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            _buildStatsRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final autoStatus = _locationTimer != null ? 'Aktif' : 'Nonaktif';
    final lastUpdate = _lastAutoUpdate != null
        ? _formatTime(_lastAutoUpdate!)
        : '--:--';

    return Row(
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
      padding: const EdgeInsets.all(18),
      constraints: const BoxConstraints(minHeight: 150),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Text(
              footnote,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
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
      elevation: 12,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 12),
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
                      _isUpdatingLocation ? 'Memperbarui...' : 'Update Sekali',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isNewProfile
                        ? _showProfileRequired
                        : _toggleAutoSync,
                    icon: Icon(
                      autoActive ? Icons.pause_circle_filled : Icons.autorenew,
                    ),
                    label: Text(autoActive ? 'Matikan Auto' : 'Auto-update'),
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

  Widget _buildBottomNavBar() {
    final items = [
      _BottomNavItem(
        label: 'Informasi Dagangan',
        icon: Icons.storefront,
        onTap: () {
          setState(() => _selectedNavIndex = 0);
          _openEditInfoPage();
        },
      ),
      _BottomNavItem(
        label: 'Pembayaran QRIS',
        icon: Icons.qr_code_2,
        onTap: () {
          setState(() => _selectedNavIndex = 1);
          _openPaymentSettingsPage();
        },
      ),
      _BottomNavItem(
        label: 'Pesan Pembeli',
        icon: Icons.chat_bubble_outline,
        onTap: () {
          setState(() => _selectedNavIndex = 2);
          _openChatList();
        },
      ),
      _BottomNavItem(
        label: 'Kelola Pre-Order',
        icon: Icons.receipt_long_outlined,
        onTap: () {
          setState(() => _selectedNavIndex = 3);
          _openPreOrderPage();
        },
      ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isActive = _selectedNavIndex == index;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: item.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFE8F9EF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isActive
                            ? const Color(0xFF0D8A3A)
                            : Colors.black54,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isActive
                              ? const Color(0xFF0D8A3A)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroSection(),
          const SizedBox(height: 32),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadProfile,
                child: bodyContent,
              ),
            ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }
}

class _BottomNavItem {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _StatusChipColors {
  const _StatusChipColors({required this.background, required this.text});

  final Color background;
  final Color text;
}
