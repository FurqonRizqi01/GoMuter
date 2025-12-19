import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/navigation/pkl_routes.dart';
import 'package:gomuter_app/utils/theme_manager.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:gomuter_app/widgets/pkl_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PklProfilePage extends StatefulWidget {
  const PklProfilePage({super.key});

  @override
  State<PklProfilePage> createState() => _PklProfilePageState();
}

class _PklProfilePageState extends State<PklProfilePage> {
  final ThemeManager _themeManager = ThemeManager();
  final TextEditingController _usernameController = TextEditingController();

  bool _isLoading = true;
  bool _isSavingUsername = false;
  String? _error;

  String _displayName = 'PKL';
  String _subtitle = '';
  String _statusVerifikasi = 'PENDING';
  String? _profileImageUrl;
  Uint8List? _localProfileBytes;
  bool _isUploadingPhoto = false;

  double? _ratingAvg;
  int? _ratingCount;

  int _totalOrders = 0;
  int? _joinYear;

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    _usernameController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await TokenManager.getValidAccessToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan. Silakan login ulang.');
      }

      final me = await ApiService.getCurrentUser(token);
      final username = (me['username'] as String?)?.trim();

      _usernameController.text = username ?? '';

      final profile = await ApiService.getPKLProfile(token);

      final prefs = await SharedPreferences.getInstance();
      final cached = (prefs.getString('username') ?? '').trim();

      final ownerName = (username != null && username.isNotEmpty)
          ? username
          : (cached.isNotEmpty ? cached : 'PKL');

      if (profile != null) {
        final usaha = (profile['nama_usaha'] as String?)?.trim() ?? '';
        _profileImageUrl = (profile['profile_image_url'] as String?)?.trim();
        _displayName = ownerName;
        _subtitle = usaha.isEmpty ? '' : 'Pemilik $usaha';
        _statusVerifikasi = (profile['status_verifikasi'] ?? 'PENDING')
            .toString()
            .toUpperCase();

        final pklId = (profile['id'] as num?)?.toInt();
        if (pklId != null) {
          try {
            final rating = await ApiService.getPKLRatingSummary(pklId: pklId);
            _ratingAvg = (rating['average_rating'] as num?)?.toDouble();
            _ratingCount = (rating['rating_count'] as num?)?.toInt();
          } catch (_) {
            // Optional.
          }
        }

        try {
          final stats = await ApiService.getPKLDailyStats(token: token);
          _totalOrders = (stats['total_orders'] as num?)?.toInt() ?? 0;
        } catch (_) {
          // Optional.
        }

        final createdAt = profile['created_at'] as String?;
        final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;
        _joinYear = dt?.toLocal().year;
      } else {
        _displayName = ownerName;
        _subtitle = '';
        _statusVerifikasi = 'PENDING';
        _profileImageUrl = null;
      }
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat profil: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    if (_isUploadingPhoto) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membaca file gambar.')),
        );
        return;
      }

      setState(() {
        _localProfileBytes = bytes;
        _isUploadingPhoto = true;
      });

      final token = await TokenManager.getValidAccessToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan. Silakan login ulang.');
      }

      final data = await ApiService.uploadPKLProfilePhoto(
        token: token,
        bytes: bytes,
        filename: file.name,
      );

      final url = (data['profile_image_url'] as String?)?.trim();
      if (mounted) {
        setState(() {
          _profileImageUrl = url;
          _localProfileBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profil berhasil diperbarui.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal upload foto profil: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _openUsernameDialog() async {
    final border = _themeManager.borderColor;
    final text = _themeManager.textColor;
    final muted = _themeManager.mutedTextColor;
    final fieldFill = _themeManager.surfaceColor;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah Username'),
        content: TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: 'Masukkan username',
            hintStyle: TextStyle(color: muted),
            filled: true,
            fillColor: fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border),
            ),
          ),
          style: TextStyle(color: text),
        ),
        actions: [
          TextButton(
            onPressed: _isSavingUsername ? null : () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: _isSavingUsername ? null : _saveUsername,
            child: Text(_isSavingUsername ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUsername() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username tidak boleh kosong.')),
      );
      return;
    }

    setState(() {
      _isSavingUsername = true;
    });

    try {
      final token = await TokenManager.getValidAccessToken();
      if (token == null) {
        throw Exception('Token tidak ditemukan. Silakan login ulang.');
      }

      final updated = await ApiService.updateCurrentUsername(
        accessToken: token,
        username: newUsername,
      );

      final savedUsername = (updated['username'] as String?)?.trim();
      if (savedUsername != null && savedUsername.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', savedUsername);
        if (mounted) {
          setState(() {
            _displayName = savedUsername;
          });
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username berhasil diperbarui.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui username: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingUsername = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Anda akan kembali ke halaman login.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TokenManager.clearTokens();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

 
  @override
  Widget build(BuildContext context) {
    final bg = _themeManager.backgroundColor;
    final surface = _themeManager.surfaceColor;
    final text = _themeManager.textColor;
    final muted = _themeManager.mutedTextColor;
    final border = _themeManager.borderColor;

    final statusNormalized = _statusVerifikasi.toUpperCase();
    final verified = statusNormalized == 'DITERIMA' || statusNormalized == 'VERIFIED';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profil Saya'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: border),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: _themeManager.primaryGreen,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(_error!, style: TextStyle(color: text)),
                    ),

                  const SizedBox(height: 14),

                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _pickAndUploadProfilePhoto,
                          child: Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: surface,
                              border: Border.all(color: border, width: 2),
                              image: _localProfileBytes != null
                                  ? DecorationImage(
                                      image: MemoryImage(_localProfileBytes!),
                                      fit: BoxFit.cover,
                                    )
                                  : (_profileImageUrl != null &&
                                          _profileImageUrl!.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage(_profileImageUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                            ),
                            child: (_localProfileBytes == null &&
                                    (_profileImageUrl == null ||
                                        _profileImageUrl!.isEmpty))
                                ? Icon(
                                    Icons.person_rounded,
                                    size: 56,
                                    color: _themeManager.hintTextColor,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _pickAndUploadProfilePhoto,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _themeManager.accentGold,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _isUploadingPhoto
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  Center(
                    child: Text(
                      _displayName,
                      style: TextStyle(
                        color: text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _subtitle,
                        style: TextStyle(color: muted, fontSize: 14),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: verified
                            ? _themeManager.primaryGreen.withValues(alpha: 0.12)
                            : _themeManager.accentGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: verified
                              ? _themeManager.primaryGreen.withValues(
                                  alpha: 0.25,
                                )
                              : _themeManager.accentGold.withValues(
                                  alpha: 0.25,
                                ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            verified
                                ? Icons.verified_rounded
                                : Icons.hourglass_bottom_rounded,
                            size: 16,
                            color: verified
                                ? _themeManager.primaryGreen
                                : _themeManager.accentGold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            verified ? 'Terverifikasi' : 'Menunggu verifikasi',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: verified
                                  ? _themeManager.primaryGreen
                                  : _themeManager.accentGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: _StatChip(
                          icon: Icons.star_rounded,
                          label: 'Rating',
                          value: _ratingAvg == null
                              ? '-'
                              : _ratingAvg!.toStringAsFixed(1),
                          subValue: _ratingCount == null
                              ? null
                              : '${_ratingCount!} ulasan',
                          themeManager: _themeManager,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatChip(
                          icon: Icons.shopping_bag_rounded,
                          label: 'Total Order',
                          value: _totalOrders == 0
                              ? '-'
                              : _totalOrders.toString(),
                          themeManager: _themeManager,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatChip(
                          icon: Icons.calendar_month_rounded,
                          label: 'Gabung',
                          value: _joinYear?.toString() ?? '-',
                          themeManager: _themeManager,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'KELOLA WARUNG',
                    style: TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _GroupCard(
                    themeManager: _themeManager,
                    children: [
                      _MenuRow(
                        icon: Icons.qr_code_2_rounded,
                        iconBg: _themeManager.accentGold.withValues(
                          alpha: 0.12,
                        ),
                        title: 'Pembayaran',
                        subtitle: 'Atur QRIS & metode pembayaran',
                        onTap: () =>
                            Navigator.pushNamed(context, PklRoutes.payment),
                        themeManager: _themeManager,
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Text(
                    'AKUN & KEAMANAN',
                    style: TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _GroupCard(
                    themeManager: _themeManager,
                    children: [
                      _MenuRow(
                        icon: Icons.lock_outline_rounded,
                        iconBg: _themeManager.hintTextColor.withValues(
                          alpha: 0.12,
                        ),
                        title: 'Ubah Username',
                        subtitle: 'Perbarui username akun',
                        onTap: _openUsernameDialog,
                        themeManager: _themeManager,
                      ),
                      SwitchListTile(
                        value: _themeManager.isDarkMode,
                        onChanged: (_) {
                          _themeManager.toggleTheme();
                        },
                        activeThumbColor: _themeManager.accentGold,
                        title: Text(
                          'Mode Gelap',
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        secondary: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _themeManager.hintTextColor.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _themeManager.isDarkMode
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            color: _themeManager.hintTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  OutlinedButton.icon(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      backgroundColor: Colors.red.withValues(alpha: 0.06),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      'Keluar Akun',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Center(
                    child: Text(
                      'Versi aplikasi',
                      style: TextStyle(color: muted),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: const PklBottomNavBar(current: PklNavItem.profile),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children, required this.themeManager});

  final List<Widget> children;
  final ThemeManager themeManager;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: themeManager.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: themeManager.borderColor),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.themeManager,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final ThemeManager themeManager;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: themeManager.accentGold),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: themeManager.textColor,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: themeManager.mutedTextColor),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: themeManager.hintTextColor,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.themeManager,
    this.subValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final ThemeManager themeManager;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: themeManager.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeManager.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: themeManager.accentGold),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: themeManager.mutedTextColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: themeManager.textColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 4),
            Text(
              subValue!,
              style: TextStyle(color: themeManager.hintTextColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
