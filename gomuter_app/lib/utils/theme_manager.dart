import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;

  ThemeManager._internal() {
    _loadTheme();
  }

  static const String _anonymousPrefKey = 'is_dark_mode_anonymous';

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  String _preferenceKey = _anonymousPrefKey;
  String get preferenceKey => _preferenceKey;

  static String _sanitizeKeyPart(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  }

  static String buildUserPreferenceKey({
    required String role,
    required String username,
  }) {
    return 'is_dark_mode_${_sanitizeKeyPart(role)}_${_sanitizeKeyPart(username)}';
  }

  Future<void> useAnonymousTheme() async {
    _preferenceKey = _anonymousPrefKey;
    await _loadThemeForKey(_preferenceKey);
  }

  Future<void> useUserTheme({
    required String role,
    required String username,
  }) async {
    _preferenceKey = buildUserPreferenceKey(role: role, username: username);
    await _loadThemeForKey(_preferenceKey);
  }

  Future<void> setDarkMode(bool isDarkMode) async {
    _isDarkMode = isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final username = (prefs.getString('username') ?? '').trim();
    final role = (prefs.getString('user_role') ?? '').trim();

    if (username.isNotEmpty && role.isNotEmpty) {
      _preferenceKey = buildUserPreferenceKey(role: role, username: username);
    } else {
      _preferenceKey = _anonymousPrefKey;
    }

    await _loadThemeForKey(_preferenceKey);
  }

  Future<void> _loadThemeForKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == _anonymousPrefKey) {
      _isDarkMode = false;
    } else {
      _isDarkMode = prefs.getBool(key) ?? false;
    }
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, _isDarkMode);
    notifyListeners();
  }

  // Colors

  /// Brand
  Color get primaryGreen => const Color(0xFF1B7B5A);
  Color get lightGreen => const Color(0xFFE8F5F0);

  /// Premium accent (gold/amber) for highlights/CTAs.
  Color get accentGold => const Color(0xFFF29F3D);

  /// Surfaces
  /// Warm dark surfaces for an elegant "premium" look (less harsh than green-on-black).
  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF140F0A) : const Color(0xFFF5F5F5);
  Color get cardColor => _isDarkMode ? const Color(0xFF1E1711) : Colors.white;
  Color get surfaceColor =>
      _isDarkMode ? const Color(0xFF261D16) : (Colors.grey[50] ?? Colors.white);

  /// Text
  Color get textColor => _isDarkMode ? const Color(0xFFF5EFE7) : Colors.black87;
  Color get mutedTextColor =>
      _isDarkMode ? const Color(0xFFB8ABA1) : Colors.black54;
  Color get hintTextColor =>
      _isDarkMode ? const Color(0xFF8E8279) : Colors.black45;

  /// Lines
  Color get borderColor => _isDarkMode
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.08);

  /// Accents
  Color get accentSurfaceColor =>
      _isDarkMode ? Colors.white.withValues(alpha: 0.06) : lightGreen;
  Color get overlayScrimColor => _isDarkMode
      ? Colors.black.withValues(alpha: 0.65)
      : Colors.white.withValues(alpha: 0.95);
}
