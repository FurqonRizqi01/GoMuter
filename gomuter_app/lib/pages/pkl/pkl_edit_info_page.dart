import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';

class PklEditInfoPage extends StatefulWidget {
  const PklEditInfoPage({super.key});

  @override
  State<PklEditInfoPage> createState() => _PklEditInfoPageState();
}

class _PklEditInfoPageState extends State<PklEditInfoPage> {
  final _namaUsahaController = TextEditingController();
  final _jenisDaganganController = TextEditingController();
  final _jamOperasionalController = TextEditingController();
  final _alamatController = TextEditingController();
  final _namaRekeningController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isNewProfile = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _namaUsahaController.dispose();
    _jenisDaganganController.dispose();
    _jamOperasionalController.dispose();
    _alamatController.dispose();
    _namaRekeningController.dispose();
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
        _namaUsahaController.text = profile['nama_usaha'] ?? '';
        _jenisDaganganController.text = profile['jenis_dagangan'] ?? '';
        _jamOperasionalController.text = profile['jam_operasional'] ?? '';
        _alamatController.text = profile['alamat_domisili'] ?? '';
        _namaRekeningController.text = profile['nama_rekening'] ?? '';
        setState(() {
          _isNewProfile = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat profil PKL. $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        setState(() {
          _error = 'Token tidak ditemukan. Silakan login ulang.';
          _isSaving = false;
        });
        return;
      }

      final data = {
        'nama_usaha': _namaUsahaController.text.trim(),
        'jenis_dagangan': _jenisDaganganController.text.trim(),
        'jam_operasional': _jamOperasionalController.text.trim(),
        'alamat_domisili': _alamatController.text.trim(),
        'nama_rekening': _namaRekeningController.text.trim(),
      };

      await ApiService.savePKLProfile(
        token: token,
        data: data,
        isNew: _isNewProfile,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isNewProfile
                ? 'Profil berhasil diajukan. Menunggu verifikasi admin.'
                : 'Profil berhasil diperbarui.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Gagal menyimpan profil. $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: const Text(
          'Edit Informasi Dagangan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFFFFCDD2),
                          width: 1,
                        ),
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
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: const Color(
                                  0xFFD32F2F,
                                ).withValues(alpha: 0.9),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildRoundedField(
                    label: 'Nama Usaha',
                    controller: _namaUsahaController,
                    icon: Icons.storefront_rounded,
                  ),
                  const SizedBox(height: 18),
                  _buildRoundedField(
                    label: 'Kategori / Jenis Dagangan',
                    controller: _jenisDaganganController,
                    icon: Icons.category_rounded,
                  ),
                  const SizedBox(height: 18),
                  _buildRoundedField(
                    label: 'Jam Operasional',
                    controller: _jamOperasionalController,
                    icon: Icons.access_time_rounded,
                  ),
                  const SizedBox(height: 18),
                  _buildRoundedField(
                    label: 'Alamat Domisili',
                    controller: _alamatController,
                    icon: Icons.location_city_rounded,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 18),
                  _buildRoundedField(
                    label: 'Nama Rekening (opsional)',
                    controller: _namaRekeningController,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D8A3A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.save_rounded, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  _isNewProfile
                                      ? 'Ajukan Profil Usaha'
                                      : 'Simpan Perubahan',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRoundedField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF0D8A3A), size: 22),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFF0D8A3A), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
          ),
        ),
      ],
    );
  }
}
