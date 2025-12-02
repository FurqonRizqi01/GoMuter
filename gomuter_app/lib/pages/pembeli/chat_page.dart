import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatPage extends StatefulWidget {
  final int pklId;
  final String pklNama;

  const ChatPage({super.key, required this.pklId, required this.pklNama});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  int? _chatId;
  String? _token;
  String? _currentUsername;
  List<dynamic> _messages = [];
  final TextEditingController _msgController = TextEditingController();
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final username = prefs.getString('username');

      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _token = token;
        _currentUsername = username;
      });

      final chat = await ApiService.startChat(
        token: token,
        pklId: widget.pklId,
      );
      final chatId = chat['id'] as int;

      setState(() {
        _chatId = chatId;
      });

      await _loadMessages();

      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _loadMessages(silent: true);
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memulai chat.\n$e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_chatId == null || _token == null) return;

    try {
      final msgs = await ApiService.getChatMessages(
        token: _token!,
        chatId: _chatId!,
      );
      if (mounted) {
        setState(() {
          _messages = msgs;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = 'Gagal memuat pesan.\n$e';
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_chatId == null || _token == null) return;
    final content = _msgController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      await ApiService.sendChatMessage(
        token: _token!,
        chatId: _chatId!,
        content: content,
      );
      _msgController.clear();
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengirim pesan: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat dengan ${widget.pklNama}')),
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
          : Column(
              children: [
                Expanded(child: _buildMessages()),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          decoration: const InputDecoration(
                            hintText: 'Tulis pesan...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        onPressed: _isSending ? null : _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text('Belum ada percakapan. Mulai sapa PKL sekarang!'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index] as Map<String, dynamic>;
        final content = (msg['content'] ?? '') as String;
        final senderName = (msg['sender_username'] ?? '-') as String;
        final isMe = senderName == _currentUsername;

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: isMe ? Colors.teal[300] : Colors.grey[200],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 12),
              ),
            ),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isMe ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
