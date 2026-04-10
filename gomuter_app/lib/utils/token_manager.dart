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
    if (access == null) return null;

    // Refresh proactively if token is expired OR will expire soon.
    final needsRefresh = _isExpired(access) || _expiresSoon(access);
    if (!needsRefresh) return access;

    return await _refreshAccessToken(prefs) ?? access;
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

    try {
      final response = await ApiService.refreshAccessToken(
        refreshToken: refresh,
      );
      final newAccess = response['access'] as String?;
      final newRefresh = (response['refresh'] as String?)?.trim();

      if (newAccess == null || newAccess.isEmpty) {
        return null;
      }

      await prefs.setString(_accessKey, newAccess);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await prefs.setString(_refreshKey, newRefresh);
      }
      return newAccess;
    } catch (_) {
      // Jika refresh gagal, token dibersihkan untuk memaksa login ulang.
      await clearTokens();
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
