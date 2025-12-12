import 'package:flutter/material.dart';
import '../navigation/pkl_routes.dart';

enum PklNavItem { home, payment, preorder, chat }

extension PklNavItemDetails on PklNavItem {
  String get label {
    switch (this) {
      case PklNavItem.home:
        return 'Beranda';
      case PklNavItem.payment:
        return 'Pembayaran';
      case PklNavItem.preorder:
        return 'Pre-Order';
      case PklNavItem.chat:
        return 'Pesan';
    }
  }

  IconData get icon {
    switch (this) {
      case PklNavItem.home:
        return Icons.home_outlined;
      case PklNavItem.payment:
        return Icons.qr_code_2;
      case PklNavItem.preorder:
        return Icons.receipt_long_outlined;
      case PklNavItem.chat:
        return Icons.chat_bubble_outline;
    }
  }

  String get routeName {
    switch (this) {
      case PklNavItem.home:
        return PklRoutes.home;
      case PklNavItem.payment:
        return PklRoutes.payment;
      case PklNavItem.preorder:
        return PklRoutes.preorder;
      case PklNavItem.chat:
        return PklRoutes.chat;
    }
  }
}

class PklBottomNavBar extends StatelessWidget {
  const PklBottomNavBar({
    super.key,
    required this.current,
    this.onCurrentTap,
    this.chatBadgeCount = 0,
  });

  final PklNavItem current;
  final ValueChanged<PklNavItem>? onCurrentTap;
  final int chatBadgeCount;

  void _handleTap(BuildContext context, PklNavItem destination) {
    if (destination == current) {
      onCurrentTap?.call(destination);
      return;
    }
    Navigator.of(context).pushReplacementNamed(destination.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: PklNavItem.values.map((item) {
              final isActive = item == current;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _handleTap(context, item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFE8F9EF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildIcon(item, isActive),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isActive
                                ? const Color(0xFF0D8A3A)
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(PklNavItem item, bool isActive) {
    final icon = Icon(
      item.icon,
      color: isActive ? const Color(0xFF0D8A3A) : Colors.black54,
    );
    if (item != PklNavItem.chat || chatBadgeCount <= 0) {
      return icon;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              chatBadgeCount > 9 ? '9+' : '$chatBadgeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
