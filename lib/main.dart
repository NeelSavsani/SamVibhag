import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // REQUIRED: Imports SystemNavigator for clean app minimization
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'screens/account/appearance_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart'; 
import 'screens/bottom_nav_screen.dart'; 

import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Hive
  await Hive.initFlutter();

  // Explicitly opening 'samvibhag_storage' box before the UI attempts to read it
  await Hive.openBox('samvibhag_storage');

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppThemeController())],
      child: const SamVibhagApp(),
    ),
  );
}

// FIXED: Created a Global Key to track the navigation history stack across named routes
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

class SamVibhagApp extends StatelessWidget {
  const SamVibhagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppThemeController>(
      builder: (context, themeController, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SamVibhag',
          
          // FIXED: Registered the tracking key to map screen history natively
          navigatorKey: globalNavigatorKey,

          // Define the screen the app opens up to first (Splash Screen)
          initialRoute: '/',

          // Map path strings to your specific Screen Widgets cleanly
          routes: {
            '/': (context) => const SplashScreen(),
            '/welcome': (context) => const WelcomeScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/appearance': (context) => const AppearanceScreen(),
            '/home': (context) => const BottomNavScreen(), 
          },

          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,

          // FIXED: Injected a global PopScope wrapper around the entire router canvas 
          // to intercept hardware keys and edge-swipes on ALL screens automatically.
          builder: (context, navigationWidget) {
            return PopScope(
              canPop: false, // Tells the phone os that the app will handle the history tracking manually
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;

                final NavigatorState? navigator = globalNavigatorKey.currentState;

                if (navigator != null && navigator.canPop()) {
                  // If there is any screen in the history path, step backward one page
                  navigator.pop();
                } else {
                  // If we are at the root homepage view, cleanly minimize or close the app
                  await SystemNavigator.pop();
                }
              },
              child: navigationWidget ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}