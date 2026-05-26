import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';

enum _DPProofAction { uploadFile, manualUrl }

class PreOrderPage extends StatefulWidget {
  const PreOrderPage({
    super.key,
    required this.pklId,
    required this.pklName,
    this.initialCart,
  });

  final int pklId;
  final String pklName;
  final List<Map<String, dynamic>>? initialCart;

  @override
  State<PreOrderPage> createState() => _PreOrderPageState();
}

class _PreOrderPageState extends State<PreOrderPage>
    with SingleTickerProviderStateMixin {
  final ThemeManager _themeManager = ThemeManager();

  final _formKey = GlobalKey<FormState>();
  final _catatanController = TextEditingController();
  final _addressController = TextEditingController();
  final _searchController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  // Cart: productId → quantity
  final Map<int, int> _cart = {};

  // Map related
  final MapController _mapController = MapController();
  LatLng? _selectedLatLng;
  LatLng? _initialCenter;
  double _initialZoom = 12;
  bool _mapLoading = true;

  static const LatLng _fallbackCenter = LatLng(-6.200000, 106.816666);

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

  Color get _primaryColor => _themeManager.primaryOrange;
  Color get _secondaryColor => _themeManager.secondaryOrange;
  Color get _accentColor => _themeManager.orangeSurfaceColor;
  Color get _darkColor => _themeManager.textColor;
  Color get _mutedTextColor => _themeManager.mutedTextColor;
  Color get _borderColor => _themeManager.borderColor;

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    _tabController = TabController(length: 2, vsync: this);
    // Populate cart from initial data
    if (widget.initialCart != null) {
      for (final item in widget.initialCart!) {
        final id = item['product_id'] as int?;
        final qty = item['quantity'] as int? ?? 1;
        if (id != null) _cart[id] = qty;
      }
    }
    _initMap();
    _loadPKLDetail();
    _loadMyOrders();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    _tabController.dispose();
    _catatanController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
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
      _recalculateDP();
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

  int get _cartTotal {
    final products = _availableProducts;
    int total = 0;
    for (final entry in _cart.entries) {
      final product = products.firstWhere(
        (p) => p['id'] == entry.key,
        orElse: () => <String, dynamic>{},
      );
      total += ((product['price'] as num?)?.toInt() ?? 0) * entry.value;
    }
    return total;
  }

  int get _cartItemCount {
    int count = 0;
    for (final qty in _cart.values) {
      count += qty;
    }
    return count;
  }

  List<Map<String, dynamic>> get _availableProducts {
    final productsRaw = _pklDetail?['products'];
    if (productsRaw is! List) return [];
    return productsRaw
        .whereType<Map<String, dynamic>>()
        .where((p) => p['is_available'] == true)
        .toList();
  }

  void _recalculateDP() {
    final total = _cartTotal;
    setState(() {
      _dpAmount = total > 0 ? (total * 0.2).round().clamp(5000, total) : 5000;
    });
  }

  Future<void> _initMap() async {
    // Always show a map quickly (avoid infinite spinner on web/permission issues).
    if (mounted) {
      setState(() {
        _initialCenter ??= _fallbackCenter;
        _initialZoom = 12;
        _mapLoading = false;
      });
    }

    try {
      // On web, geolocation may hang while waiting for permission.
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission().timeout(
          const Duration(seconds: 4),
          onTimeout: () => LocationPermission.denied,
        );
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        pos = null;
      }

      if (pos == null) return;

      final center = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _initialCenter = center;
        _initialZoom = 16;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(center, 16);
      });
    } catch (_) {
      // keep fallback
    }
  }

  Future<LatLng?> _geocodeViaNominatim(String query) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${Uri.encodeComponent(query)}',
    );
    final response = await http.get(
      url,
      headers: const {
        'User-Agent': 'GoMuter/1.0 (flutter)',
      },
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;
    final first = decoded.first;
    if (first is! Map) return null;
    final latStr = first['lat']?.toString();
    final lonStr = first['lon']?.toString();
    if (latStr == null || lonStr == null) return null;
    final lat = double.tryParse(latStr);
    final lon = double.tryParse(lonStr);
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  Future<String?> _reverseGeocodeViaNominatim(LatLng pos) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}',
    );
    final response = await http.get(
      url,
      headers: const {
        'User-Agent': 'GoMuter/1.0 (flutter)',
      },
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final name = decoded['display_name']?.toString();
    if (name == null || name.trim().isEmpty) return null;
    return name.trim();
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    try {
      LatLng? latlng;
      if (kIsWeb) {
        latlng = await _geocodeViaNominatim(query);
      } else {
        final results = await locationFromAddress(query);
        if (results.isNotEmpty) {
          final r = results.first;
          latlng = LatLng(r.latitude, r.longitude);
        }
      }

      // Fallback (also covers unexpected plugin failures).
      latlng ??= await _geocodeViaNominatim(query);

      if (latlng == null) {
        throw Exception('Alamat tidak ditemukan');
      }
      _selectedLatLng = latlng;
      _addressController.text = query;
      _latController.text = latlng.latitude.toString();
      _lngController.text = latlng.longitude.toString();
      _mapController.move(latlng, 16);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menemukan alamat: $e')),
        );
      }
    }
  }

  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      if (kIsWeb) {
        return await _reverseGeocodeViaNominatim(pos);
      }

      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isEmpty) {
        return await _reverseGeocodeViaNominatim(pos);
      }
      final p = placemarks.first;
      final parts = <String>[];
      if (p.street != null && p.street!.isNotEmpty) {
        parts.add(p.street!);
      }
      if (p.subLocality != null && p.subLocality!.isNotEmpty) {
        parts.add(p.subLocality!);
      }
      if (p.locality != null && p.locality!.isNotEmpty) {
        parts.add(p.locality!);
      }
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
        parts.add(p.administrativeArea!);
      }
      final built = parts.join(', ');
      if (built.trim().isNotEmpty) {
        return built;
      }
      return await _reverseGeocodeViaNominatim(pos);
    } catch (_) {
      return await _reverseGeocodeViaNominatim(pos);
    }
  }

  Future<void> _onMapTap(LatLng pos) async {
    _selectedLatLng = pos;
    _latController.text = pos.latitude.toString();
    _lngController.text = pos.longitude.toString();
    final addr = await _reverseGeocode(pos);
    if (addr != null && addr.isNotEmpty) {
      _addressController.text = addr;
    }
    if (mounted) setState(() {});
  }

  Future<void> _submitPreOrder({bool retryOnAuthError = true}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 item menu.')),
      );
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

      // Build items list for API
      final items = <Map<String, dynamic>>[];
      for (final entry in _cart.entries) {
        items.add({
          'product_id': entry.key,
          'quantity': entry.value,
        });
      }

      await ApiService.createPreOrder(
        token: token,
        pklId: widget.pklId,
        catatan: _catatanController.text.trim().isEmpty
            ? null
            : _catatanController.text.trim(),
        pickupAddress: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        pickupLatitude: latitude,
        pickupLongitude: longitude,
        items: items,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pre-order berhasil dikirim.')),
      );

      _catatanController.clear();
      _addressController.clear();
      _latController.clear();
      _lngController.clear();
      setState(() {
        _cart.clear();
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
        decoration: BoxDecoration(
          color: _themeManager.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  color: _borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                  style: TextStyle(color: _mutedTextColor, fontSize: 14),
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
    final isDark = _themeManager.isDarkMode;
    final optionBg = isDark ? _themeManager.surfaceColor : Colors.grey.shade50;
    final optionBorder = isDark ? _borderColor : Colors.grey.shade200;
    final subtitleColor = isDark ? _mutedTextColor : Colors.grey.shade600;
    final chevronColor = isDark ? _mutedTextColor : Colors.grey.shade400;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: optionBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: optionBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryColor, _secondaryColor],
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _darkColor,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: subtitleColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: chevronColor),
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
    final isDark = _themeManager.isDarkMode;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _themeManager.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primaryColor, _secondaryColor],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.link, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
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
                style: TextStyle(color: _mutedTextColor, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? _themeManager.surfaceColor
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? _borderColor : Colors.grey.shade200,
                  ),
                ),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'https://drive.google.com/...',
                    hintStyle: TextStyle(color: _themeManager.hintTextColor),
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
                        style: TextStyle(
                          color: isDark
                              ? _mutedTextColor
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_primaryColor, _secondaryColor],
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
    bool readOnly = false,
  }) {
    final isDark = _themeManager.isDarkMode;
    final cardBg = _themeManager.cardColor;
    final fieldFill = isDark ? _themeManager.surfaceColor : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
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
        readOnly: readOnly,
        style: TextStyle(fontSize: 15, color: _darkColor),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primaryColor, _secondaryColor],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          labelStyle: TextStyle(
            color: isDark ? _mutedTextColor : Colors.grey.shade600,
          ),
          hintStyle: TextStyle(
            color: isDark ? _themeManager.hintTextColor : Colors.grey.shade400,
          ),
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
            borderSide: BorderSide(color: _primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          filled: true,
          fillColor: fieldFill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final primary = _primaryColor;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, _secondaryColor],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _themeManager.isDarkMode
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: _themeManager.isDarkMode
                          ? Colors.white
                          : _themeManager.textColor),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pre-Order',
                      style: TextStyle(
                        color: _themeManager.isDarkMode
                            ? Colors.white
                            : _themeManager.textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.pklName,
                      style: TextStyle(
                        color: _themeManager.isDarkMode
                            ? Colors.white.withValues(alpha: 0.9)
                            : _themeManager.mutedTextColor,
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
                  color: _themeManager.isDarkMode
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(Icons.refresh,
                      color: _themeManager.isDarkMode
                          ? Colors.white
                          : _themeManager.textColor),
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
    final cardBg = _themeManager.cardColor;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
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
          gradient: LinearGradient(colors: [_primaryColor, _secondaryColor]),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.70),
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
                      style: TextStyle(
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
            // Menu section
            _buildMenuSelectionSection(),
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
            _buildLocationPicker(),
            const SizedBox(height: 24),
            _buildOrderSummaryCard(),
            const SizedBox(height: 24),
            _buildDPCard(),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryColor, _secondaryColor],
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

  Widget _buildMenuSelectionSection() {
    final products = _availableProducts;
    final isDark = _themeManager.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.restaurant_menu, color: _primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              'Pilih Menu',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _darkColor,
              ),
            ),
            const Spacer(),
            if (_cartItemCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_cartItemCount item',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingPKL)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _primaryColor),
            ),
          )
        else if (products.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? _primaryColor.withValues(alpha: 0.08)
                  : _accentColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'Belum ada menu tersedia',
                style: TextStyle(color: _mutedTextColor),
              ),
            ),
          )
        else
          ...products.map((product) => _buildMenuItemRow(product)),
      ],
    );
  }

  Widget _buildMenuItemRow(Map<String, dynamic> product) {
    final id = product['id'] as int;
    final name = (product['name'] ?? '-') as String;
    final price = (product['price'] as num?)?.toInt() ?? 0;
    final imageUrl = _resolveImageUrl(product['image_url'] as String?);
    final qty = _cart[id] ?? 0;
    final isDark = _themeManager.isDarkMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: qty > 0
            ? Border.all(color: _primaryColor, width: 1.5)
            : Border.all(color: _borderColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _accentColor,
                        child: Icon(Icons.fastfood, color: _primaryColor.withValues(alpha: 0.4), size: 24),
                      ),
                    )
                  : Container(
                      color: _accentColor,
                      child: Icon(Icons.fastfood, color: _primaryColor.withValues(alpha: 0.4), size: 24),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _darkColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Rp ${_formatMenuPrice(price)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
          if (qty == 0)
            InkWell(
              onTap: () {
                setState(() => _cart[id] = 1);
                _recalculateDP();
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? _primaryColor.withValues(alpha: 0.15)
                    : _accentColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (qty <= 1) {
                          _cart.remove(id);
                        } else {
                          _cart[id] = qty - 1;
                        }
                      });
                      _recalculateDP();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.remove, size: 18, color: _primaryColor),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '$qty',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _darkColor,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _cart[id] = qty + 1);
                      _recalculateDP();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.add, size: 18, color: _primaryColor),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    if (_cart.isEmpty) return const SizedBox.shrink();

    final products = _availableProducts;
    final total = _cartTotal;

    return Container(
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Ringkasan Pesanan',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: _darkColor,
              ),
            ),
          ),
          const Divider(height: 1),
          ...(_cart.entries.map((entry) {
            final product = products.firstWhere(
              (p) => p['id'] == entry.key,
              orElse: () => <String, dynamic>{},
            );
            final name = (product['name'] ?? '-') as String;
            final price = (product['price'] as num?)?.toInt() ?? 0;
            final subtotal = price * entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$name  x${entry.value}',
                      style: TextStyle(fontSize: 13, color: _darkColor),
                    ),
                  ),
                  Text(
                    'Rp ${_formatMenuPrice(subtotal)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _darkColor,
                    ),
                  ),
                ],
              ),
            );
          })),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _darkColor,
                    ),
                  ),
                ),
                Text(
                  'Rp ${_formatMenuPrice(total)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMenuPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  String? _resolveImageUrl(String? url) {
    final value = (url ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '${ApiService.baseUrl}$value';
    }
    return '${ApiService.baseUrl}/$value';
  }

  Widget _buildLocationPicker() {
    final border = BorderRadius.circular(12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lokasi Penjemputan', style: TextStyle(fontWeight: FontWeight.w700, color: _darkColor)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Cari alamat...',
                  border: OutlineInputBorder(borderRadius: border),
                ),
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (v) => _searchAddress(v),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _searchAddress(_searchController.text),
              child: const Text('Cari'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: border,
            border: Border.all(color: _borderColor),
            color: _themeManager.surfaceColor,
          ),
          child: ClipRRect(
            borderRadius: border,
            child: _mapLoading || _initialCenter == null
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _initialCenter!,
                      initialZoom: _initialZoom,
                      onTap: (tapPosition, point) => _onMapTap(point),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.gomuter.app',
                      ),
                      if (_selectedLatLng != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedLatLng!,
                              width: 46,
                              height: 46,
                              child: Icon(
                                Icons.location_on_rounded,
                                size: 42,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildModernTextField(
                controller: _addressController,
                label: 'Alamat (tersimpan)',
                hint: 'Alamat hasil pencarian / titik di peta',
                icon: Icons.location_on_outlined,
                readOnly: true,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _selectedLatLng == null
                  ? null
                  : () async {
                      // Save selected location into controllers
                      final pos = _selectedLatLng!;
                      _latController.text = pos.latitude.toString();
                      _lngController.text = pos.longitude.toString();
                      final addr = await _reverseGeocode(pos);
                      if (addr != null && addr.isNotEmpty) {
                        _addressController.text = addr;
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Titik penjemputan disimpan.')),
                      );
                      setState(() {});
                    },
              child: const Text('Simpan titik'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDPCard() {
    final isDark = _themeManager.isDarkMode;

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
              gradient: LinearGradient(
                colors: [_primaryColor, _secondaryColor],
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
                    color: isDark
                        ? _themeManager.orangeSurfaceColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Rp ${_formatMenuPrice(_dpAmount)}',
                    style: TextStyle(
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
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: _primaryColor),
                    ),
                  )
                : _pklError != null
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: isDark ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade400,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _pklError!,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.red.shade200
                                  : Colors.red.shade700,
                            ),
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
                            color: isDark
                                ? _themeManager.surfaceColor
                                : Colors.white,
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
                                  style: TextStyle(
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
                            color: isDark
                                ? _themeManager.surfaceColor
                                : Colors.white,
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
                                  color: isDark
                                      ? _themeManager.surfaceColor
                                      : Colors.grey.shade50,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/qris_logo.png',
                                      height: 24,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.qr_code_2,
                                        color: _primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
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
                                      color: isDark
                                          ? _themeManager.surfaceColor
                                          : Colors.grey.shade100,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image,
                                            size: 48,
                                            color: isDark
                                                ? _mutedTextColor
                                                : Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'QRIS tidak dapat dimuat',
                                            style: TextStyle(
                                              color: isDark
                                                  ? _mutedTextColor
                                                  : Colors.grey.shade600,
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
                            color: isDark
                                ? _themeManager.surfaceColor
                                : Colors.white,
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
                                  style: TextStyle(
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
                            color: isDark
                                ? _themeManager.orangeSurfaceColor
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'PKL belum mengunggah QRIS. Hubungi PKL untuk info pembayaran.',
                                  style: TextStyle(
                                    color: isDark
                                        ? _mutedTextColor
                                        : Colors.orange.shade800,
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
                      color: isDark
                          ? _themeManager.surfaceColor
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: isDark
                              ? _mutedTextColor
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Informasi PKL belum tersedia.',
                          style: TextStyle(color: _darkColor),
                        ),
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
              child: CircularProgressIndicator(color: _primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Memuat riwayat...',
              style: TextStyle(
                color: _themeManager.isDarkMode
                    ? _mutedTextColor
                    : Colors.grey.shade600,
              ),
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
              Text(
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
                style: TextStyle(
                  color: _themeManager.isDarkMode
                      ? _mutedTextColor
                      : Colors.grey.shade600,
                ),
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
    final isDark = _themeManager.isDarkMode;

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
        color: _themeManager.cardColor,
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _darkColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        createdText,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? _mutedTextColor
                              : Colors.grey.shade600,
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
                  style: TextStyle(
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
                      color: isDark
                          ? _themeManager.surfaceColor
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notes,
                          size: 16,
                          color: isDark
                              ? _mutedTextColor
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            catatan,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? _mutedTextColor
                                  : Colors.grey.shade700,
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
                                color: isDark
                                    ? _mutedTextColor
                                    : Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              'Rp $dpAmount',
                              style: TextStyle(
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
                      color: isDark
                          ? Colors.green.withValues(alpha: 0.18)
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: isDark
                              ? Colors.green.shade300
                              : Colors.green.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bukti DP sudah dikirim',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.green.shade200
                                  : Colors.green.shade700,
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
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
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
                              side: BorderSide(color: _primaryColor),
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
      backgroundColor: _themeManager.backgroundColor,
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
