import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _DPProofAction { uploadFile, manualUrl }

class PreOrderPage extends StatefulWidget {
  const PreOrderPage({super.key, required this.pklId, required this.pklName});

  final int pklId;
  final String pklName;

  @override
  State<PreOrderPage> createState() => _PreOrderPageState();
}

class _PreOrderPageState extends State<PreOrderPage> {
  final _formKey = GlobalKey<FormState>();
  final _deskripsiController = TextEditingController();
  final _catatanController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _perkiraanTotalController = TextEditingController();

  bool _isSubmitting = false;
  bool _isLoadingOrders = true;
  bool _isLoadingPKL = true;
  String? _error;
  String? _pklError;
  List<dynamic> _myOrders = [];
  Map<String, dynamic>? _pklDetail;
  int _dpAmount = 5000;
  int? _uploadingDPOrderId;

  @override
  void initState() {
    super.initState();
    _loadPKLDetail();
    _loadMyOrders();
  }

  @override
  void dispose() {
    _deskripsiController.dispose();
    _catatanController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _perkiraanTotalController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> _loadPKLDetail() async {
    setState(() {
      _isLoadingPKL = true;
      _pklError = null;
    });

    try {
      final detail = await ApiService.getPKLDetail(widget.pklId);
      setState(() {
        _pklDetail = Map<String, dynamic>.from(detail);
      });
    } catch (e) {
      setState(() {
        _pklError = 'Gagal memuat info PKL: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPKL = false;
        });
      }
    }
  }

  String? _pklString(String key) {
    final value = _pklDetail?[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  Future<void> _loadMyOrders({bool retryOnAuthError = true}) async {
    setState(() {
      _isLoadingOrders = true;
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

      final data = await ApiService.getMyPreOrders(token: token);
      final filtered = data.where((dynamic item) {
        final preorder = item as Map<String, dynamic>;
        return (preorder['pkl'] as int?) == widget.pklId;
      }).toList();

      setState(() {
        _myOrders = filtered;
      });
    } catch (e) {
      if (retryOnAuthError && await _handleTokenError(e)) {
        await _loadMyOrders(retryOnAuthError: false);
        return;
      }
      setState(() {
        _error = 'Gagal memuat pre-order: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOrders = false;
        });
      }
    }
  }

  double? _parseCoordinate(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.trim());
  }

  double? _parseTotal(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.trim());
  }

  void _recalculateDP() {
    final total = _parseTotal(_perkiraanTotalController.text);
    if (total == null) {
      setState(() {
        _dpAmount = 5000;
      });
      return;
    }

    final computed = (total * 0.2).round();
    setState(() {
      _dpAmount = computed < 5000 ? 5000 : computed;
    });
  }

  Future<void> _submitPreOrder({bool retryOnAuthError = true}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan.');
      }

      final latitude = _parseCoordinate(_latController.text);
      final longitude = _parseCoordinate(_lngController.text);
      final perkiraanTotal = _parseTotal(_perkiraanTotalController.text);

      await ApiService.createPreOrder(
        token: token,
        pklId: widget.pklId,
        deskripsiPesanan: _deskripsiController.text.trim(),
        catatan: _catatanController.text.trim().isEmpty
            ? null
            : _catatanController.text.trim(),
        pickupAddress: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        pickupLatitude: latitude,
        pickupLongitude: longitude,
        dpAmount: _dpAmount,
        perkiraanTotal: perkiraanTotal,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pre-order berhasil dikirim.')),
      );

      _deskripsiController.clear();
      _catatanController.clear();
      _addressController.clear();
      _latController.clear();
      _lngController.clear();
      _perkiraanTotalController.clear();
      setState(() {
        _dpAmount = 5000;
      });

