import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// A friendly screen that asks the user for Location & Notification
/// permissions the very first time they open the app.
class PermissionScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const PermissionScreen({super.key, required this.onFinished});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _requesting = false;

  static const _orange = Color(0xFFF97316);

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    if (kIsWeb) {
      // On web, permission_handler is not available – skip.
      widget.onFinished();
      return;
    }

    final locStatus = await Permission.locationWhenInUse.status;
    final notifStatus = await Permission.notification.status;

    if (!mounted) return;
    setState(() {
      _locationGranted = locStatus.isGranted;
      _notificationGranted = notifStatus.isGranted;
    });

    // If both are already granted, skip this screen entirely.
    if (_locationGranted && _notificationGranted) {
      widget.onFinished();
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _requesting = true);

    // Request location
    if (!_locationGranted) {
      final status = await Permission.locationWhenInUse.request();
      if (mounted) {
        setState(() => _locationGranted = status.isGranted);
      }
    }

    // Request notification (Android 13+)
    if (!_notificationGranted) {
      if (!kIsWeb && Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (mounted) {
          setState(() => _notificationGranted = status.isGranted);
        }
      } else {
        // iOS handles notification permission via Firebase; mark as done.
        if (mounted) setState(() => _notificationGranted = true);
      }
    }

    if (mounted) {
      setState(() => _requesting = false);
    }

    // Small delay so user can see the checkmarks
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _orange.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 60,
                  color: _orange,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'Izinkan Akses',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Agar GoMuter berjalan dengan baik, kami membutuhkan '
                'beberapa izin berikut:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // Permission items
              _PermissionItem(
                icon: Icons.location_on_rounded,
                title: 'Lokasi',
                description: 'Menemukan PKL terdekat di sekitarmu',
                granted: _locationGranted,
              ),
              const SizedBox(height: 16),
              _PermissionItem(
                icon: Icons.notifications_rounded,
                title: 'Notifikasi',
                description: 'Menerima info pesanan & promo terbaru',
                granted: _notificationGranted,
              ),

              const Spacer(flex: 3),

              // Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _requesting ? null : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _orange.withAlpha(128),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _requesting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Izinkan & Lanjutkan'),
                ),
              ),
              const SizedBox(height: 12),

              // Skip
              TextButton(
                onPressed: _requesting ? null : widget.onFinished,
                child: Text(
                  'Nanti saja',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF97316);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: granted
            ? const Color(0xFFF0FDF4) // green tint
            : const Color(0xFFFFF7ED), // orange tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted
              ? const Color(0xFF86EFAC)
              : orange.withAlpha(51),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: granted ? const Color(0xFF22C55E) : orange, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (granted)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 24),
        ],
      ),
    );
  }
}
