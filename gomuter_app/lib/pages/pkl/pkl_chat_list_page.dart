import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pkl/pkl_chat_room_page.dart';
import 'package:gomuter_app/utils/chat_badge_manager.dart';
import 'package:gomuter_app/utils/chat_read_tracker.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PklChatListPage extends StatefulWidget {
  const PklChatListPage({super.key});

  @override
  State<PklChatListPage> createState() => _PklChatListPageState();
}

class _PklChatListPageState extends State<PklChatListPage> {
  final ThemeManager _themeManager = ThemeManager();
  bool _isLoading = true;
  String? _error;
  List<dynamic> _chats = [];
  Map<int, DateTime> _openedMap = <int, DateTime>{};
  bool _showSearch = false;
  String _searchQuery = '';
  int _filterIndex = 0; // 0: semua, 1: belum dibaca
  String _myInitial = 'P';

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    _loadChats();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadMyInitial();
  }

  Future<void> _loadMyInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final username = (prefs.getString('username') ?? '').trim();
    if (!mounted) return;
    setState(() {
      _myInitial = username.isEmpty ? 'P' : username[0].toUpperCase();
    });
  }

  Future<void> _refreshOpenedMap() async {
    final map = await ChatReadTracker.getOpenedMap(ChatRole.pkl);
    if (!mounted) return;
    setState(() {
      _openedMap = map;
    });
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await TokenManager.getValidAccessToken();
      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }

      final chats = await ApiService.getChats(token: token);
      await ChatBadgeManager.markChatsSeen(ChatRole.pkl);
      if (!mounted) return;
      setState(() {
        _chats = chats;
      });
      await _refreshOpenedMap();
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat daftar chat.\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _filteredChats() {
    final base = _chats.whereType<Map<String, dynamic>>().toList();
    final q = _searchQuery.trim().toLowerCase();

    Iterable<Map<String, dynamic>> result = base;
    if (q.isNotEmpty) {
      result = result.where((chat) {
        final name = (chat['pembeli_username'] ?? '').toString().toLowerCase();
        return name.contains(q);
      });
    }

    if (_filterIndex == 1) {
      result = result.where((chat) {
        final id = (chat['id'] as num?)?.toInt();
        if (id == null) return false;
        return ChatReadTracker.isUnread(
          openedMap: _openedMap,
          chatId: id,
          updatedAt: chat['updated_at']?.toString(),
        );
      });
    }

    return result.toList();
  }

  int _unreadCount() {
    var count = 0;
    for (final chat in _chats.whereType<Map<String, dynamic>>()) {
      final id = (chat['id'] as num?)?.toInt();
      if (id == null) continue;
      if (ChatReadTracker.isUnread(
        openedMap: _openedMap,
        chatId: id,
        updatedAt: chat['updated_at']?.toString(),
      )) {
        count++;
      }
    }
    return count;
  }

  String _formatTimestamp(String? raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _themeManager.backgroundColor;
    final textColor = _themeManager.textColor;
    final borderColor = _themeManager.borderColor;
    final unreadCount = _unreadCount();
    final chats = _filteredChats();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: textColor,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadChats,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  children: [
                    _buildHeader(unreadCount: unreadCount),
                    const SizedBox(height: 14),
                    if (_showSearch) _buildSearchField(),
                    if (_showSearch) const SizedBox(height: 12),
                    _buildFilters(),
                    const SizedBox(height: 14),
                    if (chats.isNotEmpty) _buildQuickAvatars(chats),
                    if (chats.isNotEmpty) const SizedBox(height: 14),
                    if (_error != null) _buildErrorBanner(_error!),
                    if (chats.isEmpty)
                      _buildEmptyState()
                    else
                      ...chats.map<Widget>((chat) {
                        final id = (chat['id'] as num?)?.toInt() ?? 0;
                        final unread = id == 0
                            ? false
                            : ChatReadTracker.isUnread(
                                openedMap: _openedMap,
                                chatId: id,
                                updatedAt: chat['updated_at']?.toString(),
                              );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildChatTile(chat, isUnread: unread),
                        );
                      }),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const PklBottomNavBar(current: PklNavItem.chat),
    );
  }

  Widget _buildHeader({required int unreadCount}) {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final badgeBg = _themeManager.accentGold.withValues(alpha: 0.14);
    final badgeBorder = _themeManager.accentGold.withValues(alpha: 0.3);
    final badgeText = _themeManager.accentGold;

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                'Pesan',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: -0.6,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    '$unreadCount Baru',
                    style: TextStyle(
                      color: badgeText,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (unreadCount == 0) ...[
                const SizedBox(width: 10),
                Text(
                  'Tidak ada pesan baru',
                  style: TextStyle(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cari',
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _searchQuery = '';
            });
          },
          icon: Icon(
            _showSearch ? Icons.close_rounded : Icons.search_rounded,
          ),
        ),
        const SizedBox(width: 4),
        CircleAvatar(
          radius: 18,
          backgroundColor: _themeManager.accentSurfaceColor,
          foregroundColor: _themeManager.primaryGreen,
          child: Text(
            _myInitial,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final borderColor = _themeManager.borderColor;
    final fill = _themeManager.cardColor;
    final muted = _themeManager.mutedTextColor;
    final text = _themeManager.textColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: text),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Cari nama pembeli…',
          hintStyle: TextStyle(color: muted),
          icon: Icon(Icons.search_rounded, color: muted),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final border = _themeManager.borderColor;
    final card = _themeManager.cardColor;
    final muted = _themeManager.mutedTextColor;
    final active = _themeManager.textColor;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FilterPill(
              label: 'Semua',
              selected: _filterIndex == 0,
              onTap: () => setState(() => _filterIndex = 0),
              themeManager: _themeManager,
              activeText: active,
              inactiveText: muted,
            ),
          ),
          Expanded(
            child: _FilterPill(
              label: 'Belum Dibaca',
              selected: _filterIndex == 1,
              onTap: () => setState(() => _filterIndex = 1),
              themeManager: _themeManager,
              activeText: active,
              inactiveText: muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAvatars(List<Map<String, dynamic>> chats) {
    final border = _themeManager.borderColor;
    final text = _themeManager.textColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEDANG BERLANGSUNG',
          style: TextStyle(
            color: _themeManager.mutedTextColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chats.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final chat = chats[i];
              final id = (chat['id'] as num?)?.toInt();
              final name = (chat['pembeli_username'] ?? 'Pembeli') as String;
              final unread = id == null
                  ? false
                  : ChatReadTracker.isUnread(
                      openedMap: _openedMap,
                      chatId: id,
                      updatedAt: chat['updated_at']?.toString(),
                    );

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: id == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PklChatRoomPage(
                              chatId: id,
                              pembeliName: name,
                            ),
                          ),
                        ).then((_) => _loadChats());
                      },
                child: Container(
                  width: 72,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _themeManager.cardColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: unread
                          ? _themeManager.accentGold.withValues(alpha: 0.55)
                          : border,
                      width: unread ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: _themeManager.accentSurfaceColor,
                            foregroundColor: _themeManager.primaryGreen,
                            child: Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (unread)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _themeManager.accentGold,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _themeManager.cardColor,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: text,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade200),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _themeManager.cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 44,
            color: _themeManager.primaryGreen,
          ),
          const SizedBox(height: 10),
          Text(
            'Belum ada chat dari pembeli.',
            style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Saat pembeli menghubungi kamu, daftar ini akan terisi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat, {bool? isUnread}) {
    final border = _themeManager.borderColor;
    final textColor = _themeManager.textColor;
    final mutedText = _themeManager.mutedTextColor;
    final pembeli = (chat['pembeli_username'] ?? 'Pembeli') as String;
    final updatedAt = _formatTimestamp(chat['updated_at'] as String?);
    final chatId = (chat['id'] as num?)?.toInt();
    final unread = isUnread ??
        (chatId == null
            ? false
            : ChatReadTracker.isUnread(
                openedMap: _openedMap,
                chatId: chatId,
                updatedAt: chat['updated_at']?.toString(),
              ));

    final stripeColor = unread
        ? _themeManager.accentGold
        : _themeManager.hintTextColor.withValues(alpha: 0.45);
    final tileBg =
        unread ? _themeManager.cardColor : _themeManager.surfaceColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: chatId == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PklChatRoomPage(
                      chatId: chatId,
                      pembeliName: pembeli,
                    ),
                  ),
                ).then((_) => _loadChats());
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: unread
                  ? _themeManager.accentGold.withValues(alpha: 0.35)
                  : border,
              width: unread ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 52,
                decoration: BoxDecoration(
                  color: stripeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                backgroundColor: _themeManager.accentSurfaceColor,
                foregroundColor: _themeManager.primaryGreen,
                child:
                    Text(pembeli.isEmpty ? '?' : pembeli[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pembeli,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: textColor,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _themeManager.accentGold,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Baru',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Update terakhir: $updatedAt',
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.themeManager,
    required this.activeText,
    required this.inactiveText,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeManager themeManager;
  final Color activeText;
  final Color inactiveText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? themeManager.surfaceColor : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? activeText : inactiveText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
