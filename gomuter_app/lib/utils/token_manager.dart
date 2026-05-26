import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';

// Pengelola token JWT di sisi mobile (simpan, validasi, dan refresh token).
class TokenManager {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  // Jeda aman untuk refresh sebelum token benar-benar kedaluwarsa.
  static const Duration _refreshSkew = Duration(minutes: 2);

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  // Mengembalikan access token yang masih valid; refresh otomatis jika diperlukan.
  static Future<String?> getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_accessKey);
    if (access == null || access.isEmpty) {
      // Jika access token tidak ada tetapi refresh token masih ada,
      // aplikasi mencoba membuat access token baru tanpa meminta login ulang.
      return _refreshAccessToken(prefs);
    }

    // Access token yang habis/nyaris habis tidak dipakai lagi untuk request API.
    final needsRefresh = _isExpired(access) || _expiresSoon(access);
    if (!needsRefresh) return access;

    return _refreshAccessToken(prefs);
  }

  static Future<String?> forceRefreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return _refreshAccessToken(prefs);
  }

  // Memanggil endpoint refresh token backend lalu menyimpan token baru.
  static Future<String?> _refreshAccessToken(SharedPreferences prefs) async {
    final refresh = prefs.getString(_refreshKey);
    if (refresh == null || refresh.isEmpty) {
      return null;
    }
    if (_isExpired(refresh)) {
      // Refresh token adalah batas sesi utama; jika habis, pengguna harus login lagi.
      await clearTokens();
      return null;
    }

    try {
      final response = await ApiService.refreshAccessToken(
        refreshToken: refresh,
      );
      final newAccess = response['access'] as String?;
      final newRefresh = (response['refresh'] as String?)?.trim();

      if (newAccess == null || newAccess.isEmpty) {
        return null;
      }

      // Simpan access token baru, dan simpan refresh token baru jika backend merotasi token.
      await prefs.setString(_accessKey, newAccess);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await prefs.setString(_refreshKey, newRefresh);
      }
      return newAccess;
    } catch (_) {
      // Jangan hapus refresh token untuk error sementara seperti koneksi/CORS/server.
      // Token akan dicoba refresh lagi saat aplikasi dibuka atau request berikutnya.
      return null;
    }
  }

  static bool _isExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      // Jika token rusak, paksa refresh.
      return true;
    }
  }

  static bool _expiresSoon(String token) {
    try {
      final expiry = JwtDecoder.getExpirationDate(token);
      final remaining = expiry.difference(DateTime.now());
      return remaining <= _refreshSkew;
    } catch (_) {
      return true;
    }
  }
}
