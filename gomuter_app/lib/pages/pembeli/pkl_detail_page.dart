import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pembeli/chat_page.dart';
import 'package:gomuter_app/pages/pembeli/preorder_page.dart';
import 'package:gomuter_app/utils/chat_badge_manager.dart';
import 'package:gomuter_app/utils/map_route_service.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';

class PklDetailPage extends StatefulWidget {
  final int pklId;
  final Map<String, dynamic>? initialData;
  final LatLng? initialBuyerLatLng;

  const PklDetailPage({
    super.key,
    required this.pklId,
    this.initialData,
    this.initialBuyerLatLng,
  });

  @override
  State<PklDetailPage> createState() => _PklDetailPageState();
}

class _PklDetailPageState extends State<PklDetailPage> {
  final ThemeManager _themeManager = ThemeManager();
  static const Duration _statusPollingInterval = Duration(seconds: 10);

  Color get _primary => _themeManager.primaryOrange;
  Color get _secondary => _themeManager.secondaryOrange;
  Color get _softSurface => _themeManager.orangeSurfaceColor;
  Color get _ctaAccent => _themeManager.primaryOrange;

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
  bool _isFavorite = false;
  bool _isFavoriteLoading = false;
  Timer? _statusPollingTimer;
  bool _isStatusPolling = false;

  List<LatLng> _routePoints = [];
  double? _routeDistanceMeters;
  int _routeRequestSerial = 0;

