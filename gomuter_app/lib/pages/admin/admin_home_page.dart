import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';

class AdminHomePage extends StatefulWidget {
  final String accessToken;
  const AdminHomePage({super.key, required this.accessToken});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _pending = [];
  int? _processingId;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getPendingPKL(token: widget.accessToken);
      setState(() {
        _pending = data;
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat PKL pending: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _promptNote({required bool approve}) async {
    final controller = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(approve ? 'Terima PKL' : 'Tolak PKL'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    approve
                        ? 'Tambahkan catatan (opsional) untuk PKL.'
                        : 'Masukkan alasan penolakan agar PKL mendapat feedback.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Catatan',
                    ),
                  ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final note = controller.text.trim();
                    if (!approve && note.isEmpty) {
                      setModalState(() {
                        errorText = 'Alasan penolakan wajib diisi.';
                      });
                      return;
                    }
                    Navigator.pop(context, note);
                  },
                  child: Text(approve ? 'Terima' : 'Tolak'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _verifyPKL(Map<String, dynamic> pkl, bool approve) async {
    final note = await _promptNote(approve: approve);
    if (note == null) return;

    final id = pkl['id'] as int;
    setState(() {
      _processingId = id;
    });

    try {
      await ApiService.verifyPKL(
        token: widget.accessToken,
        id: id,
        data: {
          'status_verifikasi': approve ? 'DITERIMA' : 'DITOLAK',
          'status_aktif': approve,
          'catatan_verifikasi': note.isEmpty ? null : note,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'PKL diterima dan aktif.' : 'PKL ditolak.'),
          ),
        );
      }

      await _loadPending();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses verifikasi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GoMuter - Admin')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadPending,
                child: _pending.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(
                            child: Text('Tidak ada PKL menunggu verifikasi.'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _pending.length,
                        itemBuilder: (context, index) {
                          final pkl = _pending[index] as Map<String, dynamic>;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pkl['nama_usaha'] ?? '-',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(pkl['jenis_dagangan'] ?? '-'),
                                  const SizedBox(height: 4),
                                  Text('Status: ${pkl['status_verifikasi']}'),
                                  if ((pkl['catatan_verifikasi'] as String?)
                                          ?.isNotEmpty ??
                                      false)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Catatan: ${pkl['catatan_verifikasi']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _processingId == pkl['id']
                                              ? null
                                              : () => _verifyPKL(pkl, true),
                                          icon: const Icon(Icons.check),
                                          label: const Text('Terima'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _processingId == pkl['id']
                                              ? null
                                              : () => _verifyPKL(pkl, false),
                                          icon: const Icon(Icons.close),
                                          label: const Text('Tolak'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_processingId == pkl['id'])
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: LinearProgressIndicator(),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
