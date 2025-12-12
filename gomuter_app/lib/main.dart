import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'navigation/admin_routes.dart';
import 'navigation/pkl_routes.dart';
import 'pages/admin/admin_home_page.dart';
import 'pages/pkl/pkl_chat_list_page.dart';
import 'pages/pkl/pkl_edit_info_page.dart';
import 'pages/pkl/pkl_home_page.dart';
import 'pages/pkl/pkl_payment_settings_page.dart';
import 'pages/pkl/pkl_preorder_page.dart';
import 'web/file_picker_web_registrar.dart';
import 'pages/auth/auth_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ensureFilePickerWebRegistered();
  await initializeDateFormatting('id');
  runApp(const GoMuterApp());
}

class GoMuterApp extends StatelessWidget {
  const GoMuterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoMuter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D8A3A),
          primary: const Color(0xFF0D8A3A),
          secondary: const Color(0xFF25D366),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
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
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D8A3A),
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0D8A3A),
            side: const BorderSide(color: Color(0xFF0D8A3A), width: 1.8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0D8A3A),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F9FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF0D8A3A), width: 2),
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
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.black87,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const AuthPage(),
      routes: {
        PklRoutes.home: (_) => const PklHomePage(),
        PklRoutes.profile: (_) => const PklEditInfoPage(),
        PklRoutes.payment: (_) => const PklPaymentSettingsPage(),
        PklRoutes.preorder: (_) => const PklPreOrderPage(),
        PklRoutes.chat: (_) => const PklChatListPage(),
      },
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
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