  // Cart: productId → quantity
  final Map<int, int> _cart = {};

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    if (widget.initialData != null) {
      _detail = Map<String, dynamic>.from(widget.initialData!);
      _pklLatLng = _extractLatLng(_detail);
    }
    _buyerLatLng = widget.initialBuyerLatLng;
    _distanceMeters = _computeDistance(_buyerLatLng, _pklLatLng);
    _loadDetail(initial: true);
    _loadRatingSummary();
    _loadBuyerLocation();
    _loadFavoriteState();
    _startStatusPolling();
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    _themeManager.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _startStatusPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(_statusPollingInterval, (_) {
      _pollStatusSilently();
    });
  }

  Future<void> _pollStatusSilently() async {
    if (!mounted || _isStatusPolling) return;
    _isStatusPolling = true;
    try {
      final data = await ApiService.getPKLDetail(widget.pklId);
      if (!mounted) return;

      setState(() {
        _detail = Map<String, dynamic>.from(data);
        _pklLatLng = _extractLatLng(_detail);
        _distanceMeters = _computeDistance(_buyerLatLng, _pklLatLng);
      });
      unawaited(_loadRoute());
    } catch (_) {
      // Keep UI stable when polling fails briefly (network spikes, backend restart).
    } finally {
      _isStatusPolling = false;
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
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

  Future<void> _loadRoute({VoidCallback? onUpdated}) async {
    final buyer = _buyerLatLng;
    final pkl = _pklLatLng;
    if (buyer == null || pkl == null) {
      if (mounted) {
        setState(() {
          _routeRequestSerial++;
          _routePoints = [];
          _routeDistanceMeters = null;
        });
        onUpdated?.call();
      }
      return;
    }

    final requestId = ++_routeRequestSerial;
    final result = await MapRouteService.fetchRoute(
      origin: buyer,
      destination: pkl,
    );

    if (!mounted || requestId != _routeRequestSerial) return;
    setState(() {
      _routePoints = result.points;
      _routeDistanceMeters = result.distanceMeters;
    });
    onUpdated?.call();
  }

  List<LatLng> _visibleRoutePoints(LatLng buyer, LatLng pkl) {
    return _routePoints.length >= 2 ? _routePoints : [buyer, pkl];
  }

  double? _visibleRouteDistanceMeters() {
    return _routeDistanceMeters ?? _distanceMeters;
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
      unawaited(_loadRoute());
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
    Future<bool> useSavedBuyerLocation() async {
      try {
        final token = await TokenManager.getValidAccessToken();
        if (token == null) return false;

        final saved = await ApiService.getBuyerLocation(token: token);
        final lat = (saved?['latitude'] as num?)?.toDouble();
        final lng = (saved?['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return false;

        if (!mounted) return true;
        final buyer = LatLng(lat, lng);
        setState(() {
          _buyerLatLng = buyer;
          _distanceMeters = _computeDistance(buyer, _pklLatLng);
        });
        unawaited(_loadRoute());
        return true;
      } catch (_) {
        return false;
      }
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await useSavedBuyerLocation();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await useSavedBuyerLocation();
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {
        position = null;
      }

      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      final buyer = LatLng(position.latitude, position.longitude);
      setState(() {
        _buyerLatLng = buyer;
        _distanceMeters = _computeDistance(buyer, _pklLatLng);
      });
      unawaited(_loadRoute());
    } catch (_) {
      await useSavedBuyerLocation();
    }
  }

  void _refreshRoute() {
    if (_buyerLatLng == null) return;
    unawaited(_loadRoute());
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
    }
    return '${meters.round()} m';
  }

  Widget _buildDistanceLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _themeManager.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _themeManager.isDarkMode ? 0.35 : 0.12,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _themeManager.textColor,
        ),
      ),
    );
  }

  Widget _buildMapMarker({
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final borderBase = _themeManager.isDarkMode
        ? _themeManager.textColor
        : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: borderBase, width: 2)
              : Border.all(color: borderBase.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
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

  Future<void> _loadFavoriteState() async {
    try {
      final token = await TokenManager.getValidAccessToken();
      if (token == null) return;

      final favorites = await ApiService.getFavoritePKL(token: token);
      final isFavorite = favorites.any((fav) {
        if (fav is! Map<String, dynamic>) return false;
        final pklValue = fav['pkl'];
        if (pklValue is num) {
          return pklValue.toInt() == widget.pklId;
        }
        return false;
      });

      if (!mounted) return;
      setState(() {
        _isFavorite = isFavorite;
      });
    } catch (_) {
      // Ignore favorite state errors to keep detail page responsive.
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading) return;

    final token = await TokenManager.getValidAccessToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi berakhir. Silakan login ulang.')),
      );
      return;
    }

    setState(() {
      _isFavoriteLoading = true;
    });

    try {
      if (_isFavorite) {
        await ApiService.removeFavoritePKL(token: token, pklId: widget.pklId);
      } else {
        await ApiService.addFavoritePKL(token: token, pklId: widget.pklId);
      }

      if (!mounted) return;
      setState(() {
        _isFavorite = !_isFavorite;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavorite
                ? 'PKL ditambahkan ke favorit'
                : 'PKL dihapus dari favorit',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui favorit: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFavoriteLoading = false;
        });
      }
    }
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

  Future<void> _openChat() async {
    final data = _detail;
    if (data == null) return;
    final name = (data['nama_usaha'] ?? '-') as String;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(pklId: widget.pklId, pklNama: name),
      ),
    );
    await ChatBadgeManager.markChatsSeen(ChatRole.pembeli);
  }

  int get _cartTotal {
    final data = _detail;
    if (data == null) return 0;
    final productsRaw = data['products'];
    final products = productsRaw is List ? productsRaw : const [];
    int total = 0;
    for (final entry in _cart.entries) {
      final product = products.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p != null && p['id'] == entry.key,
        orElse: () => null,
      );
      if (product != null) {
        total += ((product['price'] as num?)?.toInt() ?? 0) * entry.value;
      }
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

  void _openPreorder() {
    final data = _detail;
    if (data == null) return;
    final name = (data['nama_usaha'] ?? '-') as String;
    final productsRaw = data['products'];
    final products = productsRaw is List ? productsRaw : const [];

    // Build cart items list
    final cartItems = <Map<String, dynamic>>[];
    for (final entry in _cart.entries) {
      final product = products.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p != null && p['id'] == entry.key,
        orElse: () => null,
      );
      if (product != null) {
        cartItems.add({
          'product_id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'quantity': entry.value,
          'image_url': product['image_url'],
        });
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreOrderPage(
          pklId: widget.pklId,
          pklName: name,
          initialCart: cartItems.isEmpty ? null : cartItems,
        ),
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
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final buyer = _buyerLatLng;
            final showRoute = buyer != null;
            final routePoints = buyer != null
                ? _visibleRoutePoints(buyer, location)
                : const <LatLng>[];

            final distanceMeters = showRoute
                ? (_visibleRouteDistanceMeters() ??
                      _computeDistance(buyer, location))
                : null;
            final distanceText = distanceMeters != null
                ? _formatDistance(distanceMeters)
                : null;
            final labelPoint = distanceText != null && routePoints.length >= 2
                ? routePoints[routePoints.length ~/ 2]
                : null;
            final cameraFit = routePoints.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(routePoints),
                    padding: const EdgeInsets.all(42),
                    maxZoom: 16,
                  )
                : null;

            void refreshSheetRoute() {
              if (_buyerLatLng == null) return;
              unawaited(_loadRoute(onUpdated: () => setSheetState(() {})));
            }

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
                          key: ValueKey(
                            'detail-sheet-${buyer?.latitude}-${buyer?.longitude}-${location.latitude}-${location.longitude}-${routePoints.length}',
                          ),
                          options: MapOptions(
                            initialCenter: location,
                            initialZoom: 16,
                            initialCameraFit: cameraFit,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.example.gomuter_app',
                            ),
                            if (showRoute && routePoints.length >= 2)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: routePoints,
                                    strokeWidth: 9,
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                  Polyline(
                                    points: routePoints,
                                    strokeWidth: 5,
                                    color: const Color(0xFF31A853),
                                  ),
                                ],
                              ),
                            if (labelPoint != null && distanceText != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: labelPoint,
                                    width: 140,
                                    height: 40,
                                    child: IgnorePointer(
                                      child: Center(
                                        child: _buildDistanceLabel(
                                          distanceText,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                if (buyer != null)
                                  Marker(
                                    point: buyer,
                                    width: 44,
                                    height: 44,
                                    child: _buildMapMarker(
                                      icon: Icons.person_pin_circle_rounded,
                                      color: _ctaAccent,
                                      selected: true,
                                      onTap: refreshSheetRoute,
                                    ),
                                  ),
                                Marker(
                                  point: location,
                                  width: 44,
                                  height: 44,
                                  child: _buildMapMarker(
                                    icon: Icons.storefront_rounded,
                                    color: _primary,
                                    selected: true,
                                    onTap: refreshSheetRoute,
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
      },
    );
  }

  Widget _buildHeader(Map<String, dynamic> data) {
    final name = (data['nama_usaha'] ?? '-') as String;
    final jenis = (data['jenis_dagangan'] ?? '-') as String;
    final alamat = (data['alamat_domisili'] ?? '-') as String;
    final isActive = data['status_aktif'] == true;
    final avgRating = (_ratingSummary?['average_rating'] as num?)?.toDouble();
    final ratingCount = (_ratingSummary?['rating_count'] as num?)?.toInt() ?? 0;

    // Collect product images for hero
    final productsRaw = data['products'];
    final products = productsRaw is List ? productsRaw : const [];
    String? heroImageUrl;
    for (final item in products) {
      if (item is Map) {
        final url = item['image_url'];
        if (url is String && url.isNotEmpty) {
          heroImageUrl = url;
          break;
        }
      }
    }

    final isDark = _themeManager.isDarkMode;

    return SizedBox(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Hero image
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary, _secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: heroImageUrl != null
                ? Image.network(
                    heroImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                        _getCategoryIcon(jenis),
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      _getCategoryIcon(jenis),
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          // Gradient scrim for AppBar readability
          Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // AppBar overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
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
                          color: Colors.black.withValues(alpha: 0.3),
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
                                Icons.share_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Status badge
          Positioned(
            top: 80,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF22C55E) : Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isActive ? 'BUKA SEKARANG' : 'TUTUP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Card overlay
          Container(
            margin: const EdgeInsets.only(top: 190),
            width: double.infinity,
            decoration: BoxDecoration(
              color: _themeManager.cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category tag
                  Text(
                    jenis.toUpperCase(),
                    style: TextStyle(
                      color: _primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Name + Rating row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: _themeManager.textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Rating box
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _softSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  avgRating != null
                                      ? _formatRatingValue(avgRating)
                                      : '-',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _themeManager.textColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.star_rounded,
                                  color: _primary,
                                  size: 20,
                                ),
                              ],
                            ),
                            Text(
                              '$ratingCount ulasan',
                              style: TextStyle(
                                fontSize: 11,
                                color: _themeManager.mutedTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Address
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: _themeManager.mutedTextColor,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          alamat,
                          style: TextStyle(
                            color: _themeManager.mutedTextColor,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircularAction(
            icon: Icons.phone_rounded,
            label: 'Telepon',
            color: _primary,
            onTap: _detail == null ? null : _openChat,
          ),
          _buildCircularAction(
            icon: Icons.near_me_rounded,
            label: 'Rute',
            color: const Color(0xFF3B82F6),
            onTap: _pklLatLng == null ? null : _showMapSheet,
          ),
          _buildCircularAction(
            icon: Icons.chat_bubble_rounded,
            label: 'Chat',
            color: _primary,
            onTap: _detail == null ? null : _openChat,
          ),
          _buildCircularAction(
            icon: _isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: 'Favorit',
            color: Colors.red,
            onTap: _isFavoriteLoading ? null : _toggleFavorite,
          ),
        ],
      ),
    );
  }

  Widget _buildCircularAction({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _themeManager.textColor,
            ),
          ),
        ],
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
            subtitle: _priceRangeLabel(data),
            detail: 'Pilih menu di bawah',
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
        color: _themeManager.cardColor,
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
              color: _softSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _themeManager.mutedTextColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _themeManager.textColor,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      color: _themeManager.mutedTextColor,
                      fontSize: 12,
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
                  color: _themeManager.textColor,
                ),
              ),
              if (_isRatingLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _themeManager.cardColor,
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
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: _themeManager.textColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '/5',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _themeManager.mutedTextColor,
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
                              color: _themeManager.accentGold,
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
                            color: _themeManager.mutedTextColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _themeManager.accentGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.star_rounded,
                        color: _themeManager.accentGold,
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
                      color: _softSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: _primary,
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
                      backgroundColor: _primary,
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
    final tentang = (data['tentang'] ?? '') as String;
    final description = tentang.isNotEmpty ? tentang : 'Belum ada deskripsi.';

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
              color: _themeManager.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: _themeManager.mutedTextColor,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(Map<String, dynamic> data) {
    final productsRaw = data['products'];
    final products = (productsRaw is List ? productsRaw : const [])
        .whereType<Map<String, dynamic>>()
        .where((p) => p['is_available'] == true)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, color: _primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Menu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _themeManager.textColor,
                ),
              ),
              const Spacer(),
              if (_cartItemCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primary,
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
          if (products.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _softSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  'Belum ada menu tersedia',
                  style: TextStyle(color: _themeManager.mutedTextColor),
                ),
              ),
            )
          else
            ...products.map((product) => _buildMenuItemCard(product)),
        ],
      ),
    );
  }

  Widget _buildMenuItemCard(Map<String, dynamic> product) {
    final id = product['id'] as int;
    final name = (product['name'] ?? '-') as String;
    final price = (product['price'] as num?)?.toInt() ?? 0;
    final imageUrl = product['image_url'] as String?;
    final description = (product['description'] ?? '') as String;
    final isFeatured = product['is_featured'] == true;
    final qty = _cart[id] ?? 0;
    final isDark = _themeManager.isDarkMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: qty > 0
            ? Border.all(color: _primary, width: 1.5)
            : Border.all(color: _themeManager.borderColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Product image
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 100,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: _softSurface,
                          child: Icon(
                            Icons.fastfood_rounded,
                            color: _primary.withValues(alpha: 0.4),
                            size: 32,
                          ),
                        ),
                      )
                    : Container(
                        color: _softSurface,
                        child: Icon(
                          Icons.fastfood_rounded,
                          color: _primary.withValues(alpha: 0.4),
                          size: 32,
                        ),
                      ),
              ),
            ),
            // Product info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (isFeatured)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '\u2B50',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: _themeManager.textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: _themeManager.mutedTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rp ${_formatPrice(price)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: _primary,
                            ),
                          ),
                        ),
                        if (qty == 0)
                          InkWell(
                            onTap: () => setState(() => _cart[id] = 1),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Tambah',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? _primary.withValues(alpha: 0.15)
                                  : _softSurface,
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
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(Icons.remove, size: 18, color: _primary),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    '$qty',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _themeManager.textColor,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() => _cart[id] = qty + 1),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(Icons.add, size: 18, color: _primary),
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
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  String _priceRangeLabel(Map<String, dynamic> data) {
    final productsRaw = data['products'];
    final products = (productsRaw is List ? productsRaw : const [])
        .whereType<Map<String, dynamic>>()
        .where((p) => p['is_available'] == true)
        .toList();
    if (products.isEmpty) return 'Belum ada menu';
    final prices = products
        .map((p) => (p['price'] as num?)?.toInt() ?? 0)
        .where((p) => p > 0)
        .toList();
    if (prices.isEmpty) return 'Harga bervariasi';
    prices.sort();
    final low = _formatPrice(prices.first);
    final high = _formatPrice(prices.last);
    if (prices.first == prices.last) return 'Rp $low';
    return 'Rp $low - Rp $high';
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
              color: _themeManager.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _themeManager.cardColor,
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
                    color: _themeManager.surfaceColor,
                    child: Center(
                      child: Text(
                        'Gagal memuat QRIS',
                        style: TextStyle(color: _themeManager.mutedTextColor),
                      ),
                    ),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: _themeManager.surfaceColor,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_primary),
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

    final buyer = _buyerLatLng;
    final showRoute = buyer != null;
    final routePoints = buyer != null
        ? _visibleRoutePoints(buyer, _pklLatLng!)
        : const <LatLng>[];

    final distanceMeters = showRoute
        ? (_visibleRouteDistanceMeters() ??
              _computeDistance(buyer, _pklLatLng))
        : null;
    final distanceText = distanceMeters != null
        ? _formatDistance(distanceMeters)
        : null;
    final labelPoint = distanceText != null && routePoints.length >= 2
        ? routePoints[routePoints.length ~/ 2]
        : null;
    final cameraFit = routePoints.length >= 2
        ? CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(routePoints),
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 54),
            maxZoom: 16,
          )
        : null;

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
              color: _themeManager.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: _themeManager.cardColor,
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
                    key: ValueKey(
                      'detail-preview-${buyer?.latitude}-${buyer?.longitude}-${_pklLatLng!.latitude}-${_pklLatLng!.longitude}-${routePoints.length}',
                    ),
                    options: MapOptions(
                      initialCenter: _pklLatLng!,
                      initialZoom: 16,
                      initialCameraFit: cameraFit,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'com.example.gomuter_app',
                      ),
                      if (showRoute && routePoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              strokeWidth: 9,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            Polyline(
                              points: routePoints,
                              strokeWidth: 5,
                              color: const Color(0xFF31A853),
                            ),
                          ],
                        ),
                      if (labelPoint != null && distanceText != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: labelPoint,
                              width: 140,
                              height: 40,
                              child: IgnorePointer(
                                child: Center(
                                  child: _buildDistanceLabel(distanceText),
                                ),
                              ),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (buyer != null)
                            Marker(
                              point: buyer,
                              width: 44,
                              height: 44,
                              child: _buildMapMarker(
                                icon: Icons.person_pin_circle_rounded,
                                color: _ctaAccent,
                                selected: true,
                                onTap: _refreshRoute,
                              ),
                            ),
                          Marker(
                            point: _pklLatLng!,
                            width: 44,
                            height: 44,
                            child: _buildMapMarker(
                              icon: Icons.storefront_rounded,
                              color: _primary,
                              selected: true,
                              onTap: _refreshRoute,
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
                          color: _themeManager.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: _themeManager.isDarkMode ? 0.35 : 0.1,
                              ),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_rounded,
                              color: _primary,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Petunjuk Arah',
                              style: TextStyle(
                                color: _primary,
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
    final bgColor = _themeManager.backgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: _isLoading && data == null
          ? _buildLoadingState()
          : data == null
          ? _buildErrorStateWidget()
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () => _loadDetail(initial: false),
                  color: _primary,
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
                        _buildPhotoSection(data),
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
                // Bottom Floating Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      14,
                      20,
                      MediaQuery.of(context).padding.bottom + 14,
                    ),
                    decoration: BoxDecoration(
                      color: _themeManager.cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _themeManager.isDarkMode ? 0.25 : 0.08,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Total Harga',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _themeManager.mutedTextColor,
                                ),
                              ),
                              Text(
                                'Rp ${_formatPrice(_cartTotal)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: _buildFloatingButton(
                            icon: Icons.shopping_bag_rounded,
                            label: 'Pesan Sekarang',
                            color: _primary,
                            onTap: _openPreorder,
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
            gradient: LinearGradient(
              colors: [_primary, _secondary],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _primary.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: textColor ?? Colors.white),
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
    final bgColor = _themeManager.backgroundColor;
    final textColor = _themeManager.textColor;
    return Container(
      color: bgColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _softSurface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primary),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Memuat detail PKL...',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorStateWidget() {
    final bgColor = _themeManager.backgroundColor;
    final isDark = _themeManager.isDarkMode;
    return Container(
      color: bgColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _error ?? 'Gagal memuat detail PKL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _themeManager.textColor,
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
                  backgroundColor: _primary,
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
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: textWidget,
      ),
    );
  }
}
