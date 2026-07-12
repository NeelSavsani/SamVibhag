import 'dart:io'; // REQUIRED: For processing local File handles safely

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

    final currentUserName = user.displayName ?? "Neel Savsani";

    return FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: currentUserName)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return GroupModel.fromMap(doc.data());
          }).toList();
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
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
        ),
        child: Row(
          children: [
            // FIXED: Render WhatsApp-style profile image from cloud URL or path with strict logo asset fallback
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
                  Text(group.groupName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('${group.members.length} Members • ${group.expenses.length} Expenses'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Rs. ${group.totalExpense.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: createGroup,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Create Group', style: TextStyle(color: Colors.white)),
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
                  /// SUMMARY CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(colors: [AppTheme.primary, Color(0xFF1D4ED8)]),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 10),
                        Text(
                          'Rs. ${getCalculatedTotalBalance(activeCloudGroups).toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            buildMiniStat(title: 'Groups', value: '${activeCloudGroups.length}'),
                            buildMiniStat(title: 'Expenses', value: '${getCalculatedExpensesCount(activeCloudGroups)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  /// EXPANDABLE LEFT SIDE SEARCH BAR
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _isSearchExpanded
                        ? TextField(
                            key: const ValueKey('expanded_search'),
                            controller: _searchController,
                            autofocus: true,
                            style: TextStyle(color: theme.colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Search groups...',
                              prefixIcon: const Icon(Icons.search_rounded),
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
                              filled: true,
                              fillColor: theme.cardColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() => searchQuery = value);
                            },
                          )
                        : Align(
                            key: const ValueKey('circle_search_icon'),
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () => setState(() => _isSearchExpanded = true),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: theme.cardColor,
                                child: Icon(
                                  Icons.search_rounded,
                                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 30),

                  /// TITLE
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your Groups', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('${filteredGroups.length} Total'),
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