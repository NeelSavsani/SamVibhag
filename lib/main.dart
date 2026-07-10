import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'screens/welcome_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';

import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Hive
  await Hive.initFlutter();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppThemeController())],
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

          // 1. Define the screen the app opens up to first (Splash Screen)
          initialRoute: '/',

          // 2. Map path strings to your specific Screen Widgets cleanly
          routes: {
            // FIXED: Set the initial default root to the SplashScreen to prevent route assertion crashes
            '/': (context) => const SplashScreen(),
            '/welcome': (context) => const WelcomeScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            // '/home': (context) => const HomeScreen(), 
          },

          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),

          themeMode: themeController.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,
              
          // FIXED: Removed the 'home' property because it conflicts directly with the 'initialRoute' configuration above
        );
      },
    );
  }
}