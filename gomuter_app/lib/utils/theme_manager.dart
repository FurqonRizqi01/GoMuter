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
  Color get backgroundColor => _isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
  Color get cardColor => _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
  Color get textColor => _isDarkMode ? Colors.white : Colors.black87;
  Color get primaryGreen => const Color(0xFF1B7B5A);
  Color get lightGreen => const Color(0xFFE8F5F0);
}
