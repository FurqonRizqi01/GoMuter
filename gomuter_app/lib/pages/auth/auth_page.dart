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

  final _resetIdentifierController = TextEditingController();
  final _resetUidController = TextEditingController();
  final _resetTokenController = TextEditingController();
  final _resetNewPasswordController = TextEditingController();
  final _resetConfirmPasswordController = TextEditingController();

  bool _forgotPreferConfirmStep = false;

  String _selectedRole = 'USER';
  bool _isLoading = false;
  String? _errorText;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _resetIdentifierController.dispose();
    _resetUidController.dispose();
    _resetTokenController.dispose();
    _resetNewPasswordController.dispose();
    _resetConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _openForgotPasswordSheet() async {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    if (_resetIdentifierController.text.trim().isEmpty) {
      _resetIdentifierController.text = _usernameController.text.trim();
    }

    // Don't clear UID/TOKEN so user can open Gmail and come back without re-requesting.
    // Always clear the password fields for safety.
    _resetNewPasswordController.clear();
    _resetConfirmPasswordController.clear();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isRequesting = false;
        bool isConfirming = false;
        bool showConfirmStep = _forgotPreferConfirmStep;
        String? sheetError;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> requestReset() async {
              setSheetState(() {
                isRequesting = true;
                sheetError = null;
              });

              try {
                final identifier = _resetIdentifierController.text.trim();
                if (identifier.isEmpty) {
                  throw Exception('Identifier kosong');
                }

                await ApiService.requestPasswordReset(identifier: identifier);

                if (!ctx.mounted) return;
                setSheetState(() {
                  showConfirmStep = true;
                  _forgotPreferConfirmStep = true;
                });

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Jika akun ditemukan, instruksi reset dikirim ke email. Cek inbox/spam.',
                    ),
                  ),
                );
              } catch (_) {
                setSheetState(() {
                  sheetError = 'Gagal mengirim permintaan reset. Coba lagi.';
                });
              } finally {
                setSheetState(() {
                  isRequesting = false;
                });
              }
            }

            Future<void> confirmReset() async {
              setSheetState(() {
                isConfirming = true;
                sheetError = null;
              });

              try {
                final uid = _resetUidController.text.trim();
                final token = _resetTokenController.text.trim();
                final newPassword = _resetNewPasswordController.text;
                final confirmPassword = _resetConfirmPasswordController.text;

                if (uid.isEmpty || token.isEmpty) {
                  throw Exception('Token kosong');
                }
                if (newPassword.isEmpty || newPassword.length < 6) {
                  throw Exception('Password terlalu pendek');
                }
                if (newPassword != confirmPassword) {
                  throw Exception('Password tidak sama');
                }

                await ApiService.confirmPasswordReset(
                  uid: uid,
                  token: token,
                  newPassword: newPassword,
                );

                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password berhasil diubah. Silakan login.'),
                  ),
                );

                setState(() {
                  _forgotPreferConfirmStep = false;
                });
              } catch (_) {
                setSheetState(() {
                  sheetError =
                      'Gagal reset password. Pastikan UID/TOKEN benar dan belum kadaluarsa.';
                });
              } finally {
                setSheetState(() {
                  isConfirming = false;
                });
              }
            }

            final viewInsets = MediaQuery.of(ctx).viewInsets;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: viewInsets.bottom + 16,
                top: 16,
              ),
              child: _GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Lupa Password',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(
                            Icons.close,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      showConfirmStep
                          ? 'Masukkan UID dan TOKEN dari email, lalu buat password baru.'
                          : 'Masukkan email atau username. Kami akan mengirim UID & TOKEN ke email akun (cek spam).',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!showConfirmStep) ...[
                      _SheetTextField(
                        controller: _resetIdentifierController,
                        hintText: 'Email atau Username',
                        icon: Icons.alternate_email_rounded,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isRequesting ? null : requestReset,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isRequesting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text(
                                  'Kirim Instruksi Reset',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            showConfirmStep = true;
                            sheetError = null;
                            _forgotPreferConfirmStep = true;
                          });
                        },
                        child: Text(
                          'Saya sudah punya UID/TOKEN',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ] else ...[
                      _SheetTextField(
                        controller: _resetUidController,
                        hintText: 'UID (dari email)',
                        icon: Icons.badge_outlined,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _resetTokenController,
                        hintText: 'TOKEN (dari email)',
                        icon: Icons.key_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _resetNewPasswordController,
                        hintText: 'Password baru',
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _resetConfirmPasswordController,
                        hintText: 'Konfirmasi password baru',
                        icon: Icons.lock_rounded,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isConfirming ? null : confirmReset,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isConfirming
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text(
                                  'Ubah Password',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            showConfirmStep = false;
                            sheetError = null;
                            _forgotPreferConfirmStep = false;
                          });
                        },
                        child: Text(
                          'Kembali',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (sheetError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        sheetError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                      if (_isLogin) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : _openForgotPasswordSheet,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              'Lupa password?',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
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
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
          prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.70)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
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
