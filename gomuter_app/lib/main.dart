import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'navigation/admin_routes.dart';
import 'navigation/pkl_routes.dart';
import 'pages/admin/admin_home_page.dart';
import 'pages/pkl/pkl_chat_list_page.dart';
import 'pages/pkl/pkl_edit_info_page.dart';
import 'pages/pkl/pkl_home_page.dart';
import 'pages/pkl/pkl_location_page.dart';
import 'pages/pkl/pkl_payment_settings_page.dart';
import 'pages/pkl/pkl_preorder_page.dart';
import 'pages/pkl/pkl_profile_page.dart';
import 'web/file_picker_web_registrar.dart';
import 'pages/auth/auth_page.dart';
import 'utils/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ensureFilePickerWebRegistered();
  await initializeDateFormatting('id');
  runApp(const GoMuterApp());
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
        home: const AuthPage(),
        routes: const {},
        onGenerateRoute: _onGenerateRoute,
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

// Halaman-halaman khusus peran ada di folder lib/pages
