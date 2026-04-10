import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'navigation/admin_routes.dart';
import 'navigation/pkl_routes.dart';
import 'pages/admin/admin_home_page.dart';
import 'pages/pembeli/pembeli_home_page.dart';
import 'pages/pkl/pkl_chat_list_page.dart';
import 'pages/pkl/pkl_edit_info_page.dart';
import 'pages/pkl/pkl_home_page.dart';
import 'pages/pkl/pkl_location_page.dart';
import 'pages/pkl/pkl_payment_settings_page.dart';
import 'pages/pkl/pkl_preorder_page.dart';
import 'pages/pkl/pkl_profile_page.dart';
import 'web/file_picker_web_registrar.dart';
import 'pages/auth/auth_page.dart';
import 'pages/splash/splash_screen.dart';
import 'pages/onboarding/onboarding_screen.dart';
import 'pages/onboarding/permission_screen.dart';
import 'utils/token_manager.dart';
import 'utils/theme_manager.dart';
import 'utils/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await _initializeFirebase();

  ensureFilePickerWebRegistered();
  await initializeDateFormatting('id');
  runApp(const GoMuterApp());

  // Initialize notifications AFTER app UI is shown (non-blocking)
  if (Firebase.apps.isNotEmpty) {
    try {
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('Warning: Failed to initialize NotificationService: $e');
    }
  } else {
    debugPrint(
      'Warning: Skipping NotificationService initialization because Firebase is not initialized.',
    );
  }
}

Future<void> _initializeFirebase() async {
  try {
    if (kIsWeb) {
      const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
      const appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
      const messagingSenderId = String.fromEnvironment(
        'FIREBASE_WEB_MESSAGING_SENDER_ID',
      );
      const projectId = String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');
      const authDomain = String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');
      const storageBucket = String.fromEnvironment(
        'FIREBASE_WEB_STORAGE_BUCKET',
      );
      const measurementId = String.fromEnvironment(
        'FIREBASE_WEB_MEASUREMENT_ID',
      );

      final hasRequiredWebOptions =
          apiKey.isNotEmpty &&
          appId.isNotEmpty &&
          messagingSenderId.isNotEmpty &&
          projectId.isNotEmpty;

      if (!hasRequiredWebOptions) {
        debugPrint(
          'Warning: Firebase Web config is missing. Pass --dart-define FIREBASE_WEB_API_KEY, FIREBASE_WEB_APP_ID, FIREBASE_WEB_MESSAGING_SENDER_ID, and FIREBASE_WEB_PROJECT_ID.',
        );
        return;
      }

      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          authDomain: authDomain.isEmpty ? null : authDomain,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
          measurementId: measurementId.isEmpty ? null : measurementId,
        ),
      );
      return;
    }

    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Warning: Failed to initialize Firebase: $e');
  }
}

class GoMuterApp extends StatelessWidget {
  const GoMuterApp({super.key});

  ThemeData _buildTheme(ThemeManager themeManager) {
    final isDark = themeManager.isDarkMode;
    final primary = themeManager.primaryGreen;
    final secondary = themeManager.accentGold;

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primary,
      secondary: secondary,
      surface: themeManager.cardColor,
    );

