import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Hive
  await Hive.initFlutter();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppThemeController(),
        ),
      ],
      child: const SamVibhagApp(),
    ),
  );
}

class SamVibhagApp extends StatelessWidget {
  const SamVibhagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppThemeController>(
      builder: (context, themeController, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SamVibhag',

          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),

          themeMode: themeController.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,

          home: const SplashScreen(),
        );
      },
    );
  }
}