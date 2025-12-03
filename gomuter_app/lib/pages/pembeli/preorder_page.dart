import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';

enum _DPProofAction { uploadFile, manualUrl }

class PreOrderPage extends StatefulWidget {
  const PreOrderPage({super.key, required this.pklId, required this.pklName});

  final int pklId;
  final String pklName;

  @override
  State<PreOrderPage> createState() => _PreOrderPageState();
}

class _PreOrderPageState extends State<PreOrderPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _deskripsiController = TextEditingController();
  final _catatanController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _perkiraanTotalController = TextEditingController();

  late TabController _tabController;

  bool _isSubmitting = false;
  bool _isLoadingOrders = true;
  bool _isLoadingPKL = true;
  String? _error;
  String? _pklError;
  List<dynamic> _myOrders = [];
  Map<String, dynamic>? _pklDetail;
  int _dpAmount = 5000;
  int? _uploadingDPOrderId;

  // Theme colors
  static const Color _primaryColor = Color(0xFF0D7377);
  static const Color _accentColor = Color(0xFF14FFEC);
  static const Color _darkColor = Color(0xFF212121);
  static const Color _lightBg = Color(0xFFF5F7FA);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPKLDetail();
    _loadMyOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _deskripsiController.dispose();
    _catatanController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _perkiraanTotalController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    return TokenManager.getValidAccessToken();
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
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Upload Bukti Pembayaran',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Pilih metode untuk mengirim bukti DP',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildUploadOption(
                      icon: Icons.upload_file,
                      title: 'Upload File',
                      subtitle: 'Pilih gambar atau PDF dari perangkat',
                      onTap: () =>
                          Navigator.pop(context, _DPProofAction.uploadFile),
                    ),
                    const SizedBox(height: 12),
                    _buildUploadOption(
                      icon: Icons.link,
                      title: 'Masukkan URL',
                      subtitle: 'Gunakan link Google Drive atau lainnya',
                      onTap: () =>
                          Navigator.pop(context, _DPProofAction.manualUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
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

  Widget _buildUploadOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, Color(0xFF14A3A8)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _darkColor,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
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
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryColor, Color(0xFF14A3A8)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.link, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Kirim Bukti DP via URL',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _darkColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masukkan URL bukti pembayaran DP Anda',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'https://drive.google.com/...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.link, color: _primaryColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Batal',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_primaryColor, Color(0xFF14A3A8)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Kirim',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Bukti DP berhasil dikirim.'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      await _loadMyOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Gagal mengirim bukti DP: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
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

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 15, color: _darkColor),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryColor, Color(0xFF14A3A8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          labelStyle: TextStyle(color: Colors.grey.shade600),
          hintStyle: TextStyle(color: Colors.grey.shade400),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryColor, Color(0xFF14A3A8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pre-Order',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.pklName,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _isLoadingOrders
                      ? null
                      : () {
                          _loadPKLDetail();
                          _loadMyOrders();
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Ajukan pesanan untuk diambil di lokasi PKL. Jelaskan menu dan jam penjemputan agar PKL bisa menyiapkan.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
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

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [_primaryColor, Color(0xFF14A3A8)],
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        padding: const EdgeInsets.all(6),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.add_shopping_cart, size: 18),
                SizedBox(width: 8),
                Text('Buat Pesanan'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history, size: 18),
                const SizedBox(width: 8),
                const Text('Riwayat'),
                if (_myOrders.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _accentColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_myOrders.length}',
                      style: const TextStyle(
                        color: _darkColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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

  Widget _buildPreOrderForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernTextField(
              controller: _deskripsiController,
              label: 'Deskripsi Pesanan',
              hint: 'Contoh: Nasi goreng 2 porsi, mie ayam 1 porsi',
              icon: Icons.restaurant_menu,
              minLines: 2,
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Deskripsi pesanan wajib diisi.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _catatanController,
              label: 'Catatan Tambahan',
              hint: 'Contoh: Tidak pakai pedas, extra sayur',
              icon: Icons.note_alt_outlined,
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _addressController,
              label: 'Alamat Penjemputan',
              hint: 'Contoh: Depan Gedung A, lantai 1',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildModernTextField(
                    controller: _latController,
                    label: 'Latitude',
                    hint: '-6.xxx',
                    icon: Icons.my_location,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModernTextField(
                    controller: _lngController,
                    label: 'Longitude',
                    hint: '106.xxx',
                    icon: Icons.explore,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _perkiraanTotalController,
              label: 'Perkiraan Total Belanja',
              hint: 'Contoh: 50000',
              icon: Icons.payments_outlined,
              keyboardType: TextInputType.number,
              onChanged: (_) => _recalculateDP(),
            ),
            const SizedBox(height: 24),
            _buildDPCard(),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, Color(0xFF14A3A8)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitPreOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSubmitting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Mengirim...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.send_rounded, color: Colors.white),
                          SizedBox(width: 12),
                          Text(
                            'Kirim Pre-Order',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDPCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryColor.withValues(alpha: 0.1),
            _accentColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryColor, Color(0xFF14A3A8)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Informasi Pembayaran DP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Rp $_dpAmount',
                    style: const TextStyle(
                      color: _primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _isLoadingPKL
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: _primaryColor),
                    ),
                  )
                : _pklError != null
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade400),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _pklError!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  )
                : _pklDetail != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((_pklString('nama_rekening') ?? '').isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.credit_card,
                                color: _primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _pklString('nama_rekening')!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _darkColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if ((_pklString('qris_image_url') ?? '').isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/qris_logo.png',
                                      height: 24,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.qr_code_2,
                                        color: _primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Scan QRIS untuk bayar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _darkColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(16),
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Image.network(
                                    _pklString('qris_image_url')!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade100,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image,
                                            size: 48,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'QRIS tidak dapat dimuat',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if ((_pklString('qris_link') ?? '').isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.link, color: _primaryColor),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _pklString('qris_link')!,
                                  style: const TextStyle(
                                    color: _primaryColor,
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'PKL belum mengunggah QRIS. Hubungi PKL untuk info pembayaran.',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        const Text('Informasi PKL belum tersedia.'),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderHistory() {
    if (_isLoadingOrders) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(color: _primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Memuat riwayat...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadMyOrders,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (_myOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 56,
                  color: _primaryColor.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Belum ada pre-order',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _darkColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pre-order Anda untuk PKL ini akan muncul di sini',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () => _tabController.animateTo(0),
                icon: const Icon(Icons.add),
                label: const Text('Buat Pre-Order'),
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _myOrders.length,
      itemBuilder: (context, index) {
        final order = _myOrders[index] as Map<String, dynamic>;
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final deskripsi = order['deskripsi_pesanan'] as String? ?? '-';
    final status = order['status'] as String? ?? 'PENDING';
    final dpStatus = order['dp_status'] as String? ?? 'BELUM_BAYAR';
    final dpAmount = order['dp_amount'] as int? ?? 0;
    final buktiUrl = order['bukti_dp_url'] as String?;
    final catatan = order['catatan'] as String?;
    final createdAt = DateTime.tryParse(order['created_at'] as String? ?? '');
    final createdText = createdAt == null
        ? '-'
        : '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} • ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _statusIcon(status),
                    color: _statusColor(status),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #$orderId',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _darkColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        createdText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deskripsi,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _darkColor,
                  ),
                ),
                if (catatan != null && catatan.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notes,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            catatan,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // DP Info Row
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _primaryColor.withValues(alpha: 0.05),
                        _accentColor.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DP',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              'Rp $dpAmount',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _dpStatusColor(
                            dpStatus,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dpStatus.replaceAll('_', ' '),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _dpStatusColor(dpStatus),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (buktiUrl != null && buktiUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bukti DP sudah dikirim',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (dpStatus == 'BELUM_BAYAR' ||
                    dpStatus == 'MENUNGGU_KONFIRMASI') ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _uploadingDPOrderId == orderId
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Mengunggah...',
                                  style: TextStyle(
                                    color: _primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _showDPProofOptions(orderId),
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              dpStatus == 'BELUM_BAYAR'
                                  ? 'Upload Bukti DP'
                                  : 'Kirim Ulang Bukti',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primaryColor,
                              side: const BorderSide(color: _primaryColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'DITERIMA':
        return Icons.check_circle;
      case 'DITOLAK':
        return Icons.cancel;
      case 'SELESAI':
        return Icons.task_alt;
      default:
        return Icons.pending;
    }
  }

  Color _dpStatusColor(String status) {
    switch (status) {
      case 'LUNAS':
        return Colors.green;
      case 'MENUNGGU_KONFIRMASI':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildPreOrderForm(), _buildOrderHistory()],
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
