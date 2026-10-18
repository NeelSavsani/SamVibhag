import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'screens/account/appearance_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/bottom_nav_screen.dart';

import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SamVibhagBootstrap());
}

class SamVibhagBootstrap extends StatefulWidget {
  const SamVibhagBootstrap({super.key});

  @override
  State<SamVibhagBootstrap> createState() => _SamVibhagBootstrapState();
}

class _SamVibhagBootstrapState extends State<SamVibhagBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    await Hive.initFlutter();
    await Hive.openBox('samvibhag_storage');

    // Start background account maintenance only after the first UI can render.
    AuthService().initializeAuthListener();
  }

  void _retry() {
    setState(() => _initialization = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupMessage(
            message: 'App startup failed:\n${snapshot.error}',
            onRetry: _retry,
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupMessage();
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppThemeController()),
          ],
          child: const SamVibhagApp(),
        );
      },
    );
  }
}

class _StartupMessage extends StatelessWidget {
  const _StartupMessage({this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                Text(
                  message ?? 'Starting SamVibhag…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
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

        );
      },
    );
  }
}
