import 'package:flutter/material.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePasswordVisibility,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePasswordVisibility;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthTextField(
          controller: usernameController,
          label: 'Username',
          icon: Icons.person_outline_rounded,
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    final iconColor = Theme.of(context).iconTheme.color ?? textColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.10);
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.78);

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        textInputAction: textInputAction,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: label,
          hintStyle: TextStyle(
            color: textColor?.withValues(alpha: isDark ? 0.65 : 0.55),
          ),
          prefixIcon: Icon(icon, color: iconColor?.withValues(alpha: 0.70)),
          suffixIcon: suffixIcon == null
              ? null
              : IconButton(
                  onPressed: onSuffixPressed,
                  icon: Icon(
                    suffixIcon,
                    color: iconColor?.withValues(alpha: 0.70),
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
