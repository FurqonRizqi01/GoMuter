import 'package:flutter/material.dart';

class RegisterForm extends StatelessWidget {
  const RegisterForm({
    super.key,
    required this.selectedRole,
    required this.onRoleSelected,
    required this.onAdminLoginTap,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePasswordVisibility,
    required this.accentColor,
  });

  final String selectedRole;
  final ValueChanged<String> onRoleSelected;
  final VoidCallback onAdminLoginTap;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePasswordVisibility;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PILIH PERAN',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                label: 'Pembeli',
                value: 'USER',
                icon: Icons.person_search_rounded,
                selected: selectedRole == 'USER',
                accent: accentColor,
                onTap: () => onRoleSelected('USER'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RoleCard(
                label: 'Pedagang Kaki Lima',
                value: 'PKL',
                icon: Icons.storefront_rounded,
                selected: selectedRole == 'PKL',
                accent: accentColor,
                onTap: () => onRoleSelected('PKL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: onAdminLoginTap,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.70),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: Icon(
              Icons.admin_panel_settings_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.70),
            ),
            label: Text(
              'MASUK SEBAGAI ADMIN',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AuthTextField(
          controller: usernameController,
          label: 'Username',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _AuthTextField(
          controller: emailController,
          label: 'Email',
          icon: Icons.mail_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _AuthTextField(
          controller: passwordController,
          label: 'Kata Sandi',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          onSuffixPressed: onTogglePasswordVisibility,
          suffixIcon: obscurePassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.80)
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
                Center(
                  child: Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.65),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: selected ? 1.0 : 0.75,
                    ),
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Positioned(
              right: 0,
              top: 0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: selected ? 1.0 : 0.8,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: selected ? Colors.white : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.onSuffixPressed,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixPressed;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        textInputAction: textInputAction,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: label,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
          prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.70)),
          suffixIcon: suffixIcon == null
              ? null
              : IconButton(
                  onPressed: onSuffixPressed,
                  icon: Icon(
                    suffixIcon,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