      await _loadMyOrders();
    } catch (e) {
      if (retryOnAuthError && await _handleTokenError(e)) {
        await _submitPreOrder(retryOnAuthError: false);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuat pre-order: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _showDPProofOptions(int preorderId) async {
    final action = await showModalBottomSheet<_DPProofAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload file bukti DP'),
              subtitle: const Text('Pilih file dari perangkat Anda'),
              onTap: () => Navigator.pop(context, _DPProofAction.uploadFile),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Masukkan URL bukti DP'),
              subtitle: const Text('Gunakan link Google Drive / lainnya'),
              onTap: () => Navigator.pop(context, _DPProofAction.manualUrl),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _DPProofAction.uploadFile:
        await _pickAndUploadDPFile(preorderId);
        break;
      case _DPProofAction.manualUrl:
        await _promptManualDPUrl(preorderId);
        break;
    }
  }

  Future<void> _pickAndUploadDPFile(int preorderId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final fileBytes = file.bytes;

      if (fileBytes == null) {
        throw Exception('File tidak dapat dibaca. Silakan coba lagi.');
      }

      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan.');
      }

      if (mounted) {
        setState(() {
          _uploadingDPOrderId = preorderId;
        });
      }

      final uploadedUrl = await ApiService.uploadDPFile(
        token: token,
        fileName: file.name,
        fileBytes: fileBytes,
      );

      await ApiService.uploadDPProof(
        token: token,
        preorderId: preorderId,
        buktiUrl: uploadedUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bukti DP berhasil diunggah.')),
      );
      await _loadMyOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mengunggah bukti DP: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _uploadingDPOrderId = null;
        });
      }
    }
  }

  Future<void> _promptManualDPUrl(int preorderId) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kirim Bukti DP via URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'URL bukti pembayaran',
            hintText: 'Contoh: https://drive.google.com/...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.isEmpty) {
      return;
    }

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan.');
      }

      await ApiService.uploadDPProof(
        token: token,
        preorderId: preorderId,
        buktiUrl: result,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bukti DP berhasil dikirim.')),
      );
      await _loadMyOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mengirim bukti DP: $e')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pre-Order - ${widget.pklName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingOrders
                ? null
                : () {
                    _loadPKLDetail();
                    _loadMyOrders();
                  },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ajukan pesanan untuk diambil di lokasi PKL ini. Jelaskan menu dan jam penjemputan agar PKL bisa menyiapkan pesanan.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _deskripsiController,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi Pesanan',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 2,
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Deskripsi pesanan wajib diisi.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _catatanController,
                    decoration: const InputDecoration(
                      labelText: 'Catatan tambahan (opsional)',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Alamat penjemputan (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Latitude (opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lngController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Longitude (opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _perkiraanTotalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Perkiraan total belanja (opsional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recalculateDP(),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.teal.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DP yang harus dibayar: Rp$_dpAmount',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (_isLoadingPKL)
                            const LinearProgressIndicator()
                          else if (_pklError != null)
                            Text(
                              _pklError!,
                              style: const TextStyle(color: Colors.red),
                            )
                          else if (_pklDetail != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((_pklString('nama_rekening') ?? '')
                                    .isNotEmpty)
                                  Text(
                                    'Rekening: ${_pklString('nama_rekening')}',
                                  ),
                                if ((_pklString('qris_image_url') ?? '')
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Image.network(
                                        _pklString('qris_image_url')!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                              child: Text(
                                                'QRIS tidak dapat dimuat',
                                              ),
                                            ),
                                      ),
                                    ),
                                  )
                                else if ((_pklString('qris_link') ?? '')
                                    .isNotEmpty)
                                  Text('QRIS: ${_pklString('qris_link')}')
                                else
                                  const Text('PKL belum mengunggah QRIS.'),
                              ],
                            )
                          else
                            const Text('Informasi PKL belum tersedia.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitPreOrder,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        _isSubmitting ? 'Mengirim...' : 'Kirim Pre-Order',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Riwayat pre-order Anda',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _isLoadingOrders ? null : _loadMyOrders,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Muat ulang'),
                ),
              ],
            ),
            if (_isLoadingOrders)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            else if (_myOrders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Belum ada pre-order untuk PKL ini.'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myOrders.length,
                itemBuilder: (context, index) {
                  final order = _myOrders[index] as Map<String, dynamic>;
                  final orderId = order['id'] as int;
                  final deskripsi =
                      order['deskripsi_pesanan'] as String? ?? '-';
                  final status = order['status'] as String? ?? 'PENDING';
                  final dpStatus =
                      order['dp_status'] as String? ?? 'BELUM_BAYAR';
                  final dpAmount = order['dp_amount'] as int? ?? 0;
                  final buktiUrl = order['bukti_dp_url'] as String?;
                  final catatan = order['catatan'] as String?;
                  final createdAt = DateTime.tryParse(
                    order['created_at'] as String? ?? '',
                  );
                  final createdText = createdAt == null
                      ? '-'
                      : '${createdAt.day.toString().padLeft(2, '0')}/'
                            '${createdAt.month.toString().padLeft(2, '0')} '
                            '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  deskripsi,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Dibuat: $createdText'),
                                if (catatan != null && catatan.isNotEmpty)
                                  Text('Catatan: $catatan'),
                                Text('DP: Rp$dpAmount • Status DP: $dpStatus'),
                                if (buktiUrl != null && buktiUrl.isNotEmpty)
                                  Text(
                                    'Bukti: $buktiUrl',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
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
                              if (dpStatus == 'BELUM_BAYAR' ||
                                  dpStatus == 'MENUNGGU_KONFIRMASI')
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton(
                                    onPressed: _uploadingDPOrderId == orderId
                                        ? null
                                        : () => _showDPProofOptions(orderId),
                                    child: _uploadingDPOrderId == orderId
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Mengunggah...'),
                                            ],
                                          )
                                        : Text(
                                            dpStatus == 'BELUM_BAYAR'
                                                ? 'Upload bukti DP'
                                                : 'Kirim ulang bukti',
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
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
