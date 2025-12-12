import 'package:flutter/material.dart';

import '../widgets/admin_pkl_card.dart';
import '../widgets/admin_state_widgets.dart';

// Design constants
const Color _primaryColor = Color(0xFF1B7B5A);
const Color _secondaryColor = Color(0xFF2D9D78);
const Color _darkText = Color(0xFF1A1A2E);

class AdminReportsTab extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? dashboard;
  final List<Map<String, dynamic>> pendingPkls;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRetry;
  final void Function(Map<String, dynamic> pkl, bool approve) onVerify;
  final void Function(Map<String, dynamic> pkl, bool shouldBeActive)
  onToggleActive;
  final void Function(Map<String, dynamic> pkl) onShowDetail;
  final int? processingId;

  const AdminReportsTab({
    super.key,
    required this.isLoading,
    required this.error,
    required this.dashboard,
    required this.pendingPkls,
    required this.onRefresh,
    required this.onRetry,
    required this.onVerify,
    required this.onToggleActive,
    required this.onShowDetail,
    required this.processingId,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Memuat laporan...',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (error != null) {
      return AdminErrorState(message: error!, onRetry: onRetry);
    }

    final reports = (dashboard?['reports'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _primaryColor,
      backgroundColor: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Reports Section
          Container(
            padding: const EdgeInsets.all(20),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.analytics,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Laporan & Insight',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                        Text(
                          'Perhatian dan prioritas',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (reports.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _primaryColor.withValues(alpha: 0.08),
                          _secondaryColor.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            size: 40,
                            color: _primaryColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Semua Aman! 🎉',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _darkText,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tidak ada laporan prioritas',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                else
                  ...reports.map(_ReportCard.new),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Pending PKLs Section
          Container(
            padding: const EdgeInsets.all(20),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFf093fb), Color(0xFFf5576c)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.pending_actions,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Menunggu Tindakan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                          Text(
                            '${pendingPkls.length} PKL perlu verifikasi',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pendingPkls.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${pendingPkls.length}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (pendingPkls.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tidak ada PKL menunggu verifikasi',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                else
                  ...pendingPkls
                      .take(5)
                      .map(
                        (pkl) => AdminPKLCard(
                          pkl: pkl,
                          isProcessing: processingId == pkl['id'],
                          onVerify: onVerify,
                          onToggleActive: onToggleActive,
                          onShowDetail: onShowDetail,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportCard(this.report);

  @override
  Widget build(BuildContext context) {
    final severity = (report['severity'] ?? 'info').toString().toLowerCase();
    final colorSet = _getSeverityColors(severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorSet.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorSet.color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorSet.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(colorSet.icon, size: 18, color: colorSet.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    report['title'] ?? '-',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _darkText,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorSet.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    severity.toUpperCase(),
                    style: TextStyle(
                      color: colorSet.color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              report['description'] ?? '-',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (report['action'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorSet.color.withValues(alpha: 0.1),
                      colorSet.color.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: colorSet.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        report['action'],
                        style: TextStyle(
                          color: colorSet.color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _SeverityColorSet _getSeverityColors(String severity) {
    switch (severity) {
      case 'danger':
        return _SeverityColorSet(
          color: Colors.red,
          bgColor: Colors.red.shade50,
          icon: Icons.error,
        );
      case 'warning':
        return _SeverityColorSet(
          color: Colors.orange,
          bgColor: Colors.orange.shade50,
          icon: Icons.warning,
        );
      default:
        return _SeverityColorSet(
          color: Colors.blueGrey,
          bgColor: Colors.blueGrey.shade50,
          icon: Icons.info,
        );
    }
  }
}

class _SeverityColorSet {
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _SeverityColorSet({
    required this.color,
    required this.bgColor,
    required this.icon,
  });
}
