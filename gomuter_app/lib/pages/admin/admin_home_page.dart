import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:gomuter_app/utils/token_manager.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_theme.dart';
import 'tabs/admin_data_pkl_tab.dart';
import 'tabs/admin_reports_tab.dart';
import 'tabs/admin_summary_tab.dart';

class AdminHomePage extends StatefulWidget {
  final String accessToken;
  final int initialTabIndex;

  const AdminHomePage({
    super.key,
    required this.accessToken,
    this.initialTabIndex = 0,
  });

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _currentIndex = 0;
  bool _isDashboardLoading = true;
  bool _isPklsLoading = true;
  String? _dashboardError;
  String? _pklsError;
  Map<String, dynamic>? _dashboard;
  List<dynamic> _pkls = [];
  int? _processingId;
  final DateFormat _detailFormatter = DateFormat('d MMM HH.mm', 'id');

  // ── Token ──────────────────────────────────────────────────────────────
  Future<String?> _requireAdminToken() async {
    final token = await TokenManager.getValidAccessToken();
    if (token != null) return token;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi admin berakhir, silakan login ulang.'),
        ),
      );
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex.clamp(0, 3);
    _loadDashboard();
    _loadPKLs();
  }

  List<Map<String, dynamic>> get _pendingPkls => _pkls
      .where(
        (item) =>
            (item['status_verifikasi'] ?? '').toString().toUpperCase() ==
            'PENDING',
      )
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  // ── Data loading ───────────────────────────────────────────────────────
  Future<void> _loadDashboard() async {
    setState(() {
      _isDashboardLoading = true;
      _dashboardError = null;
    });
    try {
      final token = await _requireAdminToken();
      if (token == null) {
        if (!mounted) return;
        setState(() =>
            _dashboardError = 'Sesi admin berakhir, silakan login ulang.');
        return;
      }
      final data = await ApiService.getAdminDashboard(token: token);
      if (!mounted) return;
      setState(() => _dashboard = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _dashboardError = 'Gagal memuat dashboard: $e');
    } finally {
      if (mounted) setState(() => _isDashboardLoading = false);
    }
  }

  Future<void> _loadPKLs() async {
    setState(() {
      _isPklsLoading = true;
      _pklsError = null;
    });
    try {
      final token = await _requireAdminToken();
      if (token == null) {
        if (!mounted) return;
        setState(
            () => _pklsError = 'Sesi admin berakhir, silakan login ulang.');
        return;
      }
      final data = await ApiService.getAdminPKLs(token: token);
      if (!mounted) return;
      setState(() => _pkls = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pklsError = 'Gagal memuat data PKL: $e');
    } finally {
      if (mounted) setState(() => _isPklsLoading = false);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────
  Future<void> _deletePKL(Map<String, dynamic> pkl) async {
    final id = (pkl['id'] as num?)?.toInt();
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus PKL?'),
        content: Text(
          'Data PKL ini akan dihapus (termasuk data terkait).\n\nID: $id',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _processingId = id);

    try {
      final token = await _requireAdminToken();
      if (token == null) return;
      await ApiService.deleteAdminPKL(token: token, pklId: id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PKL berhasil dihapus.')),
      );
      await _loadPKLs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus PKL: $e')),
      );
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([_loadDashboard(), _loadPKLs()]);
  }

  // ── Logout ─────────────────────────────────────────────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Icons.logout, size: 40, color: Colors.red.shade400),
              ),
              const SizedBox(height: 20),
              const Text(
                'Keluar dari Akun?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: adminDarkText,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Anda akan keluar dari panel admin GoMuter. Pastikan semua pekerjaan sudah tersimpan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Batal',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _performLogout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Keluar',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _performLogout() async {
    await TokenManager.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await prefs.remove('username');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  // ── Prompt Note Dialog ─────────────────────────────────────────────────
  Future<String?> _promptNote({
    required String title,
    required String description,
    bool requireInput = false,
  }) async {
    final controller = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: adminGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            requireInput ? Icons.block : Icons.check_circle,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: adminDarkText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: TextField(
                        controller: controller,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Masukkan catatan...',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Batal',
                              style:
                                  TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: adminGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      adminPrimary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                final note = controller.text.trim();
                                if (requireInput && note.isEmpty) {
                                  setModalState(() {
                                    errorText = 'Catatan wajib diisi.';
                                  });
                                  return;
                                }
                                Navigator.pop(context, note);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Simpan',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
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
  }

  // ── Verification ───────────────────────────────────────────────────────
  Future<void> _handleVerification({
    required Map<String, dynamic> pkl,
    required bool approve,
  }) async {
    final note = await _promptNote(
      title: approve ? 'Terima PKL' : 'Tolak PKL',
      description: approve
          ? 'Tambahkan catatan (opsional) untuk PKL ini.'
          : 'Masukkan alasan penolakan agar PKL mendapat feedback.',
      requireInput: !approve,
    );
    if (note == null) return;

    final id = pkl['id'] as int?;
    if (id == null) return;
    if (!mounted) return;
    setState(() => _processingId = id);

    try {
      final token = await _requireAdminToken();
      if (token == null) return;
      await ApiService.verifyPKL(
        token: token,
        id: id,
        data: {
          'status_verifikasi': approve ? 'DITERIMA' : 'DITOLAK',
          'status_aktif': approve,
          'catatan_verifikasi': note.isEmpty ? null : note,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'PKL diterima dan diaktifkan.' : 'PKL ditolak.',
          ),
        ),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memproses PKL: $e')),
      );
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _updateActiveStatus(
    Map<String, dynamic> pkl,
    bool shouldBeActive,
  ) async {
    final id = pkl['id'] as int?;
    if (id == null) return;
    if (!mounted) return;
    setState(() => _processingId = id);

    try {
      final token = await _requireAdminToken();
      if (token == null) return;
      await ApiService.verifyPKL(
        token: token,
        id: id,
        data: {
          'status_verifikasi': pkl['status_verifikasi'] ?? 'DITERIMA',
          'status_aktif': shouldBeActive,
          'catatan_verifikasi': pkl['catatan_verifikasi'],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldBeActive ? 'PKL diaktifkan.' : 'PKL dinonaktifkan.',
          ),
        ),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui status aktif: $e')),
      );
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── PKL Detail Bottom Sheet ────────────────────────────────────────────
  void _showPKLDetail(Map<String, dynamic> pkl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final latestUpdate = pkl['latest_timestamp'] as String?;
        final status = (pkl['status_verifikasi'] ?? '-').toString();
        final isActive = pkl['status_aktif'] == true;

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: adminGradient,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.store,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pkl['nama_usaha'] ?? '-',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pkl['jenis_dagangan'] ?? '-',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildStatusBadge(
                          icon: Icons.verified,
                          label: status,
                          color: _getStatusColor(status),
                        ),
                        const SizedBox(width: 12),
                        _buildStatusBadge(
                          icon: isActive ? Icons.toggle_on : Icons.toggle_off,
                          label: isActive ? 'Aktif' : 'Offline',
                          color: isActive ? Colors.green : Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDetailCard(
                      icon: Icons.schedule,
                      title: 'Jam Operasional',
                      value: pkl['jam_operasional'] ?? '-',
                    ),
                    _buildDetailCard(
                      icon: Icons.location_on,
                      title: 'Alamat Domisili',
                      value: pkl['alamat_domisili'] ?? '-',
                    ),
                    if (pkl['catatan_verifikasi'] != null &&
                        (pkl['catatan_verifikasi'] as String).isNotEmpty)
                      _buildDetailCard(
                        icon: Icons.notes,
                        title: 'Catatan Verifikasi',
                        value: pkl['catatan_verifikasi'],
                      ),
                    if (latestUpdate != null)
                      _buildDetailCard(
                        icon: Icons.my_location,
                        title: 'Lokasi Terakhir',
                        value:
                            '${pkl['latest_latitude'] ?? '-'}, ${pkl['latest_longitude'] ?? '-'}\n${_formatDateTime(latestUpdate)}',
                      ),
                    _buildDetailCard(
                      icon: Icons.star,
                      title: 'Rating',
                      value: _formatRating(
                        pkl['average_rating'],
                        pkl['rating_count'],
                      ),
                      valueColor: Colors.amber,
                    ),
                  ],
                ),
              ),
              // Footer
              Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  top: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Tutup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: adminPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: adminPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: adminPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: adminPrimary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? adminDarkText,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DITERIMA':
        return statusAccepted;
      case 'DITOLAK':
        return statusRejected;
      case 'PENDING':
        return statusPending;
      default:
        return Colors.grey;
    }
  }

  // ── Greeting ───────────────────────────────────────────────────────────
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Selamat Pagi,';
    if (hour < 15) return 'Selamat Siang,';
    if (hour < 18) return 'Selamat Sore,';
    return 'Selamat Malam,';
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: adminBg,
      body: Column(
        children: [
          _buildGreetingHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Greeting Header ────────────────────────────────────────────────────
  Widget _buildGreetingHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      color: Colors.white,
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: adminPrimary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: adminPrimary, size: 28),
          ),
          const SizedBox(width: 12),
          // Greeting text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                const Text(
                  'Admin Utama',
                  style: TextStyle(
                    color: adminDarkText,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Notification bell
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined,
                  color: adminDarkText, size: 22),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  // ── Body based on selected tab ─────────────────────────────────────────
  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return AdminSummaryTab(
          isLoading: _isDashboardLoading,
          error: _dashboardError,
          dashboard: _dashboard,
          onRefresh: _refreshAll,
          onRetry: _loadDashboard,
          onApprovePending: (pkl) =>
              _handleVerification(pkl: pkl, approve: true),
        );
      case 1:
        return AdminDataPKLTab(
          isLoading: _isPklsLoading,
          error: _pklsError,
          pkls: _pkls,
          onRefresh: _refreshAll,
          onRetry: _loadPKLs,
          onVerify: (pkl, approve) =>
              _handleVerification(pkl: pkl, approve: approve),
          onToggleActive: _updateActiveStatus,
          onShowDetail: _showPKLDetail,
          onDelete: _deletePKL,
          processingId: _processingId,
        );
      case 2:
        // Center button – acts as Verif tab
        return AdminReportsTab(
          isLoading: _isDashboardLoading || _isPklsLoading,
          error: _dashboardError ?? _pklsError,
          dashboard: _dashboard,
          pendingPkls: _pendingPkls,
          onRefresh: _refreshAll,
          onRetry: _refreshAll,
          onVerify: (pkl, approve) =>
              _handleVerification(pkl: pkl, approve: approve),
          onToggleActive: _updateActiveStatus,
          onShowDetail: _showPKLDetail,
          onDelete: _deletePKL,
          processingId: _processingId,
        );
      case 3:
        // Akun tab – show logout option
        return _buildAkunTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Akun Tab ───────────────────────────────────────────────────────────
  Widget _buildAkunTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        // Profile Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: adminGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 16),
              const Text(
                'Admin Utama',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: adminDarkText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Administrator GoMuter',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Menu items
        _buildMenuTile(
          icon: Icons.refresh,
          title: 'Segarkan Data',
          onTap: _refreshAll,
        ),
        _buildMenuTile(
          icon: Icons.logout,
          title: 'Keluar',
          iconColor: Colors.red,
          titleColor: Colors.red,
          onTap: _showLogoutDialog,
        ),
      ],
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (iconColor ?? adminPrimary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor ?? adminPrimary, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: titleColor ?? adminDarkText,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
      ),
    );
  }

  // ── Bottom Navigation Bar ──────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_filled, 'Home'),
              _buildNavItem(1, Icons.store, 'PKL'),
              _buildCenterNavItem(),
              _buildNavItem(2, Icons.favorite_outline, 'Verif'),
              _buildNavItem(3, Icons.settings, 'Akun'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    // Adjust index for items after center button
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? adminPrimary : Colors.grey.shade400,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? adminPrimary : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterNavItem() {
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = 2),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: adminGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: adminPrimary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.qr_code_scanner,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  String _formatRating(dynamic rating, dynamic count) {
    final score = rating == null ? null : double.tryParse(rating.toString());
    final total = count == null ? 0 : int.tryParse(count.toString()) ?? 0;
    if (score == null) return 'Belum ada rating';
    return '${score.toStringAsFixed(1)} • $total ulasan';
  }

  String _formatDateTime(String isoString) {
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return '-';
    return _detailFormatter.format(parsed.toLocal());
  }
}
