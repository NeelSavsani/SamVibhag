import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'activity_screen.dart';
import 'account_screen.dart';

class BottomNavScreen extends StatefulWidget {
  const BottomNavScreen({super.key});

  @override
  State<BottomNavScreen> createState() => _BottomNavScreenState();
}

class _BottomNavScreenState extends State<BottomNavScreen> {
  int _selectedIndex = 0;

  // Private keys to maintain distinct state historical back-stacks for each tab module
  final GlobalKey<NavigatorState> _groupsTabKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _activityTabKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _accountTabKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Tab 1: Groups (With nested navigation shell)
          Navigator(
            key: _groupsTabKey,
            onGenerateRoute: (routeSettings) {
              return MaterialPageRoute(
                builder: (context) => const HomeScreen(),
              );
            },
          ),
          
          // Tab 2: Activity (With nested navigation shell)
          Navigator(
            key: _activityTabKey,
            onGenerateRoute: (routeSettings) {
              return MaterialPageRoute(
                builder: (context) => const ActivityScreen(),
              );
            },
          ),

          // Tab 3: Account (With nested navigation shell)
          Navigator(
            key: _accountTabKey,
            onGenerateRoute: (routeSettings) {
              return MaterialPageRoute(
                builder: (context) => const AccountScreen(),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) {
            // Optional: Pop back to root list view if active tab icon is tapped again
            if (index == 0) _groupsTabKey.currentState?.popUntil((r) => r.isFirst);
            if (index == 1) _activityTabKey.currentState?.popUntil((r) => r.isFirst);
            if (index == 2) _accountTabKey.currentState?.popUntil((r) => r.isFirst);
          } else {
            setState(() {
              _selectedIndex = index;
            });
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF00B386),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 13,
        unselectedFontSize: 13,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: "Groups",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: "Activity",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Account",
          ),
        ],
      ),
    );
  }
}