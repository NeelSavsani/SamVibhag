import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'account/appearance_screen.dart';
import '../../core/theme/app_theme.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out from SamVibhag?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      
      // FIXED: Added 'rootNavigator: true' to target the application's root navigator 
      // and completely strip away the persistent bottom navigation shell layouts.
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        '/welcome', 
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Pull current Firebase User credentials dynamically
    final String displayName = user?.displayName ?? 'Neel Savsani';
    final String userEmail = user?.email ?? 'neelsavsani7@gmail.com';
    final String? photoUrl = user?.photoURL;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121214)
          : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FIRST: Section Title Profile Header
              const Text(
                'Account',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Profile Overview Card Section Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(
                      isDark ? 0.08 : 0.05,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Dynamic Profile Circle Avatar Frame Slot
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                      backgroundImage: photoUrl != null
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl == null
                          ? const Icon(
                              Icons.person_rounded,
                              color: AppTheme.primary,
                              size: 32,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),

                    // User Metadata Details Stack Block
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  // Edit Action Route Handler Slot Placeholder
                                },
                                child: const Text(
                                  'Edit',
                                  style: TextStyle(
                                    color: Color(0xFF00B074),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userEmail,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Account Action Navigation Menu Items
              _AccountTile(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AppearanceScreen(),
                    ),
                  );
                },
              ),
              _AccountTile(
                icon: Icons.security_rounded,
                title: 'Security',
                onTap: () {
                  // Connects to password resets or auth changes
                },
              ),
              _AccountTile(
                icon: Icons.contact_support_outlined,
                title: 'Contact SamVibhag Support',
                onTap: () {
                  // Support ticketing mechanism hook
                },
              ),
              _AccountTile(
                icon: Icons.star_outline_rounded,
                title: 'Rate SamVibhag',
                onTap: () {
                  // In-App review trigger action mapping
                },
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 12),

              // SIXTH: Destructive Log out Action Button Frame
              _AccountTile(
                icon: Icons.logout_rounded,
                title: 'Log out',
                isDestructive: true,
                onTap: () => _logout(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetColor = isDestructive
        ? Colors.red
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(
          icon,
          color: isDestructive
              ? Colors.red
              : theme.colorScheme.onSurface.withOpacity(0.7),
          size: 24,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isDestructive ? FontWeight.bold : FontWeight.w600,
            color: targetColor,
          ),
        ),
        trailing: isDestructive
            ? null
            : Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
      ),
    );
  }
}