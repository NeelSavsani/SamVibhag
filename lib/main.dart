import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const SamVibhagApp());
}

class SamVibhagApp extends StatelessWidget {
  const SamVibhagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SamVibhag',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: const SplashScreen(),
    );
  }
}