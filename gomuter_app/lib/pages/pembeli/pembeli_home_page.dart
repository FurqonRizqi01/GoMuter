import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pembeli/pembeli_chat_list_page.dart';
import 'package:gomuter_app/pages/pembeli/pkl_detail_page.dart';
// ignore: unused_import
import 'package:gomuter_app/pages/pembeli/preorder_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:gomuter_app/utils/chat_badge_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class PembeliHomePage extends StatefulWidget {
  const PembeliHomePage({super.key});

  @override
  State<PembeliHomePage> createState() => _PembeliHomePageState();
}

class _PembeliHomePageState extends State<PembeliHomePage> {
  final ThemeManager _themeManager = ThemeManager();
  final MapController _mapController = MapController();
  final ScrollController _pklListController = ScrollController();

  bool _isLoading = true;
  bool _isSyncingLocation = false;
  bool _isLoadingNotifications = false;
  bool _hasCenteredMap = false;
  String? _error;
  String? _currentLocation;
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
  int _unreadChatCount = 0;

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
    _themeManager.addListener(_onThemeChanged);
    _initializePage();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    _searchController.dispose();
    _pklListController.dispose();
    _locationTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
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

  Future<void> _loadChatBadge() async {
    try {
      final token = await _getAccessToken();
      if (token == null) return;
      final chats = await ApiService.getChats(token: token);
      final count = await ChatBadgeManager.countUnreadChats(
        chats,
        ChatRole.pembeli,
      );
      if (!mounted) return;
      setState(() {
        _unreadChatCount = count;
      });
    } catch (_) {
      // Abaikan kesalahan badge agar tidak mengganggu UI utama.
    }
  }

