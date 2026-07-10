import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Center the AppBar Title matching specification
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
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<AppThemeController>(
          builder: (context, themeController, child) {
            // Determine our current active enum/string state for radio alignment
            // Assuming your controller handles system setting vs explicit dark toggles
            String currentSelection = 'System default';
            if (themeController.isDarkMode) {
              currentSelection = 'Night';
            } else {
              // Add fallback checking if your AppThemeController tracks system explicit preferences
              currentSelection = 'Light'; 
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Radio Option 1: Light Mode Selection
                  _ThemeRadioTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Light',
                    value: 'Light',
                    groupValue: currentSelection,
                    onChanged: (value) {
                      // Call your controller configuration updates here:
                      // themeController.setThemeMode(ThemeMode.light);
                    },
                  ),
                  
                  // Radio Option 2: Night Mode Selection
                  _ThemeRadioTile(
                    icon: Icons.nightlight_round_outlined,
                    title: 'Night',
                    value: 'Night',
                    groupValue: currentSelection,
                    onChanged: (value) {
                      // themeController.setThemeMode(ThemeMode.dark);
                    },
                  ),
                  
                  // Radio Option 3: System Default Mode Selection
                  _ThemeRadioTile(
                    icon: Icons.brightness_auto_outlined,
                    title: 'System default',
                    value: 'System default',
                    groupValue: currentSelection,
                    onChanged: (value) {
                      // themeController.setThemeMode(ThemeMode.system);
                    },
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Architectural system context description text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'App appearance adjusts to match your system settings.',
                      style: TextStyle(
                        fontSize: 13,
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
    final isSelected = value == groupValue;

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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Radio indicator layout module
              Radio<String>(
                value: value,
                groupValue: groupValue,
                onChanged: onChanged,
                activeColor: const Color(0xFF00B386), // Consistent custom green highlight color
              ),
            ],
          ),
        ),
      ),
    );
  }
}