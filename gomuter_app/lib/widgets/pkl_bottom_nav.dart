import 'package:flutter/material.dart';
import '../navigation/pkl_routes.dart';
import 'package:gomuter_app/utils/theme_manager.dart';

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

class PklBottomNavBar extends StatefulWidget {
  const PklBottomNavBar({
    super.key,
    required this.current,
    this.onCurrentTap,
    this.chatBadgeCount = 0,
  });

  final PklNavItem current;
  final ValueChanged<PklNavItem>? onCurrentTap;
  final int chatBadgeCount;

  @override
  State<PklBottomNavBar> createState() => _PklBottomNavBarState();
}

class _PklBottomNavBarState extends State<PklBottomNavBar> {
  final ThemeManager _themeManager = ThemeManager();

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeManager.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _handleTap(BuildContext context, PklNavItem destination) {
    if (destination == widget.current) {
      widget.onCurrentTap?.call(destination);
      return;
    }
    Navigator.of(context).pushReplacementNamed(destination.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _themeManager.cardColor;
    final activeBgColor = _themeManager.accentSurfaceColor;
    final activeColor = _themeManager.primaryGreen;
    final inactiveLabelColor = _themeManager.mutedTextColor;
    final inactiveIconColor = _themeManager.hintTextColor;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
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
              final isActive = item == widget.current;
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
                            ? activeBgColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          _buildIcon(
                            item,
                            isActive,
                            activeColor: activeColor,
                            inactiveColor: inactiveIconColor,
                          ),
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
                                  ? activeColor
                                  : inactiveLabelColor,
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

    Widget _buildIcon(
      PklNavItem item,
      bool isActive, {
      required Color activeColor,
      required Color inactiveColor,
    }) {
    final icon = Icon(
      item.icon,
        color: isActive ? activeColor : inactiveColor,
    );
    if (item != PklNavItem.chat || widget.chatBadgeCount <= 0) {
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
              widget.chatBadgeCount > 9 ? '9+' : '${widget.chatBadgeCount}',
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
