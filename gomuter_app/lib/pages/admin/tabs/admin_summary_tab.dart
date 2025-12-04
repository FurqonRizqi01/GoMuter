import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/admin_state_widgets.dart';

// Modern Admin Theme Colors
const Color _primaryColor = Color(0xFF1E3A5F);
const Color _secondaryColor = Color(0xFF3D5A80);
// ignore: unused_element
const Color _accentColor = Color(0xFF00D9FF);
const Color _goldColor = Color(0xFFFFD700);
// ignore: unused_element
const Color _lightBg = Color(0xFFF8FAFC);
const Color _darkText = Color(0xFF1A1A2E);

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
                color: _primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                color: _primaryColor,
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
      color: _primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildSectionHeader(
            context,
            icon: Icons.analytics,
            title: 'Ringkasan Harian',
          ),
          const SizedBox(height: 16),
          if (summary != null)
            _SummaryCardGrid(summary: summary)
          else
            const AdminEmptyState(message: 'Belum ada data ringkasan.'),
          const SizedBox(height: 24),
          _TrendCard(trend: trend),
          const SizedBox(height: 24),
          _TopPKLSection(pkls: topPkls),
          if (pendingPreview.isNotEmpty) ...[
            const SizedBox(height: 24),
            _PendingPreview(
              pending: pendingPreview,
              onApprovePending: onApprovePending,
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _darkText,
          ),
        ),
      ],
    );
  }
}

class _SummaryCardGrid extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryCardGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _DashboardStatCard(
        title: 'Total PKL',
        value: _formatNumber(summary['total_pkl']),
        subtitle: 'Aktif ${summary['active_pkl']} • Offline ${summary['inactive_pkl']}',
        icon: Icons.store,
        gradientColors: [const Color(0xFF667eea), const Color(0xFF764ba2)],
      ),
      _DashboardStatCard(
        title: 'Verifikasi',
        value: _formatNumber(summary['verified_pkl']),
        subtitle: 'Pending ${summary['pending_pkl']} • Ditolak ${summary['rejected_pkl']}',
        icon: Icons.verified_user,
        gradientColors: [const Color(0xFF11998e), const Color(0xFF38ef7d)],
      ),
      _DashboardStatCard(
        title: 'PKL Baru (7 hari)',
        value: _formatNumber(summary['new_pkls_week'], compact: true),
        subtitle: 'Minggu lalu ${summary['prev_new_pkls']}',
        icon: Icons.trending_up,
        gradientColors: [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      ),
      _DashboardStatCard(
        title: 'Update Lokasi',
        value: _formatNumber(summary['location_updates_week'], compact: true),
        subtitle: 'Minggu lalu ${summary['prev_location_updates']}',
        icon: Icons.location_on,
        gradientColors: [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
      ),
      _DashboardStatCard(
        title: 'Rating Rata-rata',
        value: summary['average_rating'] == null
            ? '-'
            : summary['average_rating'].toString(),
        subtitle: 'Total ${summary['rating_count']} ulasan',
        icon: Icons.star,
        gradientColors: [const Color(0xFFf7971e), const Color(0xFFffd200)],
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => cards[index],
    );
  }

  String _formatNumber(dynamic value, {bool compact = false}) {
    if (value == null) return '-';
    final number = (value is num) ? value : num.tryParse(value.toString());
    if (number == null) return '-';
    final formatter = compact
        ? NumberFormat.compact(locale: 'id')
        : NumberFormat.decimalPattern('id');
    return formatter.format(number);
  }
}

class _DashboardStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final List<Color> gradientColors;

  const _DashboardStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradientColors,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                    gradient: LinearGradient(
                      colors: [_primaryColor, _secondaryColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.show_chart,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Aktivitas 7 Hari Terakhir',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (trend.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Belum ada data trend',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 160,
                child: _TrendSparkline(
                  data: trend,
                  series: const [
                    _SparkSeries('auto_updates', Color(0xFF667eea)),
                    _SparkSeries('live_views', Color(0xFF11998e)),
                    _SparkSeries('search_hits', Color(0xFFf7971e)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  _TrendLegend(
                    color: Color(0xFF667eea),
                    label: 'Update Lokasi',
                  ),
                  _TrendLegend(
                    color: Color(0xFF11998e),
                    label: 'Dilihat Pembeli',
                  ),
                  _TrendLegend(
                    color: Color(0xFFf7971e),
                    label: 'Pencarian',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                    color: _darkText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (pkls.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.star_border, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'Belum ada rating',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...pkls.asMap().entries.map((entry) {
                final index = entry.key;
                final pkl = entry.value;
                final rating = _formatRating(pkl['average_rating'], pkl['rating_count']);
                final isActive = pkl['status_aktif'] == true;
                
                return Container(
                  margin: EdgeInsets.only(bottom: index < pkls.length - 1 ? 12 : 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: index == 0 
                        ? _goldColor.withValues(alpha: 0.1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: index == 0 
                        ? Border.all(color: _goldColor.withValues(alpha: 0.3))
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
                                  colors: [Color(0xFFf7971e), Color(0xFFffd200)],
                                )
                              : LinearGradient(
                                  colors: [Colors.grey.shade300, Colors.grey.shade400],
                                ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: index == 0 ? Colors.white : Colors.grey.shade600,
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
                                color: _darkText,
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
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isActive ? Icons.circle : Icons.circle_outlined,
                              size: 8,
                              color: isActive ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isActive ? 'Aktif' : 'Offline',
                              style: TextStyle(
                                color: isActive ? Colors.green : Colors.grey,
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

class _PendingPreview extends StatelessWidget {
  final List<Map<String, dynamic>> pending;
  final void Function(Map<String, dynamic> pkl)? onApprovePending;

  const _PendingPreview({
    required this.pending,
    this.onApprovePending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                        'Menunggu Verifikasi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _darkText,
                        ),
                      ),
                      Text(
                        '${pending.length} PKL perlu ditinjau',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
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
                    '${pending.length}',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...pending.map((pkl) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.store,
                        color: Colors.orange,
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
                              color: _darkText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pkl['jenis_dagangan'] ?? '-',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_primaryColor, _secondaryColor],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onApprovePending == null 
                              ? null 
                              : () => onApprovePending!(pkl),
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'Periksa',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
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
}

class _TrendSparkline extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final List<_SparkSeries> series;

  const _TrendSparkline({required this.data, required this.series});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendSparklinePainter(data: data, series: series),
      child: Container(),
    );
  }
}

class _TrendSparklinePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final List<_SparkSeries> series;

  _TrendSparklinePainter({required this.data, required this.series});

  @override
  void paint(Canvas canvas, Size size) {
    final points = data.length.clamp(2, 1000);
    final maxValue = _resolveMaxValue();
    final step = points <= 1 ? size.width : size.width / (points - 1);

    for (final item in series) {
      final paint = Paint()
        ..color = item.color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final value = (data[i][item.key] as num?)?.toDouble() ?? 0;
        final dx = step * i;
        final normalized = maxValue == 0 ? 0 : value / maxValue;
        final dy = size.height - (normalized * size.height);
        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  double _resolveMaxValue() {
    double maxValue = 0;
    for (final row in data) {
      for (final item in series) {
        final value = (row[item.key] as num?)?.toDouble() ?? 0;
        if (value > maxValue) {
          maxValue = value;
        }
      }
    }
    return maxValue <= 0 ? 1 : maxValue;
  }
}

class _SparkSeries {
  final String key;
  final Color color;
  const _SparkSeries(this.key, this.color);
}

class _TrendLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _TrendLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
