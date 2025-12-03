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
  });

  final PklNavItem current;
  final ValueChanged<PklNavItem>? onCurrentTap;

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
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFFE8F9EF) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          color: isActive ? const Color(0xFF0D8A3A) : Colors.black54,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                            color: isActive ? const Color(0xFF0D8A3A) : Colors.black87,
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
}
