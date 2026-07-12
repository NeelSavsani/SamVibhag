import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart'; // FIXED: Add this line to import Hive!
import 'package:provider/provider.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController()
      : _isDarkMode = Hive.box('samvibhag_storage').get(
          'isDarkMode',
          defaultValue: true,
        ) as bool;

  // New installations use dark mode until the user explicitly chooses otherwise.
  bool _isDarkMode;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    Hive.box('samvibhag_storage').put('isDarkMode', _isDarkMode);
    notifyListeners();
  }
}

class AppTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color header = Color(0xFF10455B);
  static const Color warning = Color(0xFFF59E0B);
  static const Color lightBackground = Color(0xFFFFFBF7);
  static const Color darkBackground = Color(0xFF111827);
  static const Color lightSurface = Colors.white;
  static const Color darkSurface = Color(0xFF1F2937);

  static ThemeData light() {
    final baseTheme = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: header,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
      cardColor: lightSurface,
      useMaterial3: true,
    );

    // FIXED: Injected Ubuntu globally to the textTheme and primaryTextTheme
    return baseTheme.copyWith(
      textTheme: GoogleFonts.ubuntuTextTheme(baseTheme.textTheme),
      primaryTextTheme: GoogleFonts.ubuntuTextTheme(baseTheme.primaryTextTheme),
    );
  }

  static ThemeData dark() {
    final baseTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: header,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
      cardColor: darkSurface,
      useMaterial3: true,
    );

    // FIXED: Injected Ubuntu globally to the textTheme and primaryTextTheme
    return baseTheme.copyWith(
      textTheme: GoogleFonts.ubuntuTextTheme(baseTheme.textTheme),
      primaryTextTheme: GoogleFonts.ubuntuTextTheme(baseTheme.primaryTextTheme),
    );
  }
}

class NightModeButton extends StatelessWidget {
  const NightModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppThemeController>();

    return IconButton(
      tooltip: controller.isDarkMode ? 'Light mode' : 'Night mode',
      onPressed: controller.toggleTheme,
      icon: Icon(
        controller.isDarkMode ? Icons.light_mode : Icons.dark_mode,
        color: Colors.white,
      ),
    );
  }
}
