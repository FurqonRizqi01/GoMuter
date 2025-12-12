import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';
import 'package:url_launcher/url_launcher.dart';

class PklPreOrderPage extends StatefulWidget {
  const PklPreOrderPage({super.key});

  @override
  State<PklPreOrderPage> createState() => _PklPreOrderPageState();
}

class _PklPreOrderPageState extends State<PklPreOrderPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _orders = [];
  final Set<int> _updatingOrderIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadOrders();
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
    const all = ['DITERIMA', 'DITOLAK', 'SELESAI'];
    return all.where((item) => item != current).toList();
  }

  Widget _buildHeroBanner() {
    return Container(
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
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF0D8A3A).withValues(alpha: 0.1),
            blurRadius: 48,
            offset: const Offset(0, 24),
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
                  Icons.shopping_bag_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Kelola Pre-Order',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Respon cepat permintaan pembeli untuk menjaga kepercayaan.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
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

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
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
              color: const Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 48,
              color: Color(0xFF0D8A3A),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Belum ada permintaan pre-order.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Saat pembeli memesan, daftar akan tampil di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.6),
              fontSize: 14,
              height: 1.4,
            ),
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
        color: Colors.white,
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
                            color: Colors.black.withValues(alpha: 0.5),
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
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.description_rounded,
                          size: 18,
                          color: Colors.black.withValues(alpha: 0.6),
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
              _buildInfoRow(
                Icons.location_on_rounded,
                'Alamat pickup',
                pickupAddress,
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PopupMenuButton<String>(
                    enabled: !_updatingOrderIds.contains(order['id'] as int),
                    onSelected: (value) =>
                        _changeStatus(order['id'] as int, value),
                    itemBuilder: (context) {
                      return _availableStatuses(status)
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
                    child: _updatingOrderIds.contains(order['id'] as int)
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D8A3A),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0D8A3A,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Ubah Status',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                            _updatingOrderIds.contains(order['id'] as int)
                            ? null
                            : () => _handleDPAction(order['id'] as int, true),
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
                            _updatingOrderIds.contains(order['id'] as int)
                            ? null
                            : () => _handleDPAction(order['id'] as int, false),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('Permintaan Pre-Order'),
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
                    _buildHeroBanner(),
                    const SizedBox(height: 18),
                    if (_error != null) _buildErrorBanner(_error!),
                    if (_orders.isEmpty)
                      _buildEmptyState()
                    else
                      ..._orders.map<Widget>(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildOrderCard(order as Map<String, dynamic>),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const PklBottomNavBar(current: PklNavItem.preorder),
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
