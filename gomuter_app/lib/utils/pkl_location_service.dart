import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Service sinkronisasi lokasi PKL ke backend (manual dan berkala otomatis).
class PklLocationService with WidgetsBindingObserver {
  static final PklLocationService _instance = PklLocationService._internal();
  factory PklLocationService() => _instance;
  PklLocationService._internal();

  static const _prefsLastUpdateKey = 'pkl_last_location_update_iso';
  static const _prefsAutoModeKey = 'pkl_location_auto_mode';
  // Interval update lokasi otomatis (menit).
  static const _updateIntervalMinutes = 2;

  Timer? _locationTimer;
  bool _isUpdating = false;
  bool _isAutoMode = false;
  DateTime? _lastUpdate;
  String? _lastError;
  bool _initialized = false;
  bool _lifecycleAttached = false;

  // Listeners untuk update UI
  final List<Function()> _listeners = [];

  bool get isAutoMode => _isAutoMode;
  bool get isUpdating => _isUpdating;
  DateTime? get lastUpdate => _lastUpdate;
  String? get lastError => _lastError;

  void addListener(Function() listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    final listeners = List<Function()>.from(_listeners);
    for (final listener in listeners) {
      listener();
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      _attachLifecycle();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastIso = prefs.getString(_prefsLastUpdateKey);
    _lastUpdate = lastIso != null
        ? DateTime.tryParse(lastIso)?.toLocal()
        : null;

    _isAutoMode = prefs.getBool(_prefsAutoModeKey) ?? false;

    _initialized = true;
    _attachLifecycle();

    if (_isAutoMode) {
      await startAutoSync(showSnack: false);
    }
  }

  void _attachLifecycle() {
    if (_lifecycleAttached) return;
    _lifecycleAttached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Best-effort behavior:
    // - When app is backgrounded, Dart timers may be paused by OS anyway.
    // - We stop the timer to avoid drift; on resume we restart if auto mode is enabled.
    if (state == AppLifecycleState.resumed) {
      if (_isAutoMode && _locationTimer == null) {
        // Restart without showing snack.
        unawaited(startAutoSync(showSnack: false));
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  Future<bool> _ensureLocationAccess() async {
    // Validasi service lokasi aktif dan permission diberikan user.
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<bool> updateLocation({bool showSnack = true}) async {
    // Trigger update lokasi satu kali (mode manual).
    if (_isUpdating) return false;

    _isUpdating = true;
    _lastError = null;
    _notifyListeners();

    try {
      return await _updateLocationInternal().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          _lastError = 'Timeout saat update lokasi.';
          return false;
        },
      );
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _isUpdating = false;
      _notifyListeners();
    }
  }

  Future<bool> _updateLocationInternal() async {
    try {
      Future<String?> getToken({required bool forceRefresh}) async {
        return forceRefresh
            ? TokenManager.forceRefreshAccessToken()
            : TokenManager.getValidAccessToken();
      }

      var token = await getToken(forceRefresh: false);
      if (token == null || token.isEmpty) {
        _lastError = 'Sesi habis. Silakan login ulang.';
        return false;
      }

      final verified = await _ensureVerifiedProfile(token);
      if (!verified) {
        return false;
      }

      final hasAccess = await _ensureLocationAccess();
      if (!hasAccess) {
        _lastError = 'Izin/layanan lokasi belum aktif.';
        return false;
      }

      // Fast path (native): use last known position first (usually instant).
      // On web, getLastKnownPosition is not supported, so skip it.
      Position? position;
      if (!kIsWeb) {
        try {
          position = await Geolocator.getLastKnownPosition();
        } on UnsupportedError {
          position = null;
        } catch (_) {
          position = null;
        }
      }

      // Fallback: actively query current position.
      final Position currentPosition;
      try {
        currentPosition = position ??
            await Geolocator.getCurrentPosition(
              desiredAccuracy:
                  kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
              timeLimit: const Duration(seconds: 15),
            );
      } on TimeoutException {
        _lastError = 'Timeout saat mengambil GPS.';
        return false;
      } catch (e) {
        _lastError = 'Gagal mengambil lokasi: ${e.toString()}';
        return false;
      }

      Future<void> callUpdateWithToken(String currentToken) async {
        // Kirim koordinat terbaru ke endpoint backend /api/pkl/update-location/.
        await ApiService.updatePKLLocation(
          token: currentToken,
          latitude: currentPosition.latitude,
          longitude: currentPosition.longitude,
        );
      }

      try {
        await callUpdateWithToken(token);
      } catch (e) {
        final msg = e.toString();
        final isUnauthorized =
            msg.contains('Unauthorized (401)') || msg.contains('(401)');
        if (!isUnauthorized) rethrow;

        token = await getToken(forceRefresh: true);
        if (token == null || token.isEmpty) {
          _lastError = 'Sesi habis. Silakan login ulang.';
          return false;
        }
        await callUpdateWithToken(token);
      }

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLastUpdateKey, now.toIso8601String());

      _lastUpdate = now;
      _notifyListeners();

      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<bool> _ensureVerifiedProfile(String token) async {
    try {
      // Pembaruan lokasi hanya boleh berjalan setelah profil usaha diterima admin.
      final profile = await ApiService.getPKLProfile(token);
      final status = (profile?['status_verifikasi'] ?? 'PENDING')
          .toString()
          .toUpperCase();
      if (status == 'DITERIMA' || status == 'VERIFIED') {
        return true;
      }

      _lastError = status == 'DITOLAK'
          ? 'Profil usaha ditolak admin. Perbaiki data terlebih dahulu.'
          : 'Profil usaha masih menunggu verifikasi admin.';
      // Mode otomatis dimatikan agar PKL pending/ditolak tidak terus mengirim lokasi.
      await _disableAutoMode();
      return false;
    } catch (e) {
      _lastError = 'Gagal mengecek status verifikasi profil. $e';
      return false;
    }
  }

  Future<void> _disableAutoMode() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _isAutoMode = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoModeKey, false);
    _notifyListeners();
  }

  Future<void> startAutoSync({bool showSnack = true}) async {
    // Mengaktifkan mode otomatis dan membuat timer periodik update lokasi.
    _locationTimer?.cancel();
    _locationTimer = null;

    final token = await TokenManager.getValidAccessToken();
    if (token == null || token.isEmpty) {
      _lastError = 'Sesi habis. Silakan login ulang.';
      await _disableAutoMode();
      return;
    }

    final verified = await _ensureVerifiedProfile(token);
    if (!verified) {
      // Jika belum terverifikasi, proses timer otomatis tidak dibuat.
      return;
    }

    final hasAccess = await _ensureLocationAccess();
    if (!hasAccess) {
      await _disableAutoMode();
      return;
    }

    _isAutoMode = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoModeKey, true);

    // Immediate sync
    await updateLocation(showSnack: false);

    _locationTimer = Timer.periodic(Duration(minutes: _updateIntervalMinutes), (
      _,
    ) {
      if (_isAutoMode) {
        updateLocation(showSnack: false);
      }
    });

    _notifyListeners();
  }

  Future<void> stopAutoSync({bool showSnack = true}) async {
    // Mematikan mode otomatis dan menghentikan timer periodik.
    _locationTimer?.cancel();
    _locationTimer = null;
    _isAutoMode = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoModeKey, false);

    _notifyListeners();
  }


  void dispose() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _listeners.clear();

    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }

    _initialized = false;
  }
}
