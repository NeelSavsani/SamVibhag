import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../models/group_model.dart';
import '../analytics/analytics_screen.dart';
import '../group/create_group_screen.dart';
import '../group/group_details_screen.dart';
import '../report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<GroupModel> groups = [];
  String searchQuery = '';
  
  bool _isSearchExpanded = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<GroupModel>> _getGroupsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    final currentUserName = (user.displayName ?? "Neel Savsani").trim().toLowerCase();
    final currentUserEmail = (user.email ?? "").trim().toLowerCase();

    // Stream all groups and perform client-side case-insensitive matching across members array
    return FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupModel.fromMap(doc.data()))
              .where((group) {
                // Check if user's name or email exists anywhere in members array
                return group.members.any((member) {
                  final m = member.trim().toLowerCase();
                  return m == currentUserName || (currentUserEmail.isNotEmpty && m == currentUserEmail);
                });
              })
              .toList();
        });
  }

  Future<void> createGroup() async {
    await Navigator.push<GroupModel>(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateGroupScreen(),
      ),
    );
  }

  Future<void> openGroupDetails(GroupModel group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupDetailsScreen(
          group: group,
          onGroupUpdated: () async {}, 
        ),
      ),
    );
  }

  Future<void> openAnalytics() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnalyticsScreen(groups: groups)),
    );
  }

  Future<void> openReport(GroupModel group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(group: group)),
    );
  }

  Future<void> confirmDeleteGroup(GroupModel group) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Group?'),
          content: Text('This will delete ${group.groupName} globally from Firebase.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppTheme.warning)),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('groups').doc(group.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${group.groupName} Group Permanently Deleted From Cloud')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cloud Deletion Error: $e")),
      );
    }
  }

  double getCalculatedTotalBalance(List<GroupModel> currentGroups) {
    return currentGroups.fold<double>(0, (total, group) => total + group.totalExpense);
  }

  int getCalculatedExpensesCount(List<GroupModel> currentGroups) {
    int total = 0;
    for (final group in currentGroups) {
      total += group.expenses.length;
    }
    return total;
  }

  List<GroupModel> getFilteredGroupsList(List<GroupModel> currentGroups) {
    if (searchQuery.trim().isEmpty) return currentGroups;
    return currentGroups.where((group) {
      return group.groupName.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
  }

  Widget buildMiniStat({required String title, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget buildGroupCard({required GroupModel group, required Color color}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => openGroupDetails(group),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.15),
              backgroundImage: group.avatarPath.isNotEmpty
                  ? (group.avatarPath.startsWith('http')
                      ? NetworkImage(group.avatarPath)
                      : FileImage(File(group.avatarPath)) as ImageProvider)
                  : const AssetImage('assets/images/logo.png'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.groupName,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${group.members.length} Members • ${group.expenses.length} Expenses'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${group.totalExpense.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'PDF Report',
                      onPressed: () => openReport(group),
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                    ),
                    IconButton(
                      tooltip: 'Delete Group',
                      onPressed: () => confirmDeleteGroup(group),
                      icon: const Icon(Icons.delete_outline, color: AppTheme.warning),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
          ),
        ),
        child: FloatingActionButton.extended(
          onPressed: createGroup,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Create Group', style: TextStyle(color: Colors.white)),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<GroupModel>>(
          stream: _getGroupsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
            }
            if (snapshot.hasError) {
              return Center(child: Text("Error fetching records: ${snapshot.error}"));
            }

            final activeCloudGroups = snapshot.data ?? [];
            
            groups
              ..clear()
              ..addAll(activeCloudGroups);

            final filteredGroups = getFilteredGroupsList(activeCloudGroups);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          width: 52,
                          height: 52,
                        ),
                        const SizedBox(width: 12),
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            children: const [
                              TextSpan(text: 'Sam'),
                              TextSpan(
                                text: 'Vibhag',
                                style: TextStyle(color: Color.fromARGB(255, 52, 107, 225)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  /// EXPANDABLE SEARCH BAR
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _isSearchExpanded
                        ? Container(
                            key: const ValueKey('expanded_search'),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFF83F4EB).withOpacity(0.45),
                              ),
                            ),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Search groups...',
                                hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.55)),
                                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF0284C7)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      _searchController.clear();
                                      searchQuery = '';
                                      _isSearchExpanded = false;
                                    });
                                  },
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onChanged: (value) => setState(() => searchQuery = value),
                            ),
                          )
                        : InkWell(
                            key: const ValueKey('circle_search_icon'),
                            onTap: () => setState(() => _isSearchExpanded = true),
                            borderRadius: BorderRadius.circular(18),
                            child: Ink(
                              height: 54,
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF83F4EB).withOpacity(0.28),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 16),
                                  const Icon(Icons.search_rounded, color: Color(0xFF0284C7)),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Search groups',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 28),

                  /// TITLE
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your Groups',
                        style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF83F4EB).withOpacity(isDark ? 0.16 : 0.24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${filteredGroups.length} Total',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF83F4EB) : const Color(0xFF0369A1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  filteredGroups.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('No matching cloud groups found'),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredGroups.length,
                          itemBuilder: (context, index) {
                            final group = filteredGroups[index];
                            return buildGroupCard(group: group, color: AppTheme.primary);
                          },
                        ),
                  const SizedBox(height: 100),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}