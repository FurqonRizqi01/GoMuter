import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pembeli/chat_page.dart';
import 'package:gomuter_app/pages/pembeli/pkl_detail_page.dart';
// ignore: unused_import
import 'package:gomuter_app/pages/pembeli/preorder_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PembeliHomePage extends StatefulWidget {
  const PembeliHomePage({super.key});

  @override
  State<PembeliHomePage> createState() => _PembeliHomePageState();
}

class _PembeliHomePageState extends State<PembeliHomePage> {
  // Theme Colors
  static const Color _primaryGreen = Color(0xFF1B7B5A);
  static const Color _secondaryGreen = Color(0xFF2D9D78);
  static const Color _lightGreen = Color(0xFFE8F5F0);
  // ignore: unused_field
  static const Color _accentPeach = Color(0xFFFAD4C0);

  bool _isLoading = true;
  bool _isSyncingLocation = false;
  bool _isLoadingNotifications = false;
  String? _error;
  List<dynamic> _pkls = [];
  List<dynamic> _favorites = [];
  Set<int> _favoriteIds = {};
  List<dynamic> _notifications = [];
  final TextEditingController _searchController = TextEditingController();
  // ignore: unused_field
  LatLng _initialCenter = const LatLng(-6.2, 106.8);
  // ignore: unused_field
  List<Marker> _markers = [];
  final List<int> _radiusOptions = [300, 500, 1000, 1500];
  int? _selectedRadius = 300;
  Timer? _locationTimer;
  static const Duration _locationInterval = Duration(minutes: 5);
  SharedPreferences? _prefs;
  Position? _buyerPosition;
  String _selectedCategory = 'Semua';
  final List<String> _categories = ['Semua', 'Makanan', 'Minuman', 'Snack'];
  String? _buyerName;

  int get _unreadNotificationsCount {
    var count = 0;
    for (final notif in _notifications) {
      if (notif is Map<String, dynamic>) {
        final isRead = notif['is_read'] == true;
        if (!isRead) count++;
      }
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> _getAccessToken() async {
    final token = await TokenManager.getValidAccessToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }
    final prefs = await _getPrefs();
    return prefs.getString('access_token');
  }

  Future<void> _initializePage() async {
    await _loadBuyerName();
    await _loadSavedRadius();
    await _loadPkls();
    await Future.wait([
      _loadFavorites(),
      _loadNotifications(silent: true),
    ]);
    await _syncLocation();
    _startLocationTimer();
  }

  Future<void> _loadBuyerName() async {
    final prefs = await _getPrefs();
    final username = prefs.getString('username');
    if (!mounted) return;
    setState(() {
      _buyerName = (username == null || username.isEmpty) ? null : username;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari aplikasi?'),
        content: const Text('Anda akan kembali ke halaman login.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TokenManager.clearTokens();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }


  Future<void> _loadSavedRadius() async {
    final prefs = await _getPrefs();
    final saved = prefs.getInt('buyer_radius');
    if (saved != null && _radiusOptions.contains(saved)) {
      setState(() {
        _selectedRadius = saved;
      });
    }
  }

  Future<void> _loadPkls({String? jenis}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _getAccessToken();

      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
        });
        return;
      }

      final data = await ApiService.getActivePKL(
        accessToken: token,
        query: jenis,
      );

      final markers = <Marker>[];
      LatLng? firstCenter;

      for (final item in data) {
        final pkl = item as Map<String, dynamic>;
        final lat = pkl['latest_latitude'];
        final lng = pkl['latest_longitude'];

        if (lat == null || lng == null) continue;

        final point = LatLng((lat as num).toDouble(), (lng as num).toDouble());
        firstCenter ??= point;

        markers.add(
          Marker(
            point: point,
            width: 40,
            height: 40,
            child: const Icon(Icons.location_on, size: 40, color: Colors.red),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _pkls = data;
        _markers = markers;
        if (firstCenter != null) {
          _initialCenter = firstCenter;
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat daftar PKL aktif: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startLocationTimer() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(_locationInterval, (_) {
      _syncLocation();
    });
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lokasi nonaktif. Aktifkan GPS.')),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi ditolak. Buka pengaturan untuk mengaktifkan.',
            ),
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<bool> _syncLocation() async {
    if (_isSyncingLocation) return _buyerPosition != null;
    if (!mounted) return false;
    setState(() {
      _isSyncingLocation = true;
    });

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) return false;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final token = await _getAccessToken();
      if (token == null) return false;

      if (mounted) {
        setState(() {
          _buyerPosition = position;
        });
      }

      await ApiService.updateBuyerLocation(
        token: token,
        latitude: position.latitude,
        longitude: position.longitude,
        radiusM: _selectedRadius,
      );
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyinkronkan lokasi: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingLocation = false;
        });
      }
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final token = await _getAccessToken();
      if (token == null) return;

      final data = await ApiService.getFavoritePKL(token: token);
      if (!mounted) return;

      final ids = <int>{};
      for (final fav in data) {
        final map = fav as Map<String, dynamic>;
        final pklId = map['pkl'];
        if (pklId is num) ids.add(pklId.toInt());
      }

      setState(() {
        _favorites = data;
        _favoriteIds = ids;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memuat favorit: $e')));
      }
    }
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingNotifications = true;
      });
    }

