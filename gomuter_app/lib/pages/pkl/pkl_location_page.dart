import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/pkl_location_service.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:latlong2/latlong.dart';

class PklLocationPage extends StatefulWidget {
  const PklLocationPage({super.key});

  @override
  State<PklLocationPage> createState() => _PklLocationPageState();
}

class _PklLocationPageState extends State<PklLocationPage> {
  final ThemeManager _themeManager = ThemeManager();
  final PklLocationService _locationService = PklLocationService();

  bool _isLoading = true;
  String? _error;

  String _namaUsaha = '';
  String _jenisDagangan = '';
  String _alamatDomisili = '';
  String _statusVerifikasi = '';

  double? _latestLatitude;
  double? _latestLongitude;

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    _locationService.addListener(_onLocationServiceChanged);
    _loadInitial();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    _locationService.removeListener(_onLocationServiceChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onLocationServiceChanged() {
    if (mounted) setState(() {});
  }

  bool get _isVerifiedProfile {
    final status = _statusVerifikasi.isEmpty
        ? 'PENDING'
        : _statusVerifikasi.toUpperCase();
    return status == 'DITERIMA' || status == 'VERIFIED';
  }

  String get _verificationLockMessage {
    final status = _statusVerifikasi.isEmpty
        ? 'PENDING'
        : _statusVerifikasi.toUpperCase();
    if (status == 'DITOLAK') {
      return 'Profil usaha ditolak admin. Perbaiki data profil sebelum memperbarui lokasi.';
    }
    return 'Profil usaha masih menunggu verifikasi admin. Lokasi bisa diperbarui setelah disetujui.';
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _locationService.initialize();

      final token = await TokenManager.getValidAccessToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan. Silakan login ulang.');
      }

      final profile = await ApiService.getPKLProfile(token);
      if (profile != null) {
        _namaUsaha = (profile['nama_usaha'] as String?)?.trim() ?? '';
        _jenisDagangan = (profile['jenis_dagangan'] as String?)?.trim() ?? '';
        _alamatDomisili = (profile['alamat_domisili'] as String?)?.trim() ?? '';
        _statusVerifikasi = (profile['status_verifikasi'] ?? 'PENDING')
            .toString()
            .toUpperCase();

        _latestLatitude = (profile['latest_latitude'] as num?)?.toDouble();
        _latestLongitude = (profile['latest_longitude'] as num?)?.toDouble();
      }
    } catch (e) {
      _error = 'Gagal memuat halaman lokasi. $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(DateTime time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  Future<void> _runManualUpdate() async {
    if (!_isVerifiedProfile) {
      _showSnack(_verificationLockMessage);
      return;
    }

    final ok = await _locationService.updateLocation(showSnack: false);
    if (!mounted) return;
    if (ok) {
      _showSnack('Lokasi berhasil diperbarui.');
      return;
    }
    final reason = _locationService.lastError;
    _showSnack(
      reason == null || reason.isEmpty
          ? 'Gagal memperbarui lokasi.'
          : 'Gagal memperbarui lokasi. $reason',
    );
  }

