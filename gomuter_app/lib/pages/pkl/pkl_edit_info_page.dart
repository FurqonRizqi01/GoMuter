import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      Navigator.pop(context, true);
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
      appBar: AppBar(
        title: const Text('Edit Informasi Dagangan'),
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
                      child:
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  _buildRoundedField(
                    label: 'Nama Usaha',
                    controller: _namaUsahaController,
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 14),
                  _buildRoundedField(
                    label: 'Kategori / Jenis Dagangan',
                    controller: _jenisDaganganController,
                    icon: Icons.category_outlined,
                  ),
                  const SizedBox(height: 14),
                  _buildRoundedField(
                    label: 'Jam Operasional',
                    controller: _jamOperasionalController,
                    icon: Icons.access_time,
                  ),
                  const SizedBox(height: 14),
                  _buildRoundedField(
                    label: 'Alamat Domisili',
                    controller: _alamatController,
                    icon: Icons.location_city,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  _buildRoundedField(
                    label: 'Nama Rekening (opsional)',
                    controller: _namaRekeningController,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isNewProfile
                                  ? 'Ajukan Profil Usaha'
                                  : 'Simpan Perubahan',
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
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF5F7FB),
            prefixIcon: Icon(icon),
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
      ],
    );
  }
}