    return ThemeData(
      colorScheme: scheme,
      brightness: isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: themeManager.backgroundColor,
      cardColor: themeManager.cardColor,
      dividerColor: themeManager.borderColor,
      textTheme:
          const TextTheme(
            displayLarge: TextStyle(fontWeight: FontWeight.w800),
            displayMedium: TextStyle(fontWeight: FontWeight.w800),
            displaySmall: TextStyle(fontWeight: FontWeight.w700),
            headlineLarge: TextStyle(fontWeight: FontWeight.w700),
            headlineMedium: TextStyle(fontWeight: FontWeight.w700),
            headlineSmall: TextStyle(fontWeight: FontWeight.w700),
            titleLarge: TextStyle(fontWeight: FontWeight.w700),
            titleMedium: TextStyle(fontWeight: FontWeight.w600),
            titleSmall: TextStyle(fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontWeight: FontWeight.w500),
            bodyMedium: TextStyle(fontWeight: FontWeight.w500),
            bodySmall: TextStyle(fontWeight: FontWeight.w500),
          ).apply(
            bodyColor: themeManager.textColor,
            displayColor: themeManager.textColor,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.8),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? themeManager.surfaceColor : const Color(0xFFF8F9FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: themeManager.borderColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: themeManager.borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: themeManager.textColor,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: themeManager.textColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return AnimatedBuilder(
      animation: themeManager,
      builder: (context, _) => MaterialApp(
        title: 'GoMuter',
        theme: _buildTheme(themeManager),
        home: const _SessionGate(),
        routes: const {},
        onGenerateRoute: _onGenerateRoute,
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    PageRouteBuilder<T> noTransitionRoute<T>(WidgetBuilder builder) {
      return PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      );
    }

    switch (settings.name) {
      case PklRoutes.home:
        return noTransitionRoute((_) => const PklHomePage());
      case PklRoutes.orders:
        return noTransitionRoute((_) => const PklPreOrderPage());
      case PklRoutes.chat:
        return noTransitionRoute((_) => const PklChatListPage());
      case PklRoutes.profile:
        return noTransitionRoute((_) => const PklProfilePage());
      case PklRoutes.manage:
        return noTransitionRoute((_) => const PklEditInfoPage());
      case PklRoutes.payment:
        return noTransitionRoute((_) => const PklPaymentSettingsPage());
      case PklRoutes.location:
        return MaterialPageRoute(
          builder: (_) => const PklLocationPage(),
          settings: settings,
        );
      case AdminRoutes.dashboard:
      case AdminRoutes.dataPKL:
      case AdminRoutes.reports:
        final token = settings.arguments as String?;
        if (token == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Akses admin membutuhkan token.')),
            ),
            settings: settings,
          );
        }
        final tabIndex = settings.name == AdminRoutes.dashboard
            ? 0
            : settings.name == AdminRoutes.dataPKL
            ? 1
            : 2;
        return MaterialPageRoute(
          builder: (_) =>
              AdminHomePage(accessToken: token, initialTabIndex: tabIndex),
          settings: settings,
        );
    }
    return null;
  }
}

/// Entry gate: Splash → Onboarding (first-time) → Session check.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

enum _GatePhase { splash, onboarding, permissions, sessionCheck }

class _SessionGateState extends State<_SessionGate> {
  _GatePhase _phase = _GatePhase.splash;

  static const _onboardingDoneKey = 'onboarding_done';

  void _onSplashFinished() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool(_onboardingDoneKey) ?? false;

    if (!mounted) return;

    if (onboardingDone) {
      // Returning user — skip onboarding & permissions, go straight to session
      setState(() => _phase = _GatePhase.sessionCheck);
      _checkSession();
    } else {
      setState(() => _phase = _GatePhase.onboarding);
    }
  }

  void _onOnboardingFinished() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, true);

    if (!mounted) return;
    // After onboarding, ask for permissions
    setState(() => _phase = _GatePhase.permissions);
  }

  void _onPermissionsFinished() {
    if (!mounted) return;
    setState(() => _phase = _GatePhase.sessionCheck);
    _checkSession();
  }

  Future<void> _checkSession() async {
    final token = await TokenManager.getValidAccessToken();

    if (token == null) {
      _goToAuth();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('user_role') ?? '').toUpperCase();

    if (!mounted) return;

    if (role == 'PKL') {
      Navigator.pushReplacementNamed(context, PklRoutes.home);
    } else if (role == 'ADMIN') {
      Navigator.pushReplacementNamed(
        context,
        AdminRoutes.dashboard,
        arguments: token,
      );
    } else if (role == 'USER' && role.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PembeliHomePage()),
      );
    } else {
      _goToAuth();
    }
  }

  void _goToAuth() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.splash:
        return SplashScreen(onFinished: _onSplashFinished);
      case _GatePhase.onboarding:
        return OnboardingScreen(onFinished: _onOnboardingFinished);
      case _GatePhase.permissions:
        return PermissionScreen(onFinished: _onPermissionsFinished);
      case _GatePhase.sessionCheck:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
    }
  }
}

// Halaman-halaman khusus peran ada di folder lib/pages
