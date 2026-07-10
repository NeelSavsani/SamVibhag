import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late Animation<double> _logoAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,

          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),

            child: Column(
              children: [
                const Spacer(),

                ScaleTransition(
                  scale: _logoAnimation,

                  child: Hero(
                    tag: "app_logo",

                    child: Container(
                      height: 130,
                      width: 130,

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(32),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.15),

                            blurRadius: 20,

                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),

                      padding: const EdgeInsets.all(18),

                      child: Image.asset("assets/images/logo.png"),
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                Text(
                  "SamVibhag",

                  textAlign: TextAlign.center,

                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,

                    color: AppTheme.primary,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  "Smart Expense Splitter",

                  textAlign: TextAlign.center,

                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 22),

                Text(
                  "Split bills effortlessly with friends, family and colleagues.\nTrack every expense and settle up with ease.",

                  textAlign: TextAlign.center,

                  style: TextStyle(
                    fontSize: 16,

                    color: Colors.grey.shade600,

                    height: 1.6,
                  ),
                ),

                SizedBox(height: size.height * .08),
                SizedBox(
                  width: double.infinity,
                  height: 58,

                  child: ElevatedButton(
                    onPressed: () {
                      // TODO:
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(
                      //     builder: (_) =>
                      //         const RegisterScreen(),
                      //   ),
                      // );
                    },

                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),

                    child: const Text(
                      "Create Account",

                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 58,

                  child: OutlinedButton(
                    onPressed: () {
                      // TODO:
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(
                      //     builder: (_) =>
                      //         const LoginScreen(),
                      //   ),
                      // );
                    },

                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primary, width: 2),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),

                    child: const Text(
                      "Log In",

                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    const Expanded(child: Divider()),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),

                      child: Text(
                        "OR",

                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 58,

                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO:
                      // Google Sign In
                    },

                    icon: Image.asset(
                      "assets/images/google.png",

                      height: 24,
                      width: 24,
                    ),

                    label: const Text(
                      "Continue with Google",

                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                TextButton(
                  onPressed: () {},

                  child: const Text("Privacy Policy • Terms of Service"),
                ),

                const SizedBox(height: 8),

                Text(
                  "Version 1.0.0",

                  style: TextStyle(color: Colors.grey.shade600),
                ),

                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
