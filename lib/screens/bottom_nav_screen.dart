import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'home/home_screen.dart';
import 'activity_screen.dart';
import 'account_screen.dart';
import '../models/group_model.dart'; // Ensure correct import mapping

class BottomNavScreen extends StatefulWidget {
  const BottomNavScreen({super.key});

  @override
  State<BottomNavScreen> createState() => _BottomNavScreenState();
}

class _BottomNavScreenState extends State<BottomNavScreen> {
  int _selectedIndex = 0;
  final List<GroupModel> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroupsData();
  }

  // Pull local storage data locally to distribute efficiently down into our tabs
  void _loadGroupsData() {
    try {
      final box = Hive.box('samvibhag_storage');
      final savedGroups = List<dynamic>.from(box.get('groups', defaultValue: []));
      setState(() {
        _groups.clear();
        _groups.addAll(savedGroups.map((g) => GroupModel.fromMap(g as Map)));
      });
    } catch (e) {
      debugPrint("Error updating bottom nav metrics: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically rebuilds pages tracking data lists
    final List<Widget> pages = [
      const HomeScreen(),
      ActivityScreen(groups: _groups), // FIXED: Inject data to drive Analytics card
      const AccountScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 1) _loadGroupsData(); // Auto-refresh data when tapping activity
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