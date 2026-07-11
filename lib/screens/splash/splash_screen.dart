import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Wait a brief moment for the splash branding before analyzing authentication state
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      // FIXED: Read active login session status directly from Google Firebase
      final currentFirebaseUser = FirebaseAuth.instance.currentUser;

      if (currentFirebaseUser != null) {
        // Logged In -> Forward straight to the bottom navigation shell
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // No Session -> Direct user to introductory Welcome Screen
        Navigator.pushReplacementNamed(context, '/welcome');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// LOGO
            Image.asset('assets/images/logo.png', width: 180),
            const SizedBox(height: 25),

            /// APP NAME
            const Text(
              "SamVibhag",
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),

            /// SANSKRIT NAME
            const Text(
              "समविभाग",
              style: TextStyle(
                fontSize: 22,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),

            /// TAGLINE
            const Text(
              "Fair Expense Sharing",
              style: TextStyle(fontSize: 16, color: Colors.white54),
            ),
            const SizedBox(height: 40),

            /// LOADING INDICATOR
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}