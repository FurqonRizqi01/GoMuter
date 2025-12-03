import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:intl/intl.dart';

class _ProductFormResult {
  final int? id;
  final String name;
  final int price;
  final String? description;
  final bool isFeatured;
  final bool isAvailable;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final bool removeImage;

  const _ProductFormResult({
    this.id,
    required this.name,
    required this.price,
    this.description,
    required this.isFeatured,
    required this.isAvailable,
    this.imageBytes,
    this.imageFileName,
    this.removeImage = false,
  });
}

class PklEditInfoPage extends StatefulWidget {
  const PklEditInfoPage({super.key});

  @override
  State<PklEditInfoPage> createState() => _PklEditInfoPageState();
}

class _PklEditInfoPageState extends State<PklEditInfoPage> {
  static const List<String> _allowedImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  final _namaUsahaController = TextEditingController();
  final _jenisDaganganController = TextEditingController();
  final _jamOperasionalController = TextEditingController();
  final _alamatController = TextEditingController();
  final _namaRekeningController = TextEditingController();
  late final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isNewProfile = false;
  String? _error;
  bool _isProductLoading = true;
  bool _isProductMutating = false;
  String? _productError;
  List<Map<String, dynamic>> _products = [];

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

  Future<String> _requireToken() async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Token tidak ditemukan. Silakan login ulang.');
    }
    return token;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

      await _loadProducts(token: token);
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

  Future<void> _loadProducts({String? token}) async {
    final resolvedToken = token ?? await _getToken();
    if (resolvedToken == null) {
      setState(() {
        _productError = 'Token tidak ditemukan. Silakan login ulang.';
        _isProductLoading = false;
      });
      return;
    }

    setState(() {
      _isProductLoading = true;
      _productError = null;
    });

    try {
      final items = await ApiService.getPKLProducts(resolvedToken);
      if (!mounted) return;
      setState(() {
        _products = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _productError = 'Gagal memuat produk: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProductLoading = false;
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

  Future<void> _handleAddProduct() async {
    if (_isNewProfile) {
      _showSnack('Ajukan profil usaha terlebih dahulu sebelum menambah produk.');
      return;
    }

    final result = await _openProductForm();
    if (result == null) return;

    await _mutateProduct(
      (token) => ApiService.createPKLProduct(
        token: token,
        name: result.name,
        price: result.price,
        description: result.description,
        isFeatured: result.isFeatured,
        isAvailable: result.isAvailable,
        imageBytes: result.imageBytes,
        imageFileName: result.imageFileName,
      ),
      successMessage: 'Produk berhasil ditambahkan.',
    );
  }

  Future<void> _handleEditProduct(Map<String, dynamic> product) async {
    final result = await _openProductForm(product: product);
    if (result == null) return;

    await _mutateProduct(
      (token) => ApiService.updatePKLProduct(
        token: token,
        productId: product['id'] as int,
        name: result.name,
        price: result.price,
        description: result.description,
        isFeatured: result.isFeatured,
        isAvailable: result.isAvailable,
        imageBytes: result.imageBytes,
        imageFileName: result.imageFileName,
        removeImage: result.removeImage,
      ),
      successMessage: 'Produk berhasil diperbarui.',
    );
  }

  Future<void> _handleDeleteProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hapus Produk?'),
            content: Text(
              'Produk "${product['name'] ?? '-'}" akan dihapus permanen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                ),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _mutateProduct(
      (token) => ApiService.deletePKLProduct(
        token: token,
        productId: product['id'] as int,
      ),
      successMessage: 'Produk dihapus.',
    );
  }

  Future<void> _mutateProduct(
    Future<void> Function(String token) action, {
    required String successMessage,
  }) async {
    setState(() {
      _isProductMutating = true;
    });

    try {
      final token = await _requireToken();
      await action(token);
      await _loadProducts(token: token);
      if (!mounted) return;
      _showSnack(successMessage);
    } catch (e) {
      _showSnack('Gagal memproses produk: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProductMutating = false;
        });
      }
    }
  }

  Future<_ProductFormResult?> _openProductForm({Map<String, dynamic>? product}) async {
    final nameController = TextEditingController(text: product?['name'] ?? '');
    final priceController = TextEditingController(
      text: product?['price']?.toString() ?? '',
    );
    final descriptionController =
        TextEditingController(text: product?['description'] ?? '');

    bool isFeatured = product?['is_featured'] == true;
    bool isAvailable = product?['is_available'] != false;
    Uint8List? selectedBytes;
    String? selectedFileName;
    bool removeImage = false;
    final existingImageUrl = product?['image_url'] as String?;
    String? formError;

    final result = await showModalBottomSheet<_ProductFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            Future<void> pickImage() async {
              try {
                final picked = await FilePicker.platform.pickFiles(
                  allowMultiple: false,
                  withData: true,
                  type: FileType.custom,
                  allowedExtensions: _allowedImageExtensions,
                );

                if (picked == null || picked.files.isEmpty) return;
                final file = picked.files.first;
                final bytes = file.bytes;
                if (bytes == null) {
                  throw Exception('File tidak dapat dibaca.');
                }

                if (!_isSupportedImage(file.name)) {
                  modalSetState(() {
                    formError = 'Gunakan gambar JPG, JPEG, PNG, atau WEBP.';
                  });
                  return;
                }

                modalSetState(() {
                  selectedBytes = bytes;
                  selectedFileName = _sanitizeFileName(file.name);
                  removeImage = false;
                  formError = null;
                });
              } catch (e) {
                modalSetState(() {
                  formError = 'Gagal memilih gambar: $e';
                });
              }
            }

            void clearImage() {
              modalSetState(() {
                selectedBytes = null;
                selectedFileName = null;
                removeImage = existingImageUrl != null;
                formError = null;
              });
            }

            Widget buildPreview() {
              Widget child;
              if (selectedBytes != null) {
                child = Image.memory(
                  selectedBytes!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              } else if (existingImageUrl != null && !removeImage) {
                child = Image.network(
                  existingImageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              } else {
                child = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.image_outlined, size: 36, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Belum ada gambar', style: TextStyle(color: Colors.grey)),
                  ],
                );
              }

              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 160,
                  color: const Color(0xFFF3F4F6),
                  child: child,
                ),
              );
            }

            Future<void> submit() async {
              final name = nameController.text.trim();
              final priceText = priceController.text.trim();
              final description = descriptionController.text.trim();

              if (name.isEmpty) {
                modalSetState(() {
                  formError = 'Nama produk wajib diisi.';
                });
                return;
              }

              if (priceText.isEmpty) {
                modalSetState(() {
                  formError = 'Harga wajib diisi.';
                });
                return;
              }

              final price = int.tryParse(priceText);
              if (price == null || price <= 0) {
                modalSetState(() {
                  formError = 'Masukkan harga dalam angka positif.';
                });
                return;
              }

              Navigator.pop(
                context,
                _ProductFormResult(
                  id: product?['id'] as int?,
                  name: name,
                  price: price,
                  description: description.isEmpty ? null : description,
                  isFeatured: isFeatured,
                  isAvailable: isAvailable,
                  imageBytes: selectedBytes,
                  imageFileName: selectedFileName,
                  removeImage: removeImage,
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product == null ? 'Tambah Produk' : 'Ubah Produk',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    buildPreview(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: pickImage,
                          icon: const Icon(Icons.image_rounded),
                          label: Text(selectedBytes != null
                              ? 'Ganti Gambar'
                              : existingImageUrl != null && !removeImage
                                  ? 'Ubah Gambar'
                                  : 'Pilih Gambar'),
                        ),
                        const SizedBox(width: 12),
                        if (selectedBytes != null || (existingImageUrl != null && !removeImage))
                          TextButton.icon(
                            onPressed: clearImage,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Hapus Gambar'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Menu',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Harga (IDR)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Deskripsi (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            value: isFeatured,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Tandai unggulan'),
                            onChanged: (value) => modalSetState(() {
                              isFeatured = value;
                            }),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            value: isAvailable,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Tersedia'),
                            onChanged: (value) => modalSetState(() {
                              isAvailable = value;
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        formError!,
                        style: const TextStyle(color: Color(0xFFD32F2F)),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D8A3A),
                            ),
                            child: const Text('Simpan'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    priceController.dispose();
    descriptionController.dispose();

    return result;
  }

  bool _isSupportedImage(String? fileName) {
    if (fileName == null || fileName.isEmpty) return false;
    final lower = fileName.toLowerCase();
    return _allowedImageExtensions.any(lower.endsWith);
  }

  String _sanitizeFileName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'produk_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    final cleaned = name
        .split('/')
        .last
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (_isSupportedImage(cleaned)) return cleaned;
    return '$cleaned.jpg';
  }

  String _formatPrice(dynamic value) {
    if (value == null) return '-';
    if (value is num) {
      return _currencyFormatter.format(value);
    }
    final parsed = int.tryParse(value.toString());
    if (parsed != null) {
      return _currencyFormatter.format(parsed);
    }
    return value.toString();
  }

  Widget _buildProductSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Menu Unggulan',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isNewProfile
                          ? 'Lengkapi profil usahamu sebelum menambahkan menu.'
                          : 'Upload foto, harga, dan deskripsi agar pembeli tertarik.',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: (_isProductMutating || _isNewProfile)
                    ? null
                    : _handleAddProduct,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D8A3A),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah Menu'),
              ),
            ],
          ),
          if (_isProductMutating)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(
                color: Color(0xFF0D8A3A),
                backgroundColor: Color(0xFFE8F5E9),
              ),
            ),
          if (_productError != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFE0B2)),
                ),
                child: Text(
                  _productError!,
                  style: const TextStyle(color: Color(0xFFBF360C)),
                ),
              ),
            ),
          if (_isProductLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.coffee_maker_outlined,
                      color: Color(0xFF0D8A3A),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Belum ada menu terdaftar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tambahkan minimal 1 menu unggulan lengkap dengan foto dan harga.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: _products
                    .map((product) => _buildProductCard(product))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final imageUrl = product['image_url'] as String?;
    final description = product['description'] as String?;
    final isAvailable = product['is_available'] != false;
    final isFeatured = product['is_featured'] == true;
    final priceText = _formatPrice(product['price']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        color: const Color(0xFFFDFDFE),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductImage(imageUrl),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']?.toString() ?? '-',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  priceText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D8A3A),
                  ),
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (isFeatured)
                      _buildTag('Unggulan', const Color(0xFFFFC107)),
                    _buildTag(
                      isAvailable ? 'Tersedia' : 'Stok habis',
                      isAvailable ? const Color(0xFF0D8A3A) : const Color(0xFFD32F2F),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                tooltip: 'Ubah',
                icon: const Icon(Icons.edit_outlined),
                onPressed:
                    _isProductMutating ? null : () => _handleEditProduct(product),
              ),
              IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed:
                    _isProductMutating ? null : () => _handleDeleteProduct(product),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductImage(String? imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 88,
        height: 88,
        color: const Color(0xFFF0F2F5),
        child: imageUrl != null
            ? Image.network(imageUrl, fit: BoxFit.cover)
            : Icon(
                Icons.fastfood_rounded,
                color: Colors.black.withValues(alpha: 0.4),
                size: 30,
              ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
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
                  _buildProductSection(),
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
