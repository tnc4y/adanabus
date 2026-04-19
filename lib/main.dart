import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/app_shell/app_shell_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdanaBusApp());
}

class AdanaBusApp extends StatefulWidget {
  const AdanaBusApp({super.key});

  @override
  State<AdanaBusApp> createState() => _AdanaBusAppState();
}

class _AdanaBusAppState extends State<AdanaBusApp> {
  static const _themePrefKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_themePrefKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = mode == 'dark' ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleThemeMode() async {
    final next = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() {
      _themeMode = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKey, next == ThemeMode.dark ? 'dark' : 'light');
  }

  ThemeData _buildLightTheme(TextTheme textTheme) {
    return ThemeData(
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF164B9D),
        secondary: Color(0xFFB63519),
        surface: Color(0xFFFFFEFA),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      textTheme: textTheme,
      useMaterial3: true,
    );
  }

  ThemeData _buildDarkTheme(TextTheme textTheme) {
    return ThemeData(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF8BB4FF),
        secondary: Color(0xFFFF8A70),
        surface: Color(0xFF10151E),
        onPrimary: Color(0xFF0A1D3F),
        onSecondary: Color(0xFF3F120B),
      ),
      scaffoldBackgroundColor: const Color(0xFF0C1118),
      cardColor: const Color(0xFF121A24),
      textTheme: textTheme.apply(
        bodyColor: const Color(0xFFE6ECF5),
        displayColor: const Color(0xFFE6ECF5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1722),
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Adana Bus Takip',
      theme: _buildLightTheme(textTheme),
      darkTheme: _buildDarkTheme(textTheme),
      themeMode: _themeMode,
      home: AppShellPage(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleThemeMode,
      ),
    );
  }
}
