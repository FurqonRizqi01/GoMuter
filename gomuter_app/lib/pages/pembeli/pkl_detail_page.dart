import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pembeli/chat_page.dart';
import 'package:gomuter_app/pages/pembeli/preorder_page.dart';
import 'package:gomuter_app/utils/token_manager.dart';

class PklDetailPage extends StatefulWidget {
  final int pklId;
  final Map<String, dynamic>? initialData;

  const PklDetailPage({super.key, required this.pklId, this.initialData});

  @override
  State<PklDetailPage> createState() => _PklDetailPageState();
}

class _PklDetailPageState extends State<PklDetailPage> {
  // Theme Colors
  static const Color _primaryGreen = Color(0xFF1B7B5A);
  static const Color _secondaryGreen = Color(0xFF2D9D78);
  static const Color _lightGreen = Color(0xFFE8F5F0);
  static const Color _accentPeach = Color(0xFFFAD4C0);

  Map<String, dynamic>? _detail;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  LatLng? _pklLatLng;
  LatLng? _buyerLatLng;
  double? _distanceMeters;
  Map<String, dynamic>? _ratingSummary;
  double? _userRatingScore;
  String? _userRatingComment;
  bool _isRatingLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _detail = Map<String, dynamic>.from(widget.initialData!);
      _pklLatLng = _extractLatLng(_detail);
    }
    _loadDetail(initial: true);
    _loadRatingSummary();
    _loadBuyerLocation();
  }

  LatLng? _extractLatLng(Map<String, dynamic>? data) {
    final lat = (data?["latest_latitude"] as num?)?.toDouble();
    final lng = (data?["latest_longitude"] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  double? _computeDistance(LatLng? buyer, LatLng? seller) {
    if (buyer == null || seller == null) return null;
    return Geolocator.distanceBetween(
      buyer.latitude,
      buyer.longitude,
      seller.latitude,
      seller.longitude,
    );
  }

  Future<void> _loadDetail({bool initial = false}) async {
    final showBlockingLoader = initial && _detail == null;

    if (showBlockingLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _error = null;
      });
    }

    try {
      final data = await ApiService.getPKLDetail(widget.pklId);
      if (!mounted) return;
      setState(() {
        _detail = Map<String, dynamic>.from(data);
        _pklLatLng = _extractLatLng(_detail);
        _distanceMeters = _computeDistance(_buyerLatLng, _pklLatLng);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat detail PKL: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          if (showBlockingLoader) {
            _isLoading = false;
          }
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadBuyerLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      final buyer = LatLng(position.latitude, position.longitude);
      setState(() {
        _buyerLatLng = buyer;
        _distanceMeters = _computeDistance(buyer, _pklLatLng);
      });
    } catch (_) {
      // Buyer position is optional for this view.
    }
  }

  Future<void> _loadRatingSummary() async {
    setState(() {
      _isRatingLoading = true;
    });

    try {
      final token = await TokenManager.getValidAccessToken();
      final summary = await ApiService.getPKLRatingSummary(
        pklId: widget.pklId,
        accessToken: token,
      );
      if (!mounted) return;
      final userRatingRaw = summary['user_rating'];
      setState(() {
        _ratingSummary = summary;
        if (userRatingRaw is Map<String, dynamic>) {
          _userRatingScore = (userRatingRaw['score'] as num?)?.toDouble();
          _userRatingComment = (userRatingRaw['comment'] as String?) ?? '';
        } else {
          _userRatingScore = null;
          _userRatingComment = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ratingSummary = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memuat rating: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isRatingLoading = false;
        });
      }
    }
  }

  Future<void> _submitRatingToServer(double score, String comment) async {
    final token = await TokenManager.getValidAccessToken();
    if (token == null) {
      throw Exception('Token tidak ditemukan. Silakan login ulang.');
    }
    await ApiService.submitPKLRating(
      token: token,
      pklId: widget.pklId,
      score: score,
      comment: comment,
    );
    await _loadRatingSummary();
  }

  Future<void> _deleteRatingFromServer() async {
    final token = await TokenManager.getValidAccessToken();
    if (token == null) {
      throw Exception('Token tidak ditemukan. Silakan login ulang.');
    }
    await ApiService.deletePKLRating(token: token, pklId: widget.pklId);
    await _loadRatingSummary();
  }

  void _showRatingSheet() {
    double currentValue = _userRatingScore ?? 4.0;
    final controller = TextEditingController(text: _userRatingComment ?? '');
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, modalSetState) {
            Future<void> submit() async {
              modalSetState(() {
                isSubmitting = true;
              });
              try {
                await _submitRatingToServer(
                  currentValue,
                  controller.text.trim(),
                );
                if (!ctx.mounted || !mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rating tersimpan.')),
                );
              } catch (e) {
                modalSetState(() {
                  isSubmitting = false;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menyimpan rating: $e')),
                  );
                }
              }
            }

            Future<void> deleteRating() async {
              modalSetState(() {
                isSubmitting = true;
              });
              try {
                await _deleteRatingFromServer();
                if (!ctx.mounted || !mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rating dihapus.')),
                );
              } catch (e) {
                modalSetState(() {
                  isSubmitting = false;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menghapus rating: $e')),
                  );
                }
              }
            }

            final bottomPadding = MediaQuery.of(ctx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: bottomPadding + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Beri penilaian',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: isSubmitting
                            ? null
                            : () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        _formatRatingValue(currentValue),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.orangeAccent,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      const Text('/ 5'),
                    ],
                  ),
                  Slider(
                    value: currentValue,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    label: _formatRatingValue(currentValue),
                    onChanged: isSubmitting
                        ? null
                        : (value) {
                            final snapped = (value * 2).round() / 2.0;
                            modalSetState(() {
                              currentValue = snapped;
                            });
                          },
                  ),
                  TextField(
                    controller: controller,
                    enabled: !isSubmitting,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Komentar (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: isSubmitting ? null : submit,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _userRatingScore == null
                          ? 'Simpan Rating'
                          : 'Perbarui Rating',
                    ),
                  ),
                  if (_userRatingScore != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: isSubmitting ? null : deleteRating,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Hapus Rating'),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _distanceLabel() {
    final distance = _distanceMeters;
    if (distance == null) return '-';
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
    return '${distance.toStringAsFixed(0)} m';
  }

  String _formatRatingValue(double? value) {
    if (value == null) return '-';
    final truncated = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return truncated;
  }

  // ignore: unused_element
  String _formatTimestamp(dynamic value) {
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        final local = parsed.toLocal();
        final day = local.day.toString().padLeft(2, '0');
        final month = local.month.toString().padLeft(2, '0');
        final year = local.year;
        final hour = local.hour.toString().padLeft(2, '0');
        final minute = local.minute.toString().padLeft(2, '0');
        return '$day/$month/$year • $hour:$minute';
      }
    }
    return '-';
  }

  Future<void> _openExternalMap() async {
    final location = _pklLatLng;
    if (location == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}',
    );

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka Google Maps.')),
      );
    }
  }

  void _openChat() {
    final data = _detail;
    if (data == null) return;
    final name = (data['nama_usaha'] ?? '-') as String;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(pklId: widget.pklId, pklNama: name),
      ),
    );
  }

  void _openPreorder() {
    final data = _detail;
    if (data == null) return;
    final name = (data['nama_usaha'] ?? '-') as String;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreOrderPage(pklId: widget.pklId, pklName: name),
      ),
    );
  }

  void _showMapSheet() {
    final location = _pklLatLng;
    if (location == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Lokasi PKL',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: location,
                        initialZoom: 16,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                          userAgentPackageName: 'com.example.gomuter_app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: location,
                              width: 36,
                              height: 36,
                              child: const Icon(
                                Icons.location_pin,
                                size: 36,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _openExternalMap();
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Buka di Google Maps'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Map<String, dynamic> data) {
    final name = (data['nama_usaha'] ?? '-') as String;
    final jenis = (data['jenis_dagangan'] ?? '-') as String;
    // jam_operasional is available in data if needed
    final isActive = data['status_aktif'] == true;
    final avgRating = (_ratingSummary?['average_rating'] as num?)?.toDouble();
    final ratingCount = (_ratingSummary?['rating_count'] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primaryGreen, _secondaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryGreen.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Detail PKL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _loadDetail(initial: false),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isRefreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            // PKL Image/Icon
            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _getCategoryIcon(jenis),
                    size: 48,
                    color: _primaryGreen,
                  ),
                ),
              ),
            ),
            // PKL Info
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Rating Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              avgRating != null
                                  ? _formatRatingValue(avgRating)
                                  : '-',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              ' ($ratingCount ulasan)',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.greenAccent.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.greenAccent
                                    : Colors.grey,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isActive ? 'Buka' : 'Tutup',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('makanan') ||
        lower.contains('nasi') ||
        lower.contains('mie') ||
        lower.contains('soto')) {
      return Icons.restaurant_rounded;
    } else if (lower.contains('minuman') ||
        lower.contains('es') ||
        lower.contains('jus')) {
      return Icons.local_cafe_rounded;
    } else if (lower.contains('snack') || lower.contains('gorengan')) {
      return Icons.fastfood_rounded;
    }
    return Icons.storefront_rounded;
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: Icons.phone_rounded,
              label: 'Hubungi',
              color: _primaryGreen,
              filled: true,
              onTap: _detail == null ? null : _openChat,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: Icons.map_rounded,
              label: 'Lihat di Peta',
              color: _accentPeach,
              textColor: _primaryGreen,
              filled: true,
              onTap: _pklLatLng == null ? null : _showMapSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    Color? textColor,
    bool filled = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: filled ? null : Border.all(color: color),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: textColor ?? (filled ? Colors.white : color),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor ?? (filled ? Colors.white : color),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(Map<String, dynamic> data) {
    final alamat = (data['alamat_domisili'] ?? '-') as String;
    final jam = (data['jam_operasional'] ?? '-') as String;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.location_on_rounded,
            title: 'Lokasi',
            subtitle: _distanceLabel(),
            detail: alamat,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.access_time_rounded,
            title: 'Jam Operasional',
            subtitle: jam,
            detail: 'Senin - Minggu',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.payments_rounded,
            title: 'Harga',
            subtitle: 'Rp 15.000 - Rp 50.000',
            detail: 'Harga bervariasi',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primaryGreen, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSection() {
    final avgRating = (_ratingSummary?['average_rating'] as num?)?.toDouble();
    final ratingCount = (_ratingSummary?['rating_count'] as num?)?.toInt() ?? 0;
    final userRating = _userRatingScore;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ulasan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              if (_isRatingLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatRatingValue(avgRating),
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                '/5',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: List.generate(5, (index) {
                            final rating = avgRating ?? 0;
                            return Icon(
                              index < rating.floor()
                                  ? Icons.star_rounded
                                  : index < rating
                                  ? Icons.star_half_rounded
                                  : Icons.star_outline_rounded,
                              color: Colors.amber,
                              size: 20,
                            );
                          }),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ratingCount == 0
                              ? 'Belum ada ulasan'
                              : '$ratingCount ulasan',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                if (userRating != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _lightGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: _primaryGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Rating Anda: ${_formatRatingValue(userRating)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRatingLoading ? null : _showRatingSheet,
                    icon: const Icon(Icons.rate_review_rounded),
                    label: Text(
                      userRating == null ? 'Tulis Ulasan' : 'Ubah Ulasan',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

  Widget _buildAboutSection(Map<String, dynamic> data) {
    final catatan = (data['catatan_verifikasi'] ?? '') as String;
    final description = catatan.isNotEmpty
        ? catatan
        : 'Warung dengan menu legendaris yang menggunakan bahan-bahan pilihan berkualitas tinggi dan bumbu racikan khusus yang membuat cita rasa unik dan nikmat.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tentang',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Foto',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (context, index) {
                return Container(
                  width: 90,
                  height: 90,
                  margin: EdgeInsets.only(right: index < 2 ? 12 : 0),
                  decoration: BoxDecoration(
                    color: _lightGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getCategoryIcon(
                      _detail?['jenis_dagangan'] as String? ?? '',
                    ),
                    color: _primaryGreen.withValues(alpha: 0.5),
                    size: 32,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrisPreview(Map<String, dynamic> data) {
    final qrisUrl = (data['qris_image_url'] ?? '') as String;
    if (qrisUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QRIS Pembayaran',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  qrisUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[100],
                    child: const Center(child: Text('Gagal memuat QRIS')),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.grey[100],
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _primaryGreen,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPreview() {
    if (_pklLatLng == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lokasi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: _pklLatLng!,
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'com.example.gomuter_app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pklLatLng!,
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _primaryGreen,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primaryGreen.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: _openExternalMap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_rounded,
                              color: _primaryGreen,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Petunjuk Arah',
                              style: TextStyle(
                                color: _primaryGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _detail;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading && data == null
          ? _buildLoadingState()
          : data == null
          ? _buildErrorStateWidget()
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _loadDetail(initial: false),
                  color: _primaryGreen,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(data),
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                        const SizedBox(height: 24),
                        _buildDetailSection(data),
                        const SizedBox(height: 24),
                        _buildAboutSection(data),
                        const SizedBox(height: 24),
                        _buildPhotoSection(),
                        const SizedBox(height: 24),
                        _buildRatingSection(),
                        const SizedBox(height: 24),
                        _buildMapPreview(),
                        const SizedBox(height: 24),
                        _buildQrisPreview(data),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
                // Bottom Floating Buttons
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildFloatingButton(
                          icon: Icons.chat_bubble_rounded,
                          label: 'Chat',
                          color: _primaryGreen,
                          onTap: _openChat,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFloatingButton(
                          icon: Icons.receipt_long_rounded,
                          label: 'Pre-order',
                          color: _accentPeach,
                          textColor: _primaryGreen,
                          onTap: _openPreorder,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFloatingButton({
    required IconData icon,
    required String label,
    required Color color,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: textColor ?? Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor ?? Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _lightGreen,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Memuat detail PKL...',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorStateWidget() {
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: Colors.red[400],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _error ?? 'Gagal memuat detail PKL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _loadDetail(initial: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba Lagi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(subtitle, style: const TextStyle(fontSize: 14));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1B7B5A)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: textWidget,
      ),
    );
  }
}
