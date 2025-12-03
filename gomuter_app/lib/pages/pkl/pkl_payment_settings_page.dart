import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';

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
    return TokenManager.getValidAccessToken();
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

  Widget _buildHeroBanner() {
    final subtitle = _isNewProfile
        ? 'Ajukan profil usaha agar pembayaran bisa digunakan.'
        : 'Simpan link dan QRIS untuk mempermudah transaksi.';
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B7332), Color(0xFF10A14D), Color(0xFF25D366)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D8A3A).withValues(alpha: 0.3),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF0D8A3A).withValues(alpha: 0.1),
            blurRadius: 48,
            offset: const Offset(0, 24),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Pembayaran PKL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pastikan QRIS terbaru agar pembeli bisa langsung bayar.',
                    style: TextStyle(
                      color: Colors.white,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCDD2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFD32F2F),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Terjadi Kesalahan',
                  style: TextStyle(
                    color: Color(0xFFD32F2F),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _error ?? 'Terjadi kesalahan.',
                  style: TextStyle(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 48,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            title.contains('Link') ? Icons.link_rounded : Icons.image_rounded,
            color: const Color(0xFF0D8A3A),
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkCard() {
    return _buildCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            'Link Pembayaran',
            'Simpan tautan pembayaran QRIS atau dompet digital kamu.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _qrisLinkController,
            decoration: InputDecoration(
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: Color(0xFF0D8A3A),
                  size: 20,
                ),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Colors.black.withValues(alpha: 0.08),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Colors.black.withValues(alpha: 0.08),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Color(0xFF0D8A3A),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              hintText: 'https://contoh.qris.id/pay',
              hintStyle: TextStyle(
                color: Colors.black.withValues(alpha: 0.4),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingLink ? null : _saveQrisLink,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D8A3A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              icon: _isSavingLink
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(
                _isSavingLink ? 'Menyimpan...' : 'Simpan Link',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrisCard() {
    return _buildCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            'Gambar QRIS',
            'Unggah atau tempel URL QRIS terbaru untuk pembeli.',
          ),
          const SizedBox(height: 16),
          _buildDropArea(),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
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
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus gambar'),
                ),
            ],
          ),
          if (_previewBytes != null)
            _buildPreview(Image.memory(_previewBytes!, fit: BoxFit.cover))
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
            Text(
              _qrisImageController.text,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
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
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadProfile,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 72),
                  children: [
                    const SizedBox(height: 12),
                    _buildHeroBanner(),
                    const SizedBox(height: 18),
                    if (_error != null) _buildErrorBanner(),
                    _buildLinkCard(),
                    const SizedBox(height: 18),
                    _buildQrisCard(),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const PklBottomNavBar(current: PklNavItem.payment),
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

    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: content,
      ),
    );
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
