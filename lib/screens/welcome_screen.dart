import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'auth/register_screen.dart';

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

  void _showComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$title will be connected soon.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFF07111F),
                    Color(0xFF0F172A),
                    Color(0xFF172554),
                  ]
                : const [
                    Color(0xFFEFF6FF),
                    Color(0xFFFFFBF7),
                    Color(0xFFDBEAFE),
                  ],
          ),
        ),
        child: SafeArea(
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

                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(34),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            height: 132,
                            width: 132,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: isDark ? .10 : .88,
                              ),
                              borderRadius: BorderRadius.circular(34),
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: isDark ? .12 : .90,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(
                                    alpha: .22,
                                  ),
                                  blurRadius: 34,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Image.asset("assets/images/logo.png"),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  Text(
                    "SamVibhag",

                    textAlign: TextAlign.center,

                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.8,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "Split expenses without splitting friendships.",

                    textAlign: TextAlign.center,

                    style: theme.textTheme.titleMedium?.copyWith(
                      height: 1.45,
                      color: theme.colorScheme.onSurface.withValues(alpha: .72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    "Track group bills, custom splits and settlements in one calm, simple place.",

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onSurface.withValues(alpha: .62),
                      height: 1.55,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _FeaturePill(
                        icon: Icons.receipt_long_rounded,
                        label: "Track bills",
                      ),
                      _FeaturePill(
                        icon: Icons.groups_2_rounded,
                        label: "Share groups",
                      ),
                      _FeaturePill(
                        icon: Icons.balance_rounded,
                        label: "Settle smart",
                      ),
                    ],
                  ),

                  SizedBox(height: size.height * .06),
                  SizedBox(
                    width: double.infinity,
                    height: 58,

                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },

                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),

                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Create Account",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 58,

                    child: OutlinedButton(
                      onPressed: () => _showComingSoon("Login"),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: .45),
                          width: 1.4,
                        ),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),

                      child: const Text(
                        "Log In",

                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
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
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .55,
                            ),
                            fontWeight: FontWeight.w700,
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
                      onPressed: () => _showComingSoon("Google sign in"),

                      icon: Image.asset(
                        "assets/images/google.png",

                        height: 24,
                        width: 24,
                      ),

                      label: const Text(
                        "Continue with Google",

                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        side: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: .18,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  TextButton(
                    onPressed: () => _showComingSoon("Privacy policy"),
                    child: Text(
                      "Privacy Policy • Terms of Service",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .62,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Version 1.0.0",

                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: .52),
                    ),
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: .12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: AppTheme.primary),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
