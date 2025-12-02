import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PklPaymentSettingsPage extends StatefulWidget {
  const PklPaymentSettingsPage({super.key});

  @override
  State<PklPaymentSettingsPage> createState() => _PklPaymentSettingsPageState();
}

class _PklPaymentSettingsPageState extends State<PklPaymentSettingsPage> {
  static const List<String> _allowedExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  ];

  final _qrisLinkController = TextEditingController();
  final _qrisImageController = TextEditingController();

  bool _isLoading = true;
  bool _isSavingLink = false;
  bool _isUploading = false;
  bool _isHoveringDrop = false;
  bool _isNewProfile = false;
  Uint8List? _previewBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _qrisLinkController.dispose();
    _qrisImageController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
        });
        return;
      }

      final profile = await ApiService.getPKLProfile(token);
      if (profile == null) {
        setState(() {
          _isNewProfile = true;
        });
      } else {
        _qrisLinkController.text = profile['qris_link'] ?? '';
        _qrisImageController.text = profile['qris_image_url'] ?? '';
        setState(() {
          _isNewProfile = false;
          _previewBytes = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat informasi pembayaran. $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveQrisLink() async {
    if (_isNewProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ajukan profil usaha terlebih dahulu sebelum menyimpan QRIS.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSavingLink = true;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan.');
      }

      await ApiService.savePKLProfile(
        token: token,
        data: {'qris_link': _qrisLinkController.text.trim()},
        isNew: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link QRIS berhasil disimpan.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menyimpan link QRIS: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLink = false;
        });
      }
    }
  }

  bool get _supportsDesktopDrop {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  Future<void> _pickImage() async {
    if (_isUploading) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('File tidak dapat dibaca.');
      }

      if (!_isSupportedFile(file.name)) {
        _showSnack('Gunakan gambar PNG/JPG/WEBP.');
        return;
      }

      await _uploadBytes(bytes, _safeFileName(file.name));
    } catch (e) {
      _showSnack('Gagal memilih gambar QRIS: $e');
    }
  }

  Future<void> _handleDrop(List<XFile> files) async {
    if (files.isEmpty || _isUploading) return;

    final file = files.first;
    if (!_isSupportedFile(file.name)) {
      _showSnack('Format tidak didukung. Gunakan PNG/JPG/WEBP.');
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      await _uploadBytes(bytes, _safeFileName(file.name));
    } catch (e) {
      _showSnack('Gagal membaca file QRIS: $e');
    }
  }

  Future<void> _uploadBytes(List<int> bytes, String fileName) async {
    if (_isNewProfile) {
      _showSnack(
        'Ajukan profil usaha terlebih dahulu sebelum mengunggah QRIS.',
      );
      return;
    }

    final token = await _getToken();
    if (token == null) {
      _showSnack('Token tidak ditemukan. Silakan login ulang.');
      return;
    }

    setState(() {
      _isUploading = true;
      _previewBytes = _ensureUint8(bytes);
    });

    try {
      final uploadedUrl = await ApiService.uploadDPFile(
        token: token,
        fileName: fileName,
        fileBytes: bytes,
      );

      if (!mounted) return;
      setState(() {
        _qrisImageController.text = uploadedUrl;
      });
      await _persistImageUrl(showSuccess: false);
      _showSnack('Gambar QRIS berhasil diunggah.');
    } catch (e) {
      _showSnack('Gagal mengunggah QRIS: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _persistImageUrl({bool showSuccess = true}) async {
    if (_isNewProfile) {
      if (showSuccess) {
        _showSnack(
          'Gambar QRIS siap. Simpan profil Anda untuk menutup proses.',
        );
      }
      return;
    }

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan.');
      }

      await ApiService.savePKLProfile(
        token: token,
        data: {'qris_image_url': _qrisImageController.text.trim()},
        isNew: false,
      );

      if (showSuccess) {
        _showSnack('Gambar QRIS tersimpan.');
      }
    } catch (e) {
      _showSnack('Gagal menyimpan URL QRIS: $e');
    }
  }

  void _clearImage() {
    setState(() {
      _qrisImageController.clear();
      _previewBytes = null;
    });
    _persistImageUrl(showSuccess: false);
  }

  Future<void> _promptManualUrl() async {
    final controller = TextEditingController(text: _qrisImageController.text);
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Masukkan URL gambar QRIS'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'URL gambar',
            hintText: 'https://contoh.com/qris.png',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Gunakan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.isEmpty) return;
    setState(() {
      _qrisImageController.text = result;
      _previewBytes = null;
    });
    await _persistImageUrl(showSuccess: false);
    _showSnack('URL QRIS diperbarui.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isSupportedFile(String? fileName) {
    if (fileName == null || fileName.isEmpty) return false;
    final lower = fileName.toLowerCase();
    return _allowedExtensions.any(lower.endsWith);
  }

  Uint8List _ensureUint8(List<int> bytes) {
    if (bytes is Uint8List) return bytes;
    return Uint8List.fromList(bytes);
  }

  String _safeFileName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'qris_${DateTime.now().millisecondsSinceEpoch}.png';
    }
    final cleaned = name
        .split('/')
        .last
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (_isSupportedFile(cleaned)) return cleaned;
    return '$cleaned${_allowedExtensions.first}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran & QRIS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const Text(
                    'Link Pembayaran',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _qrisLinkController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF5F7FB),
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSavingLink ? null : _saveQrisLink,
                      icon: _isSavingLink
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSavingLink ? 'Menyimpan...' : 'Simpan Link',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Gambar QRIS',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  _buildDropArea(),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _isUploading ? null : _promptManualUrl,
                        icon: const Icon(Icons.link),
                        label: const Text('Masukkan URL manual'),
                      ),
                      if (_qrisImageController.text.isNotEmpty)
                        TextButton.icon(
                          onPressed: _isUploading ? null : _clearImage,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Hapus gambar'),
                        ),
                    ],
                  ),
                  if (_previewBytes != null)
                    _buildPreview(
                      Image.memory(_previewBytes!, fit: BoxFit.cover),
                    )
                  else if (_qrisImageController.text.isNotEmpty)
                    _buildPreview(
                      Image.network(
                        _qrisImageController.text,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFF5F7FB),
                          alignment: Alignment.center,
                          child: const Text('QRIS tidak dapat dimuat'),
                        ),
                      ),
                    ),
                  if (_qrisImageController.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      _qrisImageController.text,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildDropArea() {
    Widget content = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _isUploading ? null : _pickImage,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 150,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: _isHoveringDrop
                ? const Color(0xFFE8F9EF)
                : const Color(0xFFF5F7FB),
            border: Border.all(
              color: _isHoveringDrop ? const Color(0xFF1ABC9C) : Colors.black12,
              width: 1.4,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isUploading)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                const Icon(
                  Icons.cloud_upload_outlined,
                  size: 38,
                  color: Color(0xFF1ABC9C),
                ),
              const SizedBox(height: 12),
              const Text(
                'Tarik & jatuhkan gambar QRIS',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Atau klik untuk pilih file (PNG/JPG/WEBP)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );

    if (_supportsDesktopDrop) {
      content = DropTarget(
        onDragEntered: (_) => setState(() => _isHoveringDrop = true),
        onDragExited: (_) => setState(() => _isHoveringDrop = false),
        onDragDone: (details) {
          setState(() => _isHoveringDrop = false);
          _handleDrop(details.files);
        },
        child: content,
      );
    }

    return content;
  }

  Widget _buildPreview(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(aspectRatio: 1, child: child),
      ),
    );
  }
}