  Future<void> _initializePage() async {
    await _loadBuyerName();
    await _loadSavedRadius();
    await _loadPkls();
    await Future.wait([
      _loadFavorites(),
      _loadNotifications(silent: true),
      _loadChatBadge(),
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

  Future<void> _openChatInbox() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PembeliChatListPage()),
    );
    await ChatBadgeManager.markChatsSeen(ChatRole.pembeli);
    await _loadChatBadge();
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

      String? address;
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = "${place.street}, ${place.subLocality}";
        }
      } catch (e) {
        debugPrint('Error getting address: $e');
      }

      final token = await _getAccessToken();
      if (token == null) return false;

      if (mounted) {
        setState(() {
          _buyerPosition = position;
          if (address != null) {
            _currentLocation = address;
          } else {
            _currentLocation = 'Lokasi Anda';
          }
        });

        if (!_hasCenteredMap) {
          _hasCenteredMap = true;
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            15.0,
          );
        }
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
            content: Text(
              'Aktifkan layanan lokasi untuk memakai filter radius.',
            ),
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
    await _loadPkls(jenis: activeCategory == 'Semua' ? null : activeCategory);
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
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: _themeManager.primaryGreen,
                        ),
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
                                  color: _themeManager.lightGreen,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getCategoryIcon(jenis),
                                  color: _themeManager.primaryGreen,
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
              decoration: BoxDecoration(
                color: _themeManager.isDarkMode
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
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
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _themeManager.isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: _themeManager.primaryGreen,
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _themeManager.primaryGreen,
                      ),
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
                          style: TextStyle(color: _themeManager.primaryGreen),
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
                                  color: isRead
                                      ? (_themeManager.isDarkMode
                                          ? Colors.transparent
                                          : Colors.grey[50])
                                      : (_themeManager.isDarkMode
                                          ? _themeManager.primaryGreen
                                              .withValues(alpha: 0.1)
                                          : _themeManager.lightGreen),
                                  borderRadius: BorderRadius.circular(16),
                                  border: isRead
                                      ? Border.all(
                                          color: _themeManager.isDarkMode
                                              ? Colors.white
                                                  .withValues(alpha: 0.1)
                                              : Colors.transparent,
                                        )
                                      : Border.all(
                                          color: _themeManager.primaryGreen
                                              .withValues(
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
                                          ? (_themeManager.isDarkMode
                                              ? Colors.grey[800]
                                              : Colors.grey[200])
                                          : _themeManager.primaryGreen
                                              .withValues(
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
                                          : _themeManager.primaryGreen,
                                    ),
                                  ),
                                  title: Text(
                                    message,
                                    style: TextStyle(
                                      fontWeight: isRead
                                          ? FontWeight.normal
                                          : FontWeight.w600,
                                      fontSize: 14,
                                      color: _themeManager.isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
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
                                            color: _themeManager.primaryGreen,
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
                                              color: _themeManager.primaryGreen,
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
    final isDark = _themeManager.isDarkMode;
    final bgColor = _themeManager.backgroundColor;
    final textColor = _themeManager.textColor;
    final cardColor = _themeManager.cardColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.gomuter.app',
                  tileBuilder: (context, widget, tile) {
                    if (isDark) {
                      return ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          -1, 0, 0, 0, 255,
                          0, -1, 0, 0, 255,
                          0, 0, -1, 0, 255,
                          0, 0, 0, 1, 0,
                        ]),
                        child: widget,
                      );
                    }
                    return widget;
                  },
                ),
                MarkerLayer(markers: _markers),
                if (_buyerPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _buyerPosition!.latitude,
                          _buyerPosition!.longitude,
                        ),
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 260,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'my_location_fab',
              backgroundColor: const Color(0xFFE67E22), // Orange color like image
              onPressed: () {
                if (_buyerPosition != null) {
                  _mapController.move(
                    LatLng(
                      _buyerPosition!.latitude,
                      _buyerPosition!.longitude,
                    ),
                    15.0,
                  );
                } else {
                  _syncLocation();
                }
              },
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isDark
                        ? Colors.black.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.95),
                    isDark
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(textColor),
                    _buildSearchBar(cardColor, textColor),
                    _buildCategoryChips(cardColor, textColor),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 180, // Smaller height
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(color: textColor),
                            ),
                          ),
                        )
                      : _buildPKLList(cardColor, textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Halo, ${_buyerName ?? 'Pembeli'}!',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: textColor.withValues(alpha: 0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _currentLocation ?? 'Memuat lokasi...',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeaderIconButton(
                    icon: _themeManager.isDarkMode
                        ? Icons.light_mode
                        : Icons.dark_mode,
                    badgeCount: 0,
                    onTap: () {
                      _themeManager.toggleTheme();
                    },
                    iconColor: textColor,
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderIconButton(
                    icon: Icons.favorite_rounded,
                    badgeCount: _favorites.length,
                    onTap: _showFavoritesSheet,
                    iconColor: textColor,
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderIconButton(
                    icon: Icons.chat_bubble_rounded,
                    badgeCount: _unreadChatCount,
                    onTap: _openChatInbox,
                    highlightColor: Colors.blueAccent,
                    iconColor: textColor,
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderIconButton(
                    icon: Icons.notifications_rounded,
                    badgeCount: _unreadNotificationsCount,
                    onTap: _showNotificationsSheet,
                    iconColor: textColor,
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderIconButton(
                    icon: Icons.logout_rounded,
                    badgeCount: 0,
                    onTap: _logout,
                    highlightColor: Colors.redAccent,
                    iconColor: textColor,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRadiusFilter(textColor),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required int badgeCount,
    required VoidCallback onTap,
    Color? highlightColor,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (highlightColor ?? iconColor ?? Colors.white)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (iconColor ?? Colors.white).withValues(alpha: 0.1),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              icon,
              color: highlightColor ?? iconColor ?? Colors.white,
              size: 22,
            ),
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

  Widget _buildSearchBar(Color cardColor, Color textColor) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: textColor),
        cursorColor: _themeManager.primaryGreen,
        onSubmitted: (value) => _loadPkls(jenis: value.isEmpty ? null : value),
        decoration: InputDecoration(
          hintText: 'Cari PKL atau jenis dagangan...',
          hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF1B7B5A)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: textColor.withValues(alpha: 0.5),
                  ),
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

  Widget _buildRadiusFilter(Color textColor) {
    String formatRadius(int value) {
      if (value >= 1000) {
        final km = value / 1000;
        return km % 1 == 0
            ? '${km.toStringAsFixed(0)} km'
            : '${km.toStringAsFixed(1)} km';
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
        color: _themeManager.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
                  const Icon(Icons.my_location, color: Color(0xFF1B7B5A)),
                  const SizedBox(width: 8),
                  Text(
                    'Radius pencarian',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_selectedRadius != null)
                    TextButton(
                      onPressed: () => _onRadiusChanged(null),
                      child: Text(
                        'Hapus radius',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B7B5A).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B7B5A),
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
                selectedColor: const Color(0xFF1B7B5A),
                backgroundColor: _themeManager.isDarkMode
                    ? const Color(0xFF2C2C2C)
                    : Colors.grey[100],
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : textColor.withValues(alpha: 0.6),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF1B7B5A)
                      : textColor.withValues(alpha: 0.1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(Color cardColor, Color textColor) {
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
              selectedColor: const Color(0xFF1B7B5A),
              backgroundColor: cardColor,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : textColor.withValues(alpha: 0.6),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF1B7B5A)
                    : textColor.withValues(alpha: 0.1),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPKLList(Color cardColor, Color textColor) {
    final visiblePkls = _getVisiblePkls();

    if (visiblePkls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store_mall_directory_outlined,
              size: 64,
              color: textColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Tidak ada PKL aktif',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ListView.builder(
          controller: _pklListController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: visiblePkls.length,
          itemBuilder: (context, index) {
            final pkl = visiblePkls[index];
            return _buildPKLCard(pkl, cardColor, textColor);
          },
        ),
        Positioned(
          left: 0,
          child: Center(
            child: IconButton(
              onPressed: () {
                _pklListController.animateTo(
                  _pklListController.offset - 280,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chevron_left,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: Center(
            child: IconButton(
              onPressed: () {
                _pklListController.animateTo(
                  _pklListController.offset + 280,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chevron_right,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ],
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

  Widget _buildPKLCard(
    Map<String, dynamic> pkl,
    Color cardColor,
    Color textColor,
  ) {
    final pklId = (pkl['id'] as num?)?.toInt();
    final nama = (pkl['nama_usaha'] ?? '-') as String;
    final jenis = (pkl['jenis_dagangan'] ?? '-') as String;
    final distance = _distanceLabelForPKL(pkl);
    final avgRating = (pkl['average_rating'] as num?)?.toDouble();
    final lat = (pkl['latest_latitude'] as num?)?.toDouble();
    final lng = (pkl['latest_longitude'] as num?)?.toDouble();

    return Container(
      width: 240, // Smaller width
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: pklId == null
              ? null
              : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PklDetailPage(pklId: pklId),
                    ),
                  );
                  await _loadChatBadge();
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: _themeManager.isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[200],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _getCategoryIcon(jenis),
                      size: 40,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3, // Increased flex for content
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              nama,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (avgRating != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  avgRating.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: textColor.withValues(alpha: 0.5),
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            distance,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _themeManager.primaryGreen
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              jenis,
                              style: TextStyle(
                                color: _themeManager.primaryGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton.icon(
                          onPressed: (lat != null && lng != null)
                              ? () async {
                                  final url = Uri.parse(
                                    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                                  );
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(
                                      url,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE67E22),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.navigation, size: 14),
                          label: const Text(
                            'Navigasi',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
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
