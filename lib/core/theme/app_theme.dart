import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppThemeController extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
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
    return ThemeData(
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
  }

  static ThemeData dark() {
    return ThemeData(
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