  Future<void> _setAutoMode(bool enabled) async {
    if (enabled && !_isVerifiedProfile) {
      await _locationService.stopAutoSync(showSnack: false);
      if (!mounted) return;
      _showSnack(_verificationLockMessage);
      return;
    }

    if (enabled) {
      await _locationService.startAutoSync(showSnack: false);
      if (!mounted) return;
      _showSnack(
        _locationService.isAutoMode
            ? 'Mode otomatis diaktifkan.'
            : 'Izin lokasi belum aktif. Mode otomatis dibatalkan.',
      );
      return;
    }

    await _locationService.stopAutoSync(showSnack: false);
    if (!mounted) return;
    _showSnack('Mode otomatis dimatikan.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  PreferredSizeWidget _buildAppBar() {
    final borderColor = _themeManager.borderColor;

    return AppBar(
      title: const Text('Lokasi Saya'),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: borderColor),
      ),
    );
  }

  Widget _buildMapCard() {
    final isDark = _themeManager.isDarkMode;
    final cardColor = _themeManager.cardColor;
    final borderColor = _themeManager.borderColor;

    final overlayBase = isDark ? Colors.black : Colors.white;
    final overlayTextColor = _themeManager.textColor;

    final previewTint = Color.alphaBlend(
      _themeManager.pklPrimary.withValues(alpha: isDark ? 0.20 : 0.10),
      cardColor,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
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
              child: Container(
                constraints: const BoxConstraints(maxWidth: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _themeManager.pklPrimary.withValues(alpha: 0.90),
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
                            alpha: _jenisDagangan.isNotEmpty ? 0.85 : 0.75,
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
              right: 18,
              bottom: 18,
              child: ElevatedButton.icon(
                onPressed: _locationService.isUpdating
                    ? null
                    : _runManualUpdate,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  !_isVerifiedProfile
                      ? 'Terkunci'
                      : _locationService.isUpdating
                          ? 'Update...'
                          : 'Update',
                ),
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
          ],
        ),
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
                      Icons.my_location_rounded,
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

  Widget _buildUpdateMethodToggle() {
    final cardColor = _themeManager.cardColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final borderColor = _themeManager.borderColor;

    Widget buildItem({required String label, required bool selected}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(
                  _themeManager.accentGold.withValues(alpha: 0.18),
                  cardColor,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? textColor : mutedText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _themeManager.surfaceColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _locationService.isAutoMode
                  ? () => _setAutoMode(false)
                  : null,
              borderRadius: BorderRadius.circular(999),
              child: buildItem(
                label: 'Manual',
                selected: !_locationService.isAutoMode,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: !_locationService.isAutoMode
                  ? () => _setAutoMode(true)
                  : null,
              borderRadius: BorderRadius.circular(999),
              child: buildItem(
                label: 'Otomatis',
                selected: _locationService.isAutoMode,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualCard() {
    final isDark = _themeManager.isDarkMode;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;

    final lastUpdate = _locationService.lastUpdate;
    final lastUpdateLabel = lastUpdate != null
        ? '${_formatTime(lastUpdate)} WIB'
        : '-';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _themeManager.accentGold.withValues(alpha: 0.18),
                    _themeManager.cardColor,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.touch_app_outlined,
                  color: _themeManager.accentGold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pembaruan Manual',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hemat baterai. Tekan saat Anda pindah.',
                      style: TextStyle(
                        color: mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _locationService.isUpdating ? null : _runManualUpdate,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(
                _locationService.isUpdating
                    ? 'Memperbarui...'
                    : 'Perbarui Lokasi Sekarang',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Terakhir diperbarui : $lastUpdateLabel',
            style: TextStyle(color: mutedText, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCallout() {
    final isDark = _themeManager.isDarkMode;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _themeManager.pklPrimary.withValues(alpha: isDark ? 0.10 : 0.08),
          _themeManager.cardColor,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _themeManager.pklPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Lokasi Anda hanya akan terlihat oleh pembeli saat status dagangan Anda Aktif.',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationLockCard() {
    final isDark = _themeManager.isDarkMode;
    final borderColor = _themeManager.borderColor;
    final textColor = _themeManager.textColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _themeManager.accentGold.withValues(alpha: isDark ? 0.16 : 0.12),
          _themeManager.cardColor,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded, color: _themeManager.accentGold),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _verificationLockMessage,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _themeManager.backgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    _buildMapCard(),
                    const SizedBox(height: 18),
                    Text(
                      'Metode Pembaruan',
                      style: TextStyle(
                        color: _themeManager.textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pilih bagaimana pembeli melihat pergerakan Anda.',
                      style: TextStyle(
                        color: _themeManager.mutedTextColor,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_isVerifiedProfile) ...[
                      _buildVerificationLockCard(),
                    ] else ...[
                      _buildUpdateMethodToggle(),
                      const SizedBox(height: 14),
                      _buildManualCard(),
                      const SizedBox(height: 14),
                      _buildInfoCallout(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
