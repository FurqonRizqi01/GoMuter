import 'package:flutter/material.dart';
import 'package:gomuter_app/api_service.dart';
import 'package:intl/intl.dart';

import 'tabs/admin_data_pkl_tab.dart';
import 'tabs/admin_reports_tab.dart';
import 'tabs/admin_summary_tab.dart';

// Modern Admin Theme Colors
const Color _primaryColor = Color(0xFF1E3A5F);
const Color _secondaryColor = Color(0xFF3D5A80);
const Color _accentColor = Color(0xFF00D9FF);
const Color _goldColor = Color(0xFFFFD700);
const Color _lightBg = Color(0xFFF8FAFC);
const Color _darkText = Color(0xFF1A1A2E);

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

class _AdminHomePageState extends State<AdminHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isDashboardLoading = true;
  bool _isPklsLoading = true;
  String? _dashboardError;
  String? _pklsError;
  Map<String, dynamic>? _dashboard;
  List<dynamic> _pkls = [];
  int? _processingId;
  final DateFormat _detailFormatter = DateFormat('d MMM HH.mm', 'id');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _loadDashboard();
    _loadPKLs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _pendingPkls => _pkls
      .where((item) =>
          (item['status_verifikasi'] ?? '').toString().toUpperCase() == 'PENDING')
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  Future<void> _loadDashboard() async {
    setState(() {
      _isDashboardLoading = true;
      _dashboardError = null;
    });

    try {
      final data = await ApiService.getAdminDashboard(token: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _dashboard = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dashboardError = 'Gagal memuat dashboard: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDashboardLoading = false;
        });
      }
    }
  }

  Future<void> _loadPKLs() async {
    setState(() {
      _isPklsLoading = true;
      _pklsError = null;
    });

    try {
      final data = await ApiService.getAdminPKLs(token: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _pkls = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pklsError = 'Gagal memuat data PKL: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPklsLoading = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      _loadDashboard(),
      _loadPKLs(),
    ]);
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
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
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout,
                  size: 40,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              const Text(
                'Keluar dari Akun?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              const SizedBox(height: 12),
              
              // Description
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
              
              // Buttons
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
                        onPressed: () {
                          Navigator.pop(context); // Close dialog
                          _performLogout();
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

  void _performLogout() {
    // Navigate back to login/home and clear navigation stack
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

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
                            gradient: LinearGradient(
                              colors: [_primaryColor, _secondaryColor],
                            ),
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
                              color: _darkText,
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
                          style: const TextStyle(color: Colors.red, fontSize: 12),
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
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_primaryColor, _secondaryColor],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withValues(alpha: 0.3),
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
                                padding: const EdgeInsets.symmetric(vertical: 14),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'PKL diterima dan diaktifkan.' : 'PKL ditolak.'),
        ),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memproses PKL: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
        });
      }
    }
  }

  Future<void> _updateActiveStatus(Map<String, dynamic> pkl, bool shouldBeActive) async {
    final id = pkl['id'] as int?;
    if (id == null) return;
    if (!mounted) return;
    setState(() {
      _processingId = id;
    });

    try {
      await ApiService.verifyPKL(
        token: widget.accessToken,
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
          content: Text(shouldBeActive ? 'PKL diaktifkan.' : 'PKL dinonaktifkan.'),
        ),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui status aktif: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
        });
      }
    }
  }

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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_primaryColor, _secondaryColor],
                  ),
                  borderRadius: const BorderRadius.vertical(
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
                      value: _formatRating(pkl['average_rating'], pkl['rating_count']),
                      valueColor: _goldColor,
                    ),
                  ],
                ),
              ),
              // Footer button
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: _primaryColor),
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
          Icon(icon, color: Colors.white, size: 16),
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
              color: _primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primaryColor, size: 20),
          ),
          const SizedBox(width: 16),
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
                    color: valueColor ?? _darkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
        return Colors.green;
      case 'DITOLAK':
        return Colors.red;
      case 'PENDING':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      body: Column(
        children: [
          _buildAppBar(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                AdminSummaryTab(
                  isLoading: _isDashboardLoading,
                  error: _dashboardError,
                  dashboard: _dashboard,
                  onRefresh: _refreshAll,
                  onRetry: _loadDashboard,
                  onApprovePending: (pkl) =>
                      _handleVerification(pkl: pkl, approve: true),
                ),
                AdminDataPKLTab(
                  isLoading: _isPklsLoading,
                  error: _pklsError,
                  pkls: _pkls,
                  onRefresh: _refreshAll,
                  onRetry: _loadPKLs,
                  onVerify: (pkl, approve) =>
                      _handleVerification(pkl: pkl, approve: approve),
                  onToggleActive: _updateActiveStatus,
                  onShowDetail: _showPKLDetail,
                  processingId: _processingId,
                ),
                AdminReportsTab(
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
                  processingId: _processingId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryColor, _secondaryColor],
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'GoMuter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _accentColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(
                          color: _primaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Panel Manajemen PKL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              tooltip: 'Segarkan data',
              onPressed: _refreshAll,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.red.shade400.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              tooltip: 'Keluar',
              onPressed: _showLogoutDialog,
              icon: const Icon(Icons.logout, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [_primaryColor, _secondaryColor],
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        padding: const EdgeInsets.all(6),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.dashboard, size: 18),
                SizedBox(width: 6),
                Text('Ringkasan'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.store, size: 18),
                SizedBox(width: 6),
                Text('Data PKL'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.assessment, size: 18),
                SizedBox(width: 6),
                Text('Laporan'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildDetailRow(String title, dynamic value) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value.toString()),
        ],
      ),
    );
  }

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
