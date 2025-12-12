import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pkl/pkl_chat_room_page.dart';
import 'package:gomuter_app/utils/chat_badge_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';

class PklChatListPage extends StatefulWidget {
  const PklChatListPage({super.key});

  @override
  State<PklChatListPage> createState() => _PklChatListPageState();
}

class _PklChatListPageState extends State<PklChatListPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _chats = [];

  @override
  void initState() {
    super.initState();
    _loadChats();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: const Text('Pesan dari Pembeli'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadChats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadChats,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  children: [
                    const SizedBox(height: 12),
                    _buildHeroBanner(),
                    const SizedBox(height: 18),
                    if (_error != null) _buildErrorBanner(_error!),
                    if (_chats.isEmpty)
                      _buildEmptyState()
                    else
                      ..._chats.map<Widget>(
                        (chat) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildChatTile(chat as Map<String, dynamic>),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const PklBottomNavBar(current: PklNavItem.chat),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D8A3A), Color(0xFF35C481)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D8A3A).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Chat Pembeli',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Balas pesan mereka agar orderan terus masuk.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5E7),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD32F2F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFD32F2F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
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
        children: const [
          Icon(Icons.chat_bubble_outline, size: 44, color: Color(0xFF0D8A3A)),
          SizedBox(height: 10),
          Text(
            'Belum ada chat dari pembeli.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Saat pembeli menghubungi kamu, daftar ini akan terisi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat) {
    final pembeli = (chat['pembeli_username'] ?? 'Pembeli') as String;
    final updatedAt = _formatTimestamp(chat['updated_at'] as String?);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PklChatRoomPage(
                chatId: (chat['id'] as num).toInt(),
                pembeliName: pembeli,
              ),
            ),
          ).then((_) => _loadChats());
        },
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE8F9EF),
              foregroundColor: const Color(0xFF0D8A3A),
              child: Text(pembeli.isEmpty ? '?' : pembeli[0].toUpperCase()),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pembeli,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Update terakhir: $updatedAt',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
