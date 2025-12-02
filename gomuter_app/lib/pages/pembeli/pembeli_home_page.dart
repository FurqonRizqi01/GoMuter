import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pembeli/chat_page.dart';
import 'package:gomuter_app/pages/pembeli/preorder_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PembeliHomePage extends StatefulWidget {
  const PembeliHomePage({super.key});

  @override
  State<PembeliHomePage> createState() => _PembeliHomePageState();
}

class _PembeliHomePageState extends State<PembeliHomePage> {
  bool _isLoading = true;
  bool _isSyncingLocation = false;
  bool _isLoadingNotifications = false;
  String? _error;
  List<dynamic> _pkls = [];
  List<dynamic> _favorites = [];
  Set<int> _favoriteIds = {};
  List<dynamic> _notifications = [];
  final TextEditingController _searchController = TextEditingController();
  LatLng _initialCenter = const LatLng(-6.2, 106.8);
  List<Marker> _markers = [];
  final List<int> _radiusOptions = [300, 500, 1000, 1500];
  int _selectedRadius = 300;
  Timer? _locationTimer;
  static const Duration _locationInterval = Duration(minutes: 5);
  SharedPreferences? _prefs;

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
    final prefs = await _getPrefs();
    return prefs.getString('access_token');
  }

  Future<void> _initializePage() async {
    await _loadSavedRadius();
    await _loadPkls();
    await Future.wait([_loadFavorites(), _loadNotifications(silent: true)]);
    await _syncLocation();
    _startLocationTimer();
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

  Future<void> _syncLocation() async {
    if (_isSyncingLocation) return;
    setState(() {
      _isSyncingLocation = true;
    });

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final token = await _getAccessToken();
      if (token == null) return;

      await ApiService.updateBuyerLocation(
        token: token,
        latitude: position.latitude,
        longitude: position.longitude,
        radiusM: _selectedRadius,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyinkronkan lokasi: $e')),
        );
      }
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

  Future<void> _onRadiusChanged(int radius) async {
    if (_selectedRadius == radius) return;
    setState(() {
      _selectedRadius = radius;
    });

    final prefs = await _getPrefs();
    await prefs.setInt('buyer_radius', radius);
    await _syncLocation();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dihapus dari favorit.')));
      } else {
        final fav = await ApiService.addFavoritePKL(token: token, pklId: pklId);
        if (!mounted) return;
        setState(() {
          _favoriteIds.add(pklId);
          _favorites = [..._favorites, fav];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ditambahkan ke favorit.')),
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
                    Text(
                      'PKL Favorit (${_favorites.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _loadFavorites();
                      },
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Muat ulang',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_favorites.isEmpty)
                  const Text(
                    'Belum ada PKL favorit. Gunakan ikon hati pada daftar untuk menambahkannya.',
                  )
                else
                  SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.5,
                    child: ListView.separated(
                      itemCount: _favorites.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final fav = _favorites[index] as Map<String, dynamic>;
                        final pklId = (fav['pkl'] as num?)?.toInt();
                        final nama = (fav['pkl_nama_usaha'] ?? '-') as String;
                        final jenis = (fav['jenis_dagangan'] ?? '-') as String;

                        return ListTile(
                          dense: true,
                          title: Text(nama),
                          subtitle: Text(jenis),
                          onTap: () {
                            final jenisText = fav['jenis_dagangan'];
                            if (jenisText is String) {
                              Navigator.of(ctx).pop();
                              _searchController.text = jenisText;
                              _loadPkls(jenis: jenisText);
                            }
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Hapus favorit',
                            onPressed: pklId == null
                                ? null
                                : () {
                                    Navigator.of(ctx).pop();
                                    _toggleFavorite(pklId);
                                  },
                          ),
                        );
                      },
                    ),
                  ),
              ],
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

            final sheetHeight = MediaQuery.of(ctx).size.height * 0.65;

            if (!hasRequestedInitial) {
              hasRequestedInitial = true;
              Future.microtask(refresh);
            }

            return SafeArea(
              child: SizedBox(
                height: sheetHeight,
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Notifikasi (${_notifications.length})'),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Muat ulang',
                        onPressed: _isLoadingNotifications ? null : refresh,
                      ),
                    ),
                    if (_isLoadingNotifications)
                      const LinearProgressIndicator(minHeight: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _unreadNotificationsCount == 0
                              ? null
                              : markAll,
                          child: const Text('Tandai semua dibaca'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _notifications.isEmpty
                          ? const Center(
                              child: Text('Belum ada notifikasi radius.'),
                            )
                          : ListView.separated(
                              itemCount: _notifications.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final notif =
                                    _notifications[index]
                                        as Map<String, dynamic>;
                                final notifId = (notif['id'] as num?)?.toInt();
                                final message =
                                    (notif['message'] ?? '-') as String;
                                final pklName =
                                    (notif['pkl_nama_usaha'] ?? '') as String;
                                final radius = notif['radius_m'];
                                final distance = notif['distance_m'];
                                final timeLabel = _formatTimestamp(
                                  notif['created_at'],
                                );
                                final details = <String>[];
                                if (pklName.isNotEmpty) details.add(pklName);
                                if (radius is num) {
                                  details.add('Radius ${radius.toInt()} m');
                                }
                                if (distance is num) {
                                  final dist = distance.toDouble();
                                  details.add(
                                    'Jarak ${dist.toStringAsFixed(0)} m',
                                  );
                                }
                                if (timeLabel.isNotEmpty)
                                  details.add(timeLabel);
                                final detailText = details.join(' • ');
                                final isRead = notif['is_read'] == true;

                                return ListTile(
                                  leading: Icon(
                                    isRead
                                        ? Icons.notifications_none
                                        : Icons.notifications_active,
                                    color: isRead
                                        ? Colors.grey
                                        : Colors.orangeAccent,
                                  ),
                                  tileColor: isRead
                                      ? null
                                      : Colors.orange.withOpacity(0.08),
                                  title: Text(message),
                                  subtitle: detailText.isEmpty
                                      ? null
                                      : Text(detailText),
                                  trailing: isRead
                                      ? null
                                      : TextButton(
                                          onPressed: () => markRead(notifId),
                                          child: const Text('Sudah dibaca'),
                                        ),
                                  onTap: isRead
                                      ? null
                                      : () => markRead(notifId),
                                );
                              },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GoMuter - Pembeli'),
        actions: [
          IconButton(
            tooltip: 'Notifikasi',
            icon: _buildBadgeIcon(
              icon: Icons.notifications,
              count: _unreadNotificationsCount,
            ),
            onPressed: () {
              _showNotificationsSheet();
            },
          ),
          IconButton(
            tooltip: 'Favorit',
            icon: _buildBadgeIcon(
              icon: Icons.favorite,
              count: _favoriteIds.length,
              color: Colors.pinkAccent,
            ),
            onPressed: _showFavoritesSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading
                ? null
                : () {
                    final jenis = _searchController.text.trim();
                    _loadPkls(jenis: jenis.isEmpty ? null : jenis);
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Cari berdasarkan jenis dagangan',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      final jenis = value.trim();
                      _loadPkls(jenis: jenis.isEmpty ? null : jenis);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          final jenis = _searchController.text.trim();
                          _loadPkls(jenis: jenis.isEmpty ? null : jenis);
                        },
                  child: const Text('Cari'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedRadius,
                    decoration: const InputDecoration(
                      labelText: 'Radius notifikasi (meter)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _radiusOptions
                        .map(
                          (radius) => DropdownMenuItem<int>(
                            value: radius,
                            child: Text('$radius m'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _onRadiusChanged(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSyncingLocation ? null : _syncLocation,
                  icon: _isSyncingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: const Text('Sinkron lokasi'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : _pkls.isEmpty
                ? const Center(
                    child: Text('Tidak ada PKL dengan kriteria tersebut.'),
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: 250,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: _initialCenter,
                            initialZoom: 14,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.example.gomuter_app',
                            ),
                            MarkerLayer(markers: _markers),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _pkls.length,
                          itemBuilder: (context, index) {
                            final pkl = _pkls[index] as Map<String, dynamic>;
                            final namaUsaha =
                                (pkl['nama_usaha'] ?? '-') as String;
                            final jenisDagangan =
                                (pkl['jenis_dagangan'] ?? '-') as String;
                            final jam =
                                (pkl['jam_operasional'] ?? '-') as String;
                            final alamat =
                                (pkl['alamat_domisili'] ?? '-') as String;
                            final pklId = (pkl['id'] as num?)?.toInt();
                            final isFavorite =
                                pklId != null && _favoriteIds.contains(pklId);

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: ListTile(
                                title: Text(namaUsaha),
                                subtitle: Text(
                                  '$jenisDagangan\nJam: $jam\nAlamat: $alamat',
                                ),
                                isThreeLine: true,
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isFavorite
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: Colors.pinkAccent,
                                      ),
                                      tooltip: isFavorite
                                          ? 'Hapus favorit'
                                          : 'Jadikan favorit',
                                      onPressed: pklId == null
                                          ? null
                                          : () => _toggleFavorite(pklId),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.receipt_long),
                                      tooltip: 'Pre-order',
                                      onPressed: () {
                                        final pklIdentifier = pkl['id'];
                                        if (pklIdentifier == null) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PreOrderPage(
                                              pklId: (pklIdentifier as num)
                                                  .toInt(),
                                              pklName: namaUsaha,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chat),
                                      tooltip: 'Chat',
                                      onPressed: () {
                                        final pklIdentifier = pkl['id'];
                                        if (pklIdentifier == null) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatPage(
                                              pklId: (pklIdentifier as num)
                                                  .toInt(),
                                              pklNama: namaUsaha,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
