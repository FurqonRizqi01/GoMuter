import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';

class TokenManager {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  static Future<void> saveTokens({required String access, required String refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  static Future<String?> getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_accessKey);
    if (access == null) return null;

    final isExpired = _isExpired(access);
    if (!isExpired) {
      return access;
    }

    return _refreshAccessToken(prefs);
  }

  static Future<String?> forceRefreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return _refreshAccessToken(prefs);
  }

  static Future<String?> _refreshAccessToken(SharedPreferences prefs) async {
    final refresh = prefs.getString(_refreshKey);
    if (refresh == null || refresh.isEmpty) {
      return null;
    }

    try {
      final response = await ApiService.refreshAccessToken(refreshToken: refresh);
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
}
