import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PklPreOrderPage extends StatefulWidget {
  const PklPreOrderPage({super.key});

  @override
  State<PklPreOrderPage> createState() => _PklPreOrderPageState();
}

class _PklPreOrderPageState extends State<PklPreOrderPage> {
  final ThemeManager _themeManager = ThemeManager();
  bool _isLoading = true;
  String? _error;
  List<dynamic> _orders = [];
  final Set<int> _updatingOrderIds = <int>{};
  int _tabIndex = 0; // 0: berlangsung, 1: selesai

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    _loadOrders();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _getToken() async {
    return TokenManager.getValidAccessToken();
  }

  Future<void> _loadOrders({bool retryOnAuthError = true}) async {
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

      final data = await ApiService.getPKLPreOrders(token: token);
      setState(() {
        _orders = data;
      });
    } catch (e) {
      if (retryOnAuthError && await _handleTokenError(e)) {
        await _loadOrders(retryOnAuthError: false);
        return;
      }
      setState(() {
        _error = 'Gagal memuat pre-order: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changeStatus(
    int preorderId,
    String status, {
    bool retryOnAuthError = true,
  }) async {
    setState(() {
      _updatingOrderIds.add(preorderId);
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan');
      }

      await ApiService.updatePreOrderStatus(
        token: token,
        preorderId: preorderId,
        status: status,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Status diubah menjadi $status')));

      await _loadOrders();
    } catch (e) {
      if (retryOnAuthError && await _handleTokenError(e)) {
        await _changeStatus(preorderId, status, retryOnAuthError: false);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memperbarui status: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingOrderIds.remove(preorderId);
        });
      }
    }
  }

  Future<void> _handleDPAction(
    int preorderId,
    bool approve, {
    bool retryOnAuthError = true,
  }) async {
    setState(() {
      _updatingOrderIds.add(preorderId);
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan');
      }

      await ApiService.verifyDPStatus(
        token: token,
        preorderId: preorderId,
        approve: approve,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'DP dikonfirmasi.' : 'DP ditolak dan diminta ulang.',
          ),
        ),
      );
      await _loadOrders();
    } catch (e) {
      if (retryOnAuthError && await _handleTokenError(e)) {
        await _handleDPAction(preorderId, approve, retryOnAuthError: false);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memproses DP: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingOrderIds.remove(preorderId);
        });
      }
    }
  }

  bool _isTokenExpiredError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('token_not_valid') ||
        message.contains('token is expired') ||
        message.contains('401');
  }

  Future<bool> _tryRefreshToken() async {
    final token = await TokenManager.forceRefreshAccessToken();
    return token != null;
  }

  Future<bool> _handleTokenError(Object error) async {
    if (!_isTokenExpiredError(error)) {
      return false;
    }

    final refreshed = await _tryRefreshToken();
    if (!refreshed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi berakhir. Silakan login ulang.')),
      );
    }
    return refreshed;
  }

  bool _looksLikeImage(String url) {
    final value = url.toLowerCase();
    return value.endsWith('.png') ||
        value.endsWith('.jpg') ||
        value.endsWith('.jpeg') ||
        value.endsWith('.gif') ||
        value.endsWith('.webp');
  }

  Future<void> _openDpLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL bukti DP tidak valid.')),
        );
      }
      return;
    }

    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuka tautan bukti DP.')),
      );
    }
  }

  Future<void> _showDpPreview(String url) async {
    if (!_looksLikeImage(url)) {
      await _openDpLink(url);
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final maxWidth = size.width * 0.9;
        final maxHeight = size.height * 0.7;
        return AlertDialog(
          contentPadding: const EdgeInsets.all(8),
          content: SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text('Gambar bukti tidak dapat dimuat.'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _openDpLink(url),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Buka di tab baru'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildDpSection(String proofUrl) {
    return [
      const SizedBox(height: 6),
      Text('Bukti DP: $proofUrl'),
      const SizedBox(height: 6),
      if (_looksLikeImage(proofUrl))
        GestureDetector(
          onTap: () => _showDpPreview(proofUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              proofUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Text('Pratinjau tidak tersedia'),
              ),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _showDpPreview(proofUrl),
          icon: Icon(
            _looksLikeImage(proofUrl) ? Icons.photo : Icons.open_in_new,
          ),
          label: Text(_looksLikeImage(proofUrl) ? 'Lihat bukti' : 'Buka bukti'),
        ),
      ),
    ];
  }

  List<String> _availableStatuses(String current) {
    final normalized = current.toUpperCase();
    if (normalized == 'PENDING') {
      return const ['DITERIMA', 'DITOLAK'];
    }
    if (normalized == 'DITERIMA') {
      return const ['SELESAI'];
    }
    // Final states: don't allow reopening.
    return const [];
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCDD2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFD32F2F),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPickupMapDialog(LatLng pos, String address) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lokasi Penjemputan'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(target: pos, zoom: 16),
                      markers: {
                        Marker(markerId: const MarkerId('pickup'), position: pos),
                      },
                      zoomControlsEnabled: false,
                      myLocationEnabled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(address, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _themeManager.accentSurfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 48,
              color: _themeManager.primaryGreen,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum ada permintaan pre-order.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Saat pembeli memesan, daftar akan tampil di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final pembeli = order['pembeli_username'] as String? ?? '-';
    final deskripsi = order['deskripsi_pesanan'] as String? ?? '-';
    final catatan = order['catatan'] as String?;
    final pickupAddress = order['pickup_address'] as String? ?? '-';
    final latitude = order['pickup_latitude'];
    final longitude = order['pickup_longitude'];
    final status = order['status'] as String? ?? 'PENDING';
    final dpStatus = order['dp_status'] as String? ?? 'BELUM_BAYAR';
    final dpAmount = order['dp_amount'] as int? ?? 0;
    final buktiDp = order['bukti_dp_url'] as String?;
    final orderId = (order['id'] as num?)?.toInt() ?? -1;
    final isUpdating = orderId != -1 && _updatingOrderIds.contains(orderId);
    final createdAt = DateTime.tryParse(order['created_at'] as String? ?? '');
    final createdLabel = createdAt == null
        ? '-'
        : '${createdAt.day.toString().padLeft(2, '0')}/'
              '${createdAt.month.toString().padLeft(2, '0')} '
              '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: _statusColor(status).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
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
                      Icons.person_rounded,
                      color: Color(0xFF0D8A3A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pembeli,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dibuat: $createdLabel',
                          style: TextStyle(
                            color: _themeManager.mutedTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _statusColor(status).withValues(alpha: 0.15),
                          _statusColor(status).withValues(alpha: 0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _statusColor(status).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _themeManager.surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _themeManager.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.description_rounded,
                          size: 18,
                          color: _themeManager.mutedTextColor,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Detail Pesanan',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      deskripsi,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    if (catatan != null && catatan.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9E6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.note_alt_rounded,
                              size: 18,
                              color: Color(0xFFF57C00),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Catatan Pembeli',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Color(0xFFF57C00),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    catatan,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: (latitude != null && longitude != null)
                    ? () {
                        final lat = (latitude as num).toDouble();
                        final lng = (longitude as num).toDouble();
                        _showPickupMapDialog(LatLng(lat, lng), pickupAddress);
                      }
                    : null,
                child: _buildInfoRow(
                  Icons.location_on_rounded,
                  'Alamat pickup',
                  pickupAddress,
                ),
              ),
              if (latitude != null && longitude != null)
                _buildInfoRow(
                  Icons.pin_drop_rounded,
                  'Koordinat',
                  '$latitude / $longitude',
                ),
              _buildInfoRow(Icons.payments_rounded, 'DP', 'Rp$dpAmount'),
              _buildInfoRow(
                Icons.account_balance_wallet_rounded,
                'Status DP',
                dpStatus,
              ),
              if (buktiDp != null && buktiDp.isNotEmpty)
                ..._buildDpSection(buktiDp),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (status == 'PENDING') ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (isUpdating || orderId == -1)
                            ? null
                            : () => _changeStatus(orderId, 'DITOLAK'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Tolak',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (isUpdating || orderId == -1)
                            ? null
                            : () => _changeStatus(orderId, 'DITERIMA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _themeManager.accentGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Terima Pesanan',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else if (status == 'DITERIMA') ...[
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (isUpdating || orderId == -1)
                            ? null
                            : () => _changeStatus(orderId, 'SELESAI'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _themeManager.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Selesaikan Pesanan',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Builder(
                    builder: (context) {
                      final options = _availableStatuses(status);
                      if (options.isEmpty) return const SizedBox.shrink();
                      return SizedBox(
                        width: 44,
                        height: 44,
                        child: PopupMenuButton<String>(
                          enabled: !isUpdating && orderId != -1,
                          onSelected: (value) => _changeStatus(orderId, value),
                          itemBuilder: (context) {
                            return options
                                .map(
                                  (statusOption) => PopupMenuItem(
                                    value: statusOption,
                                    child: Text(statusOption),
                                  ),
                                )
                                .toList();
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _themeManager.surfaceColor,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: _themeManager.borderColor),
                            ),
                            child: isUpdating
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Icon(
                                    Icons.more_horiz_rounded,
                                    color: _themeManager.mutedTextColor,
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              if (dpStatus == 'MENUNGGU_KONFIRMASI')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed:
                            isUpdating
                            ? null
                            : () => _handleDPAction(orderId, true),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0D8A3A),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text(
                          'DP valid',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed:
                            isUpdating
                            ? null
                            : () => _handleDPAction(orderId, false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD32F2F),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.cancel_rounded, size: 18),
                        label: const Text(
                          'Tolak DP',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final mutedText = _themeManager.mutedTextColor;
    final textColor = _themeManager.textColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: mutedText),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
              color: mutedText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _themeManager.backgroundColor;
    final textColor = _themeManager.textColor;
    final borderColor = _themeManager.borderColor;

    final orders = _orders.whereType<Map<String, dynamic>>().toList();
    bool isDone(Map<String, dynamic> order) {
      final status = (order['status'] as String?)?.toUpperCase() ?? 'PENDING';
      return status == 'SELESAI' || status == 'DITOLAK';
    }

    final berlangsung = orders.where((o) => !isDone(o)).toList();
    final selesai = orders.where(isDone).toList();
    final filtered = _tabIndex == 0 ? berlangsung : selesai;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: textColor,
        title: const Text('Daftar Pre-Order'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadOrders,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  children: [
                    const SizedBox(height: 12),
                    _buildSegmentedTabs(
                      berlangsungCount: berlangsung.length,
                      selesaiCount: selesai.length,
                    ),
                    const SizedBox(height: 14),
                    if (_error != null) _buildErrorBanner(_error!),
                    if (filtered.isEmpty)
                      _buildEmptyState()
                    else
                      ...filtered.map<Widget>((order) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildOrderCard(order),
                        );
                      }),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const PklBottomNavBar(current: PklNavItem.orders),
    );
  }

  Widget _buildSegmentedTabs({
    required int berlangsungCount,
    required int selesaiCount,
  }) {
    final border = _themeManager.borderColor;
    final card = _themeManager.cardColor;
    final activeText = _themeManager.textColor;
    final inactiveText = _themeManager.mutedTextColor;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentPill(
              label: 'Berlangsung',
              badge: berlangsungCount > 0 ? '$berlangsungCount' : null,
              selected: _tabIndex == 0,
              onTap: () => setState(() => _tabIndex = 0),
              themeManager: _themeManager,
              activeText: activeText,
              inactiveText: inactiveText,
            ),
          ),
          Expanded(
            child: _SegmentPill(
              label: 'Selesai',
              badge: selesaiCount > 0 ? '$selesaiCount' : null,
              selected: _tabIndex == 1,
              onTap: () => setState(() => _tabIndex = 1),
              themeManager: _themeManager,
              activeText: activeText,
              inactiveText: inactiveText,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'DITERIMA':
        return Colors.green;
      case 'DITOLAK':
        return Colors.red;
      case 'SELESAI':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.themeManager,
    required this.activeText,
    required this.inactiveText,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeManager themeManager;
  final Color activeText;
  final Color inactiveText;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? themeManager.surfaceColor : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? activeText : inactiveText,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? themeManager.accentGold
                      : themeManager.accentGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: selected ? Colors.white : themeManager.accentGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
