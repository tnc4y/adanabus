import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/app_shell/app_shell_page.dart';

void main() {
  runApp(const AdanaBusApp());
}

class AdanaBusApp extends StatelessWidget {
  const AdanaBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Adana Bus Takip',
      theme: ThemeData(
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
      ),
      home: const AppShellPage(),
    );
  }
}
