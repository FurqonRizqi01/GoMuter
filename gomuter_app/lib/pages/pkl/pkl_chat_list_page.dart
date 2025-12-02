import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/pages/pkl/pkl_chat_room_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }

      final chats = await ApiService.getChats(token: token);
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
      appBar: AppBar(
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
          : _error != null
          ? Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            )
          : _chats.isEmpty
          ? const Center(child: Text('Belum ada chat dari pembeli.'))
          : ListView.separated(
              itemCount: _chats.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final chat = _chats[index] as Map<String, dynamic>;
                final pembeli =
                    (chat['pembeli_username'] ?? 'Pembeli') as String;
                final updatedAt = _formatTimestamp(
                  chat['updated_at'] as String?,
                );
                return ListTile(
                  title: Text(pembeli),
                  subtitle: Text('Update terakhir: $updatedAt'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PklChatRoomPage(
                          chatId: (chat['id'] as num).toInt(),
                          pembeliName: pembeli,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
