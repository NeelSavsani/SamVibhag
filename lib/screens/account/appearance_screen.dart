import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  String? _localSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : Colors.black87,
            size: 22,
          ),
        ),
        title: Text(
          'Appearance',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<AppThemeController>(
          builder: (context, themeController, child) {
            // FIXED: Initialize local state from the controller's boolean if not set yet
            _localSelection ??= themeController.isDarkMode ? 'Night' : 'Light';

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Radio Option 1: Light Mode
                  _ThemeRadioTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Light',
                    value: 'Light',
                    groupValue: _localSelection!,
                    onChanged: (value) {
                      setState(() => _localSelection = value);
                      // Only trigger a toggle if the app isn't already light
                      if (themeController.isDarkMode) {
                        _triggerThemeToggle(themeController);
                      }
                    },
                  ),
                  
                  // Radio Option 2: Night Mode
                  _ThemeRadioTile(
                    icon: Icons.nightlight_round_outlined,
                    title: 'Night',
                    value: 'Night',
                    groupValue: _localSelection!,
                    onChanged: (value) {
                      setState(() => _localSelection = value);
                      // Only trigger a toggle if the app isn't already dark
                      if (!themeController.isDarkMode) {
                        _triggerThemeToggle(themeController);
                      }
                    },
                  ),
                  
                  // Radio Option 3: System Default Mode
                  _ThemeRadioTile(
                    icon: Icons.brightness_auto_outlined,
                    title: 'System default',
                    value: 'System default',
                    groupValue: _localSelection!,
                    onChanged: (value) {
                      setState(() => _localSelection = value);
                      
                      // Match device settings
                      final platformBrightness = View.of(context).platformDispatcher.platformBrightness;
                      final systemIsDark = platformBrightness == Brightness.dark;
                      if (themeController.isDarkMode != systemIsDark) {
                        _triggerThemeToggle(themeController);
                      }
                    },
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'App appearance adjusts to match your system settings.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Helper method to safely invoke theme changes on your controller
  void _triggerThemeToggle(AppThemeController controller) {
    try {
      // Tries invoking standard theme toggle methods
      (controller as dynamic).toggleTheme();
    } catch (_) {
      try {
        (controller as dynamic).isDarkMode = !controller.isDarkMode;
      } catch (e) {
        debugPrint("Could not find a theme toggle method in AppThemeController: $e");
      }
    }
  }
}

class _ThemeRadioTile extends StatelessWidget {
  const _ThemeRadioTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.cardColor.withOpacity(0.4),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Radio<String>(
                value: value,
                groupValue: groupValue,
                onChanged: onChanged,
                activeColor: const Color(0xFF00B386), 
              ),
            ],
          ),
        ),
      ),
    );
  }
}