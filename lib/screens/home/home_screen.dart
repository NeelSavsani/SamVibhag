import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:samvibhag/widgets/admob_banner.dart';

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
    if (user == null) return Stream.value(<GroupModel>[]);

    return FirebaseFirestore.instance
        .collection('groups')
        .where(
          Filter.or(
            Filter('memberUids', arrayContains: user.uid),
            Filter('createdBy', isEqualTo: user.uid),
          ),
        )
        .snapshots()
        .map((snapshot) {
          final uniqueGroups = <String, GroupModel>{};
          for (var doc in snapshot.docs) {
            uniqueGroups[doc.id] = GroupModel.fromMap(doc.data());
          }
          return uniqueGroups.values.toList();
        });
  }

  Future<void> createGroup() async {
    await Navigator.of(context, rootNavigator: true).push<GroupModel>(
      MaterialPageRoute(
        builder: (context) => const CreateGroupScreen(),
      ),
    );
  }

  Future<void> openGroupDetails(GroupModel group) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => GroupDetailsScreen(
          group: group,
          onGroupUpdated: () async {}, 
        ),
      ),
    );
  }

  Future<void> openAnalytics() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => AnalyticsScreen(groups: groups)),
    );
  }

  Future<void> openReport(GroupModel group) async {
    await Navigator.of(context, rootNavigator: true).push(
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
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${group.members.length} Members'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${group.totalExpense.toStringAsFixed(0)}',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
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
      floatingActionButton: SizedBox(
        height: 48,
        child: Container(
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
            extendedPadding: const EdgeInsets.symmetric(horizontal: 10),
            extendedIconLabelSpacing: 6,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text(
              'Create Group',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
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

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SizedBox(
                    height: 56,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            axis: Axis.horizontal,
                            axisAlignment: 1,
                            sizeFactor: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _isSearchExpanded
                          ? Container(
                              key: const ValueKey('expanded-header-search'),
                              width: double.infinity,
                              height: 48,
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF83F4EB)
                                      .withOpacity(0.45),
                                ),
                              ),
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search groups',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.55),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    color: Color(0xFF0284C7),
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: 'Close search',
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
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                onChanged: (value) =>
                                    setState(() => searchQuery = value),
                              ),
                            )
                          : Row(
                              key: const ValueKey('collapsed-header'),
                              children: [
                                Image.asset(
                                  'assets/images/logo.png',
                                  width: 48,
                                  height: 48,
                                ),
                                const Spacer(),
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF83F4EB)
                                          .withOpacity(0.28),
                                    ),
                                  ),
                                  child: IconButton(
                                    tooltip: 'Search groups',
                                    onPressed: () => setState(
                                      () => _isSearchExpanded = true,
                                    ),
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      color: Color(0xFF0284C7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                    children: [
                      /// TITLE
                      Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your Groups',
                        style: GoogleFonts.dmSans(fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF83F4EB).withOpacity(isDark ? 0.16 : 0.24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${filteredGroups.length} Total',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF83F4EB) : const Color(0xFF0369A1),
                          ),
                        ),
                      ),
                    ],
                  ),
                      const SizedBox(height: 20),

                      if (filteredGroups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text('No matching cloud groups found')),
                        )
                      else
                        ...filteredGroups.map(
                          (group) => buildGroupCard(
                            group: group,
                            color: AppTheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
