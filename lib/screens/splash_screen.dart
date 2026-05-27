import 'dart:async';

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

    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        ),
      );
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

            Image.asset(
              'assets/images/logo.png',
              width: 180,
            ),

            const SizedBox(height: 25),

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

            const Text(
              "समविभाग",
              style: TextStyle(
                fontSize: 22,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              "Fair Expense Sharing",
              style: TextStyle(
                fontSize: 16,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}






class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),

      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        title: const Text(
          "SamVibhag",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
      ),

      body: const Center(
        child: Text(
          "Welcome to SamVibhag",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}