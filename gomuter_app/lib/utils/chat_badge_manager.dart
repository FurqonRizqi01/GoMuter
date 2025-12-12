import 'package:shared_preferences/shared_preferences.dart';

enum ChatRole { pkl, pembeli }

class ChatBadgeManager {
  static const _pklKey = 'chat_last_seen_pkl';
  static const _pembeliKey = 'chat_last_seen_pembeli';

  static Future<DateTime> getLastSeen(ChatRole role) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(role));
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return (parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .toUtc();
  }

  static Future<void> markChatsSeen(ChatRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(role), DateTime.now().toUtc().toIso8601String());
  }

  static Future<int> countUnreadChats(
    List<dynamic> chats,
    ChatRole role,
  ) async {
    final lastSeen = await getLastSeen(role);
    var total = 0;
    for (final chat in chats) {
      if (chat is! Map) continue;
      final updatedRaw = chat['updated_at']?.toString();
      if (updatedRaw == null) continue;
      final updated = DateTime.tryParse(updatedRaw)?.toUtc();
      if (updated == null) continue;
      if (updated.isAfter(lastSeen)) {
        total++;
      }
    }
    return total;
  }

  static String _key(ChatRole role) {
    return role == ChatRole.pkl ? _pklKey : _pembeliKey;
  }
}
