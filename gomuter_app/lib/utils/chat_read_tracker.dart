import 'package:shared_preferences/shared_preferences.dart';

import 'chat_badge_manager.dart';

class ChatReadTracker {
  static const _prefix = 'chat_last_opened_';

  static String _key(ChatRole role, int chatId) =>
      '$_prefix${role.name}_$chatId';

  static Future<void> markOpened(ChatRole role, int chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(role, chatId),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  static Future<Map<int, DateTime>> getOpenedMap(ChatRole role) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$_prefix${role.name}_';
    final result = <int, DateTime>{};

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final idPart = key.substring(prefix.length);
      final chatId = int.tryParse(idPart);
      if (chatId == null) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw)?.toUtc();
      if (dt == null) continue;
      result[chatId] = dt;
    }

    return result;
  }

  static bool isUnread({
    required Map<int, DateTime> openedMap,
    required int chatId,
    required String? updatedAt,
  }) {
    if (updatedAt == null) return false;
    final updated = DateTime.tryParse(updatedAt)?.toUtc();
    if (updated == null) return false;

    final opened = openedMap[chatId];
    if (opened == null) return true;

    return updated.isAfter(opened);
  }
}
