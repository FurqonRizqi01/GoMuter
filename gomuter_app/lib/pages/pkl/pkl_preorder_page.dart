import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
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
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null) {
      return false;
    }

    try {
      final result = await ApiService.refreshAccessToken(
        refreshToken: refreshToken,
      );
      final newAccess = result['access'] as String?;
      if (newAccess == null) {
        return false;
      }

      await prefs.setString('access_token', newAccess);
      final newRefresh = result['refresh'] as String?;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await prefs.setString('refresh_token', newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
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
      SelectableText('Bukti DP: $proofUrl'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
          : _error != null
          ? Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            )
          : _orders.isEmpty
          ? const Center(child: Text('Belum ada permintaan pre-order.'))
          : RefreshIndicator(
              onRefresh: _loadOrders,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (context, index) {
                  final order = _orders[index] as Map<String, dynamic>;
                  final pembeli = order['pembeli_username'] as String? ?? '-';
                  final deskripsi =
                      order['deskripsi_pesanan'] as String? ?? '-';
                  final catatan = order['catatan'] as String?;
                  final pickupAddress =
                      order['pickup_address'] as String? ?? '-';
                  final latitude = order['pickup_latitude'];
                  final longitude = order['pickup_longitude'];
                  final status = order['status'] as String? ?? 'PENDING';
                  final dpStatus =
                      order['dp_status'] as String? ?? 'BELUM_BAYAR';
                  final dpAmount = order['dp_amount'] as int? ?? 0;
                  final buktiDp = order['bukti_dp_url'] as String?;
                  final createdAt = DateTime.tryParse(
                    order['created_at'] as String? ?? '',
                  );
                  final createdLabel = createdAt == null
                      ? '-'
                      : '${createdAt.day.toString().padLeft(2, '0')}/'
                            '${createdAt.month.toString().padLeft(2, '0')} '
                            '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  pembeli,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(status),
                                backgroundColor: _statusColor(
                                  status,
                                ).withOpacity(0.2),
                                labelStyle: TextStyle(
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(deskripsi),
                          const SizedBox(height: 6),
                          Text('Dibuat: $createdLabel'),
                          if (catatan != null && catatan.isNotEmpty)
                            Text('Catatan pembeli: $catatan'),
                          const SizedBox(height: 6),
                          Text('Alamat pickup: $pickupAddress'),
                          if (latitude != null && longitude != null)
                            Text(
                              'Koordinat: ${latitude.toString()} / ${longitude.toString()}',
                            ),
                          const SizedBox(height: 6),
                          Text('DP: Rp$dpAmount • Status DP: $dpStatus'),
                          if (buktiDp != null && buktiDp.isNotEmpty)
                            ..._buildDpSection(buktiDp),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: PopupMenuButton<String>(
                              enabled: !_updatingOrderIds.contains(
                                order['id'] as int,
                              ),
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
                              child:
                                  _updatingOrderIds.contains(order['id'] as int)
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Chip(label: Text('Ubah status')),
                            ),
                          ),
                          if (dpStatus == 'MENUNGGU_KONFIRMASI')
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed:
                                      _updatingOrderIds.contains(
                                        order['id'] as int,
                                      )
                                      ? null
                                      : () => _handleDPAction(
                                          order['id'] as int,
                                          true,
                                        ),
                                  icon: const Icon(Icons.verified),
                                  label: const Text('DP valid'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed:
                                      _updatingOrderIds.contains(
                                        order['id'] as int,
                                      )
                                      ? null
                                      : () => _handleDPAction(
                                          order['id'] as int,
                                          false,
                                        ),
                                  icon: const Icon(Icons.highlight_off),
                                  label: const Text('Tolak DP'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