    try {
      final token = await _getAccessToken();
      if (token == null) return;

      final data = await ApiService.getNotifications(token: token);
      if (!mounted) return;

      setState(() {
        _notifications = data;
      });
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memuat notifikasi: $e')));
      }
    } finally {
      if (!silent && mounted) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  Future<void> _onRadiusChanged(int? radius) async {
    if (_selectedRadius == radius) return;
    final previous = _selectedRadius;
    setState(() {
      _selectedRadius = radius;
    });

    final prefs = await _getPrefs();
    if (radius == null) {
      await prefs.remove('buyer_radius');
      final activeCategory = _selectedCategory;
      await _loadPkls(jenis: activeCategory == 'Semua' ? null : activeCategory);
      return;
    }

    await prefs.setInt('buyer_radius', radius);

    var hasLocation = _buyerPosition != null;
    if (!hasLocation) {
      hasLocation = await _syncLocation();
    }

    if (!hasLocation) {
      if (mounted) {
        setState(() {
          _selectedRadius = previous;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktifkan layanan lokasi untuk memakai filter radius.'),
          ),
        );
      }
      if (previous == null) {
        await prefs.remove('buyer_radius');
      } else {
        await prefs.setInt('buyer_radius', previous);
      }
      return;
    }

    final activeCategory = _selectedCategory;
    await _loadPkls(
      jenis: activeCategory == 'Semua' ? null : activeCategory,
    );
  }

  Future<void> _toggleFavorite(int pklId) async {
    try {
      final token = await _getAccessToken();
      if (token == null) return;

      if (_favoriteIds.contains(pklId)) {
        await ApiService.removeFavoritePKL(token: token, pklId: pklId);
        if (!mounted) return;
        setState(() {
          _favoriteIds.remove(pklId);
          _favorites = _favorites.where((fav) {
            final favMap = fav as Map<String, dynamic>;
            final favId = favMap['pkl'];
            return favId is num && favId.toInt() != pklId;
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PKL dihapus dari favorit')),
        );
      } else {
        await ApiService.addFavoritePKL(token: token, pklId: pklId);
        if (!mounted) return;
        setState(() {
          _favoriteIds.add(pklId);
        });
        await _loadFavorites();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PKL ditambahkan ke favorit')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui favorit: $e')),
        );
      }
    }
  }

  Future<void> _markNotificationRead(int notificationId) async {
    try {
      final token = await _getAccessToken();
      if (token == null) return;

      await ApiService.markNotificationRead(
        token: token,
        notificationId: notificationId,
      );

      if (!mounted) return;
      setState(() {
        _notifications = _notifications.map((notif) {
          if (notif is Map<String, dynamic>) {
            final idValue = notif['id'];
            if (idValue is num && idValue.toInt() == notificationId) {
              return {...notif, 'is_read': true};
            }
          }
          return notif;
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui notifikasi: $e')),
        );
      }
    }
  }

  Future<void> _markAllNotificationsRead() async {
    final ids = <int>[];
    for (final notif in _notifications) {
      if (notif is Map<String, dynamic>) {
        final idValue = notif['id'];
        final isRead = notif['is_read'] == true;
        if (!isRead && idValue is num) {
          ids.add(idValue.toInt());
        }
      }
    }

    for (final id in ids) {
      await _markNotificationRead(id);
    }
  }

  // ignore: unused_element
  Widget _buildBadgeIcon({
    required IconData icon,
    required int count,
    Color? color,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color),
        if (count > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 9 ? '9+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  void _showFavoritesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.pink[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.pinkAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'PKL Favorit (${_favorites.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _loadFavorites();
                        },
                        icon: Icon(Icons.refresh_rounded, color: _primaryGreen),
                        tooltip: 'Muat ulang',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_favorites.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Belum ada PKL favorit',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: MediaQuery.of(ctx).size.height * 0.4,
                      child: ListView.separated(
                        itemCount: _favorites.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) {
                          final fav = _favorites[index] as Map<String, dynamic>;
                          final pklId = (fav['pkl'] as num?)?.toInt();
                          final nama = (fav['pkl_nama_usaha'] ?? '-') as String;
                          final jenis =
                              (fav['jenis_dagangan'] ?? '-') as String;

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _lightGreen,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getCategoryIcon(jenis),
                                  color: _primaryGreen,
                                ),
                              ),
                              title: Text(
                                nama,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                jenis,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                ),
                                onPressed: pklId == null
                                    ? null
                                    : () {
                                        Navigator.of(ctx).pop();
                                        _toggleFavorite(pklId);
                                      },
                              ),
                              onTap: () {
                                final jenisText = fav['jenis_dagangan'];
                                if (jenisText is String) {
                                  Navigator.of(ctx).pop();
                                  _searchController.text = jenisText;
                                  _loadPkls(jenis: jenisText);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var hasRequestedInitial = false;
        return StatefulBuilder(
          builder: (ctx, sheetSetState) {
            Future<void> refresh() async {
              await _loadNotifications();
              sheetSetState(() {});
            }

            Future<void> markRead(int? id) async {
              if (id == null) return;
              await _markNotificationRead(id);
              sheetSetState(() {});
            }

            Future<void> markAll() async {
              if (_unreadNotificationsCount == 0) return;
              await _markAllNotificationsRead();
              sheetSetState(() {});
            }

            if (!hasRequestedInitial) {
              hasRequestedInitial = true;
              Future.microtask(refresh);
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.7,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.notifications_rounded,
                                    color: Colors.orange[700],
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Notifikasi (${_notifications.length})',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: _primaryGreen,
                              ),
                              onPressed: _isLoadingNotifications
                                  ? null
                                  : refresh,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isLoadingNotifications)
                    LinearProgressIndicator(
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _unreadNotificationsCount == 0
                            ? null
                            : markAll,
                        child: Text(
                          'Tandai semua dibaca',
                          style: TextStyle(color: _primaryGreen),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _notifications.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 56,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Belum ada notifikasi',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, index) {
                              final notif =
                                  _notifications[index] as Map<String, dynamic>;
                              final notifId = (notif['id'] as num?)?.toInt();
                              final message =
                                  (notif['message'] ?? '-') as String;
                              final pklName =
                                  (notif['pkl_nama_usaha'] ?? '') as String;
                              final timeLabel = _formatTimestamp(
                                notif['created_at'],
                              );
                              final isRead = notif['is_read'] == true;

                              return Container(
                                decoration: BoxDecoration(
                                  color: isRead ? Colors.grey[50] : _lightGreen,
                                  borderRadius: BorderRadius.circular(16),
                                  border: isRead
                                      ? null
                                      : Border.all(
                                          color: _primaryGreen.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isRead
                                          ? Colors.grey[200]
                                          : _primaryGreen.withValues(
                                              alpha: 0.1,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isRead
                                          ? Icons.notifications_none_rounded
                                          : Icons.notifications_active_rounded,
                                      color: isRead
                                          ? Colors.grey
                                          : _primaryGreen,
                                    ),
                                  ),
                                  title: Text(
                                    message,
                                    style: TextStyle(
                                      fontWeight: isRead
                                          ? FontWeight.normal
                                          : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (pklName.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          pklName,
                                          style: TextStyle(
                                            color: _primaryGreen,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        timeLabel,
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: isRead
                                      ? null
                                      : TextButton(
                                          onPressed: () => markRead(notifId),
                                          child: Text(
                                            'Baca',
                                            style: TextStyle(
                                              color: _primaryGreen,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                  onTap: isRead
                                      ? null
                                      : () => markRead(notifId),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is String && value.isNotEmpty) {
      final date = DateTime.tryParse(value);
      if (date != null) {
        final local = date.toLocal();
        final day = local.day.toString().padLeft(2, '0');
        final month = local.month.toString().padLeft(2, '0');
        final hour = local.hour.toString().padLeft(2, '0');
        final minute = local.minute.toString().padLeft(2, '0');
        return '$day/$month ${local.year} • $hour:$minute';
      }
    }
    return '';
  }

  double? _distanceMetersForPKL(Map<String, dynamic> pkl) {
    final buyer = _buyerPosition;
    if (buyer == null) return null;
    final latRaw = pkl['latest_latitude'];
    final lngRaw = pkl['latest_longitude'];
    if (latRaw == null || lngRaw == null) return null;
    final lat = (latRaw as num).toDouble();
    final lng = (lngRaw as num).toDouble();
    return Geolocator.distanceBetween(
      buyer.latitude,
      buyer.longitude,
      lat,
      lng,
    );
  }

  String _distanceLabelForPKL(Map<String, dynamic> pkl) {
    final meters = _distanceMetersForPKL(pkl);
    if (meters == null) return '-';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  IconData _getCategoryIcon(String jenis) {
    final lowerJenis = jenis.toLowerCase();
    if (lowerJenis.contains('makan') ||
        lowerJenis.contains('nasi') ||
        lowerJenis.contains('mie')) {
      return Icons.restaurant;
    } else if (lowerJenis.contains('minum') ||
        lowerJenis.contains('es') ||
        lowerJenis.contains('jus')) {
      return Icons.local_drink;
    } else if (lowerJenis.contains('snack') ||
        lowerJenis.contains('gorengan')) {
      return Icons.bakery_dining;
    } else if (lowerJenis.contains('buah')) {
      return Icons.apple;
    } else if (lowerJenis.contains('sayur')) {
      return Icons.eco;
    }
    return Icons.storefront;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildRadiusFilter(),
            _buildCategoryChips(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _loadPkls(),
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadPkls();
                        await _loadFavorites();
                      },
                      child: _buildPKLList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryGreen, _secondaryGreen],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selamat Datang,',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buyerName ?? 'Pembeli',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Siap jelajahi kuliner favoritmu hari ini?',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  _buildHeaderIconButton(
                    icon: Icons.favorite_rounded,
                    badgeCount: _favorites.length,
                    onTap: _showFavoritesSheet,
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderIconButton(
                    icon: Icons.notifications_rounded,
                    badgeCount: _unreadNotificationsCount,
                    onTap: _showNotificationsSheet,
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderIconButton(
                    icon: Icons.logout_rounded,
                    badgeCount: 0,
                    onTap: _logout,
                    highlightColor: Colors.redAccent,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required int badgeCount,
    required VoidCallback onTap,
    Color? highlightColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (highlightColor ?? Colors.white).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: highlightColor ?? Colors.white, size: 22),
            if (badgeCount > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
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
      child: TextField(
        controller: _searchController,
        onSubmitted: (value) => _loadPkls(jenis: value.isEmpty ? null : value),
        decoration: InputDecoration(
          hintText: 'Cari PKL atau jenis dagangan...',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, color: _primaryGreen),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadPkls();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildRadiusFilter() {
    String formatRadius(int value) {
      if (value >= 1000) {
        final km = value / 1000;
        return km % 1 == 0 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km';
      }
      return '$value m';
    }

    final badgeText = _selectedRadius == null
      ? 'Tanpa batas'
      : formatRadius(_selectedRadius!);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.my_location, color: _primaryGreen),
                  const SizedBox(width: 8),
                  const Text(
                    'Radius pencarian',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_selectedRadius != null)
                    TextButton(
                      onPressed: () => _onRadiusChanged(null),
                      child: const Text('Hapus radius'),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _lightGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F5132),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _radiusOptions.map((radius) {
              final isSelected = radius == _selectedRadius;
              return ChoiceChip(
                label: Text(formatRadius(radius)),
                selected: isSelected,
                onSelected: (selected) {
                  _onRadiusChanged(selected ? radius : null);
                },
                selectedColor: _primaryGreen,
                backgroundColor: const Color(0xFFF5F7FA),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = category;
                });
                if (category == 'Semua') {
                  _loadPkls();
                } else {
                  _loadPkls(jenis: category);
                }
              },
              selectedColor: _primaryGreen,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPKLList() {
    final visiblePkls = _getVisiblePkls();

    if (visiblePkls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store_mall_directory_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Tidak ada PKL aktif',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ubah radius pencarian atau lokasi Anda',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: visiblePkls.length,
      itemBuilder: (context, index) {
        final pkl = visiblePkls[index];
        return _buildPKLCard(pkl);
      },
    );
  }

  List<Map<String, dynamic>> _getVisiblePkls() {
    final pkls = _pkls.whereType<Map<String, dynamic>>().toList();
    final buyer = _buyerPosition;
    if (buyer == null) return pkls;

    final radiusMeters = _selectedRadius?.toDouble();
    if (radiusMeters == null) return pkls;
    return pkls.where((pkl) {
      final distance = _distanceMetersForPKL(pkl);
      if (distance == null) return true;
      return distance <= radiusMeters;
    }).toList();
  }

  Widget _buildPKLCard(Map<String, dynamic> pkl) {
    final pklId = (pkl['id'] as num?)?.toInt();
    final nama = (pkl['nama_usaha'] ?? '-') as String;
    final jenis = (pkl['jenis_dagangan'] ?? '-') as String;
    final deskripsi = (pkl['deskripsi'] ?? '') as String;
    final isFavorite = pklId != null && _favoriteIds.contains(pklId);
    final distance = _distanceLabelForPKL(pkl);
    final avgRating = (pkl['average_rating'] as num?)?.toDouble();
    final ratingCount = (pkl['rating_count'] as num?)?.toInt() ?? 0;

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: pklId == null
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PklDetailPage(pklId: pklId),
                    ),
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: _lightGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getCategoryIcon(jenis),
                    size: 32,
                    color: _primaryGreen,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          jenis,
                          style: TextStyle(
                            color: _primaryGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (deskripsi.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          deskripsi,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Colors.amber[600] ?? Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            avgRating != null
                                ? avgRating.toStringAsFixed(1)
                                : 'Belum ada rating',
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (ratingCount > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '($ratingCount ulasan)',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            distance,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.pink : Colors.grey[400],
                      ),
                      onPressed: pklId == null
                          ? null
                          : () => _toggleFavorite(pklId),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chat_bubble_outline,
                        color: _primaryGreen,
                      ),
                      onPressed: pklId == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ChatPage(pklId: pklId, pklNama: nama),
                                ),
                              );
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
