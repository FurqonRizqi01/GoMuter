import 'package:flutter/material.dart';

import '../widgets/admin_pkl_card.dart';
import '../widgets/admin_state_widgets.dart';

// Design constants
const Color _primaryColor = Color(0xFF1B7B5A);
const Color _secondaryColor = Color(0xFF2D9D78);

class AdminDataPKLTab extends StatefulWidget {
  final bool isLoading;
  final String? error;
  final List<dynamic> pkls;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRetry;
  final void Function(Map<String, dynamic> pkl, bool approve) onVerify;
  final void Function(Map<String, dynamic> pkl, bool shouldBeActive) onToggleActive;
  final void Function(Map<String, dynamic> pkl) onShowDetail;
  final int? processingId;

  const AdminDataPKLTab({
    super.key,
    required this.isLoading,
    required this.error,
    required this.pkls,
    required this.onRefresh,
    required this.onRetry,
    required this.onVerify,
    required this.onToggleActive,
    required this.onShowDetail,
    required this.processingId,
  });

  @override
  State<AdminDataPKLTab> createState() => _AdminDataPKLTabState();
}

class _AdminDataPKLTabState extends State<AdminDataPKLTab> {
  static const _statusOptions = [
    {'label': 'Semua', 'value': 'ALL', 'icon': Icons.apps},
    {'label': 'Pending', 'value': 'PENDING', 'icon': Icons.hourglass_empty},
    {'label': 'Diterima', 'value': 'DITERIMA', 'icon': Icons.check_circle},
    {'label': 'Ditolak', 'value': 'DITOLAK', 'icon': Icons.cancel},
  ];

  static const _activeOptions = [
    _ActiveFilterOption('Semua', null, Icons.layers),
    _ActiveFilterOption('Aktif', true, Icons.wifi),
    _ActiveFilterOption('Offline', false, Icons.wifi_off),
  ];

  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'ALL';
  bool? _activeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredPkls {
    final searchTerm = _searchController.text.trim().toLowerCase();
    return widget.pkls.where((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final status = (map['status_verifikasi'] ?? '').toString().toUpperCase();
      if (_statusFilter != 'ALL' && status != _statusFilter) return false;
      if (_activeFilter != null && (map['status_aktif'] == true) != _activeFilter) {
        return false;
      }
      if (searchTerm.isNotEmpty) {
        final name = (map['nama_usaha'] ?? '').toString().toLowerCase();
        final type = (map['jenis_dagangan'] ?? '').toString().toLowerCase();
        if (!name.contains(searchTerm) && !type.contains(searchTerm)) {
          return false;
        }
      }
      return true;
    }).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
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
              'Memuat data PKL...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    if (widget.error != null) {
      return AdminErrorState(message: widget.error!, onRetry: widget.onRetry);
    }

    final data = _filteredPkls;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: _primaryColor,
      backgroundColor: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Modern Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: Container(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primaryColor, _secondaryColor],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.search,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                hintText: 'Cari nama usaha atau jenis dagangan...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() => _searchController.clear());
                        },
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 24),
          
          // Filter Card
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
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_primaryColor, _secondaryColor],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.filter_list,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Filter Data',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Status Verifikasi
                Text(
                  'Status Verifikasi',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusOptions.map((option) {
                      final selected = _statusFilter == option['value'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _statusFilter = option['value'] as String),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? const LinearGradient(
                                        colors: [_primaryColor, _secondaryColor],
                                      )
                                    : null,
                                color: selected ? null : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: _primaryColor.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    option['icon'] as IconData,
                                    size: 16,
                                    color: selected ? Colors.white : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    option['label'] as String,
                                    style: TextStyle(
                                      color: selected ? Colors.white : Colors.grey.shade700,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Status Aktif
                Text(
                  'Status Aktif PKL',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _activeOptions.map((option) {
                      final selected = _activeFilter == option.value;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _activeFilter = option.value),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? const LinearGradient(
                                        colors: [_primaryColor, _secondaryColor],
                                      )
                                    : null,
                                color: selected ? null : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: _primaryColor.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    option.icon,
                                    size: 16,
                                    color: selected ? Colors.white : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    option.label,
                                    style: TextStyle(
                                      color: selected ? Colors.white : Colors.grey.shade700,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Result Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.store,
                  size: 18,
                  color: _primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '${data.length} PKL ditemukan',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // PKL List
          if (data.isEmpty)
            const AdminEmptyState(message: 'Tidak ada PKL sesuai filter saat ini.')
          else
            ...data.map(
              (pkl) => AdminPKLCard(
                pkl: pkl,
                isProcessing: widget.processingId == pkl['id'],
                onVerify: widget.onVerify,
                onToggleActive: widget.onToggleActive,
                onShowDetail: widget.onShowDetail,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveFilterOption {
  final String label;
  final bool? value;
  final IconData icon;
  const _ActiveFilterOption(this.label, this.value, this.icon);
}
