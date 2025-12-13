import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;

  ThemeManager._internal() {
    _loadTheme();
  }

  bool _isDarkMode = true;
  bool get isDarkMode => _isDarkMode;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('is_dark_mode') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);
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
