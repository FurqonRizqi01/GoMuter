import 'package:flutter/material.dart';
import '../navigation/pkl_routes.dart';
import 'package:gomuter_app/utils/theme_manager.dart';

enum PklNavItem { home, orders, chat, profile }

extension PklNavItemDetails on PklNavItem {
  String get label {
    switch (this) {
      case PklNavItem.home:
        return 'Beranda';
      case PklNavItem.chat:
        return 'Pesan';
      case PklNavItem.orders:
        return 'Menu';
      case PklNavItem.profile:
        return 'Profil';
    }
  }

  IconData get icon {
    switch (this) {
      case PklNavItem.home:
        return Icons.home_rounded;
      case PklNavItem.chat:
        return Icons.bar_chart_rounded;
      case PklNavItem.orders:
        return Icons.restaurant_menu_rounded;
      case PklNavItem.profile:
        return Icons.person_rounded;
    }
  }

  String get routeName {
    switch (this) {
      case PklNavItem.home:
        return PklRoutes.home;
      case PklNavItem.chat:
        return PklRoutes.chat;
      case PklNavItem.orders:
        return PklRoutes.orders;
      case PklNavItem.profile:
        return PklRoutes.profile;
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

  void _handlePlus(BuildContext context) {
    Navigator.of(context).pushNamed(PklRoutes.manage);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _themeManager.cardColor;
    final activeBgColor = _themeManager.pklPrimary.withValues(alpha: 0.14);
    final activeColor = _themeManager.pklPrimary;
    final inactiveLabelColor = _themeManager.mutedTextColor;
    final inactiveIconColor = _themeManager.hintTextColor;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 82, maxHeight: 100),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
              children: [
                Expanded(
                  child: _NavItem(
                    item: PklNavItem.home,
                    isActive: widget.current == PklNavItem.home,
                    activeBgColor: activeBgColor,
                    activeColor: activeColor,
                    inactiveIconColor: inactiveIconColor,
                    inactiveLabelColor: inactiveLabelColor,
                    onTap: () => _handleTap(context, PklNavItem.home),
                    chatBadgeCount: widget.chatBadgeCount,
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    item: PklNavItem.orders,
                    isActive: widget.current == PklNavItem.orders,
                    activeBgColor: activeBgColor,
                    activeColor: activeColor,
                    inactiveIconColor: inactiveIconColor,
                    inactiveLabelColor: inactiveLabelColor,
                    onTap: () => _handleTap(context, PklNavItem.orders),
                    chatBadgeCount: widget.chatBadgeCount,
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _handlePlus(context),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    item: PklNavItem.chat,
                    isActive: widget.current == PklNavItem.chat,
                    activeBgColor: activeBgColor,
                    activeColor: activeColor,
                    inactiveIconColor: inactiveIconColor,
                    inactiveLabelColor: inactiveLabelColor,
                    onTap: () => _handleTap(context, PklNavItem.chat),
                    chatBadgeCount: widget.chatBadgeCount,
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    item: PklNavItem.profile,
                    isActive: widget.current == PklNavItem.profile,
                    activeBgColor: activeBgColor,
                    activeColor: activeColor,
                    inactiveIconColor: inactiveIconColor,
                    inactiveLabelColor: inactiveLabelColor,
                    onTap: () => _handleTap(context, PklNavItem.profile),
                    chatBadgeCount: widget.chatBadgeCount,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.isActive,
    required this.activeBgColor,
    required this.activeColor,
    required this.inactiveIconColor,
    required this.inactiveLabelColor,
    required this.onTap,
    required this.chatBadgeCount,
  });

  final PklNavItem item;
  final bool isActive;
  final Color activeBgColor;
  final Color activeColor;
  final Color inactiveIconColor;
  final Color inactiveLabelColor;
  final VoidCallback onTap;
  final int chatBadgeCount;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      item.icon,
      color: isActive ? activeColor : inactiveIconColor,
      size: 22,
    );

    Widget iconWidget = icon;
    if (item == PklNavItem.chat && chatBadgeCount > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                chatBadgeCount > 9 ? '9+' : '$chatBadgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? activeColor : inactiveLabelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
