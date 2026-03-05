import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../admin_theme.dart';
import '../widgets/admin_state_widgets.dart';

class AdminSummaryTab extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? dashboard;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRetry;
  final void Function(Map<String, dynamic> pkl)? onApprovePending;

  const AdminSummaryTab({
    super.key,
    required this.isLoading,
    required this.error,
    required this.dashboard,
    required this.onRefresh,
    required this.onRetry,
    this.onApprovePending,
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
                color: adminPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                color: adminPrimary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Memuat data...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    if (error != null) {
      return AdminErrorState(message: error!, onRetry: onRetry);
    }

    final summary = dashboard?['summary'] as Map<String, dynamic>?;
    final trend = (dashboard?['trend'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final topPkls = (dashboard?['top_pkls'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final pendingPreview =
        (dashboard?['pending_preview'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: adminPrimary,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // ── Section Header ──────────────────────────────────────────
          const Text(
            'Ringkasan Harian',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: adminDarkText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pantau performa PKL dan pesanan hari ini.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // ── Summary Cards 2x2 ───────────────────────────────────────
          if (summary != null)
            _SummaryCardGrid(summary: summary)
          else
            const AdminEmptyState(message: 'Belum ada data ringkasan.'),
          const SizedBox(height: 24),

          // ── Trend Chart ─────────────────────────────────────────────
          _TrendCard(trend: trend),
          const SizedBox(height: 24),

          // ── Registrasi Baru ─────────────────────────────────────────
          if (pendingPreview.isNotEmpty)
            _RegistrasiBaru(
              pending: pendingPreview,
              onApprovePending: onApprovePending,
            ),

          // ── Top PKL ─────────────────────────────────────────────────
          if (topPkls.isNotEmpty) ...[
            const SizedBox(height: 24),
            _TopPKLSection(pkls: topPkls),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Summary Card Grid (2×2)
// ═══════════════════════════════════════════════════════════════════════════
class _SummaryCardGrid extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryCardGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.shopping_cart_outlined,
                iconBgColor: adminPrimary.withValues(alpha: 0.12),
                iconColor: adminPrimary,
                title: 'Total Pesanan',
                value: _fmt(summary['total_pkl']),
                change: '+12%',
                isHighlight: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet_outlined,
                iconBgColor: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                iconColor: const Color(0xFF3B82F6),
                title: 'Pendapatan',
                value: _fmtCompact(summary['location_updates_week']),
                change: '+5%',
                isHighlight: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.chat_bubble_outline,
                iconBgColor: adminPrimary.withValues(alpha: 0.12),
                iconColor: adminPrimary,
                title: 'PKL Aktif',
                value: _fmt(summary['active_pkl']),
                change: '+2%',
                isHighlight: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.qr_code_2,
                iconBgColor: Colors.white.withValues(alpha: 0.2),
                iconColor: Colors.white,
                title: 'Verifikasi\nPending',
                value: _fmt(summary['pending_pkl']),
                change: 'Perlu tindakan',
                isHighlight: true, // orange gradient background
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '-';
    final n = (v is num) ? v : num.tryParse(v.toString());
    if (n == null) return '-';
    return NumberFormat.decimalPattern('id').format(n);
  }

  String _fmtCompact(dynamic v) {
    if (v == null) return '-';
    final n = (v is num) ? v : num.tryParse(v.toString());
    if (n == null) return '-';
    return NumberFormat.compact(locale: 'id').format(n);
  }
}

// ─── Individual Stat Card ────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String value;
  final String change;
  final bool isHighlight;

  const _StatCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.change,
    required this.isHighlight,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isHighlight ? Colors.white : adminDarkText;
    final subColor =
        isHighlight ? Colors.white.withValues(alpha: 0.85) : adminPrimary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isHighlight ? adminGradient : null,
        color: isHighlight ? null : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isHighlight
                ? adminPrimary.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!isHighlight)
                Icon(Icons.trending_up, size: 14, color: subColor),
              if (!isHighlight) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  change,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Trend Chart Card
// ═══════════════════════════════════════════════════════════════════════════
class _TrendCard extends StatefulWidget {
  final List<Map<String, dynamic>> trend;
  const _TrendCard({required this.trend});

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  bool _is7Days = true;

  @override
  Widget build(BuildContext context) {
    final data = _is7Days ? widget.trend.take(7).toList() : widget.trend;
    final dayLabels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

    return Container(
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
          // Header
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tren Registrasi PKL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: adminDarkText,
                  ),
                ),
              ),
              _buildToggleChip('7 Hari', _is7Days, () {
                setState(() => _is7Days = true);
              }),
              const SizedBox(width: 8),
              _buildToggleChip('30 Hari', !_is7Days, () {
                setState(() => _is7Days = false);
              }),
            ],
          ),
          const SizedBox(height: 24),

          // Bar chart area
          if (data.isEmpty)
            Container(
              height: 120,
              alignment: Alignment.center,
              child: Text(
                'Belum ada data trend',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  _is7Days ? 7 : data.length,
                  (i) {
                    final entry = i < data.length ? data[i] : null;
                    final val = entry != null
                        ? ((entry['auto_updates'] ?? 0) as num).toDouble()
                        : 0.0;
                    final maxVal = data.fold<double>(
                      1,
                      (prev, e) => (((e['auto_updates'] ?? 0) as num)
                                  .toDouble() >
                              prev
                          ? ((e['auto_updates'] ?? 0) as num).toDouble()
                          : prev),
                    );
                    final heightFraction = maxVal > 0 ? val / maxVal : 0.0;
                    final isToday = i == (_is7Days ? 3 : data.length - 1);

                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: heightFraction.clamp(0.05, 1.0),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? adminPrimary
                                      : adminPrimary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _is7Days
                                ? dayLabels[i % 7]
                                : '${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.w400,
                              color: isToday
                                  ? adminDarkText
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? adminPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Registrasi Baru (Pending Preview)
// ═══════════════════════════════════════════════════════════════════════════
class _RegistrasiBaru extends StatelessWidget {
  final List<Map<String, dynamic>> pending;
  final void Function(Map<String, dynamic> pkl)? onApprovePending;

  const _RegistrasiBaru({required this.pending, this.onApprovePending});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row
        Row(
          children: [
            const Text(
              'Registrasi Baru',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: adminDarkText,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {},
              child: const Text(
                'Lihat Semua',
                style: TextStyle(
                  color: adminPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Cards
        ...pending.map((pkl) {
          final status =
              (pkl['status_verifikasi'] ?? 'PENDING').toString().toUpperCase();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
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
            child: InkWell(
              onTap:
                  onApprovePending != null ? () => onApprovePending!(pkl) : null,
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  // Avatar / photo placeholder
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: adminPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.store,
                        color: adminPrimary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pkl['nama_usaha'] ?? '-',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: adminDarkText,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pkl['alamat_domisili'] ??
                                    pkl['jenis_dagangan'] ??
                                    '-',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Badge + time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: status == 'PENDING'
                              ? adminPrimary.withValues(alpha: 0.12)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: status == 'PENDING'
                                ? adminPrimary
                                : Colors.grey.shade600,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _relativeTime(pkl['created_at']),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _relativeTime(dynamic createdAt) {
    if (createdAt == null) return '';
    final dt = DateTime.tryParse(createdAt.toString());
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}mnt yll';
    if (diff.inHours < 24) return '${diff.inHours}j yll';
    return '${diff.inDays}h yll';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Top PKL Section
// ═══════════════════════════════════════════════════════════════════════════
class _TopPKLSection extends StatelessWidget {
  final List<Map<String, dynamic>> pkls;
  const _TopPKLSection({required this.pkls});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFf7971e), Color(0xFFffd200)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'PKL Performa Terbaik',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: adminDarkText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...pkls.asMap().entries.map((entry) {
              final index = entry.key;
              final pkl = entry.value;
              final rating = _formatRating(
                pkl['average_rating'],
                pkl['rating_count'],
              );
              final isActive = pkl['status_aktif'] == true;

              return Container(
                margin: EdgeInsets.only(
                  bottom: index < pkls.length - 1 ? 12 : 0,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: index == 0
                      ? const Color(0xFFFFF7ED)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: index == 0
                      ? Border.all(
                          color: adminPrimary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: index == 0
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFFf7971e),
                                  Color(0xFFffd200),
                                ],
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.grey.shade300,
                                  Colors.grey.shade400,
                                ],
                              ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index == 0
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pkl['nama_usaha'] ?? '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: adminDarkText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${pkl['jenis_dagangan'] ?? '-'} • $rating',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? statusAccepted.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? Icons.circle : Icons.circle_outlined,
                            size: 8,
                            color: isActive ? statusAccepted : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isActive ? 'Aktif' : 'Offline',
                            style: TextStyle(
                              color: isActive ? statusAccepted : Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatRating(dynamic rating, dynamic count) {
    final score = rating == null ? null : double.tryParse(rating.toString());
    final total = count == null ? 0 : int.tryParse(count.toString()) ?? 0;
    if (score == null) return 'Belum ada rating';
    return '⭐ ${score.toStringAsFixed(1)} ($total)';
  }
}
