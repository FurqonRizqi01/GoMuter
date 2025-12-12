import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api_service.dart';
import '../../navigation/admin_routes.dart';
import '../../navigation/pkl_routes.dart';
import '../pembeli/pembeli_home_page.dart';
import '../../utils/token_manager.dart';
import 'login_form.dart';
import 'register_form.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLogin = true;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedRole = 'USER';
  bool _isLoading = false;
  String? _errorText;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final result = await ApiService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      final accessToken = result['access'];
      final refreshToken = result['refresh'];
      final currentUser = await ApiService.getCurrentUser(accessToken);
      final role = (currentUser['role'] as String?)?.toUpperCase() ?? 'USER';
      final username =
          (currentUser['username'] as String?)?.trim() ??
          _usernameController.text.trim();

      await TokenManager.saveTokens(access: accessToken, refresh: refreshToken);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
      await prefs.setString('username', username);

      if (!mounted) return;
      _navigateToRoleHome(role, accessToken);
    } catch (e) {
      setState(() {
        _errorText = 'Login gagal. Periksa username/password.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await ApiService.register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _selectedRole,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrasi berhasil, silakan login.')),
      );

      setState(() {
        _isLogin = true;
      });
    } catch (e) {
      setState(() {
        _errorText = 'Registrasi gagal. Pastikan data valid.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToRoleHome(String role, String accessToken) {
    if (role == 'PKL') {
      Navigator.pushReplacementNamed(context, PklRoutes.home);
      return;
    }

    if (role == 'ADMIN') {
      Navigator.pushReplacementNamed(
        context,
        AdminRoutes.dashboard,
        arguments: accessToken,
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PembeliHomePage()),
    );
  }

  void _toggleMode(bool isLogin) {
    setState(() {
      _isLogin = isLogin;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          const _AuthBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _Header(primary: primary),
                      const SizedBox(height: 20),
                      _SegmentedToggle(
                        isLogin: _isLogin,
                        onSelect: _toggleMode,
                      ),
                      const SizedBox(height: 16),
                      _GlassCard(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isLogin
                              ? LoginForm(
                                  key: const ValueKey('login'),
                                  usernameController: _usernameController,
                                  passwordController: _passwordController,
                                  obscurePassword: _obscurePassword,
                                  onTogglePasswordVisibility: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                )
                              : RegisterForm(
                                  key: const ValueKey('register'),
                                  selectedRole: _selectedRole,
                                  onRoleSelected: (role) {
                                    setState(() {
                                      _selectedRole = role;
                                    });
                                  },
                                  onAdminLoginTap: () {
                                    _toggleMode(true);
                                  },
                                  usernameController: _usernameController,
                                  emailController: _emailController,
                                  passwordController: _passwordController,
                                  obscurePassword: _obscurePassword,
                                  onTogglePasswordVisibility: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  accentColor: primary,
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : (_isLogin ? _handleLogin : _handleRegister),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _isLogin ? 'Masuk' : 'Buat Akun Baru',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!_isLogin)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Dengan mendaftar, Anda menyetujui Syarat & Ketentuan kami.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF04150B), Color(0xFF071B10), Color(0xFF050607)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -140,
            top: -120,
            child: _GlowBlob(color: primary.withValues(alpha: 0.18), size: 340),
          ),
          Positioned(
            right: -150,
            top: 140,
            child: _GlowBlob(color: primary.withValues(alpha: 0.10), size: 320),
          ),
          Positioned(
            left: -120,
            bottom: -140,
            child: _GlowBlob(color: primary.withValues(alpha: 0.12), size: 360),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0.0)]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.primary});

  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1,
            ),
          ),
          child: Icon(Icons.store_rounded, size: 46, color: primary),
        ),
        const SizedBox(height: 16),
        const Text(
          'Selamat Datang',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Temukan jajanan kaki lima terbaik di sekitarmu',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  const _SegmentedToggle({required this.isLogin, required this.onSelect});

  final bool isLogin;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Masuk',
              selected: isLogin,
              accent: primary,
              onTap: () => onSelect(true),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              label: 'Daftar',
              selected: !isLogin,
              accent: primary,
              onTap: () => onSelect(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: selected
              ? Border.all(color: accent.withValues(alpha: 0.55), width: 1)
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.65),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}
