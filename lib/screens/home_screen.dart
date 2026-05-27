import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/group_model.dart';
import '../theme/app_theme.dart';

import 'analytics_screen.dart';
import 'create_group_screen.dart';
import 'group_details_screen.dart';
import '../services/report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState
    extends State<HomeScreen> {

  static const String storageBoxName =
      'samvibhag_storage';

  static const String groupsKey =
      'groups';

  final List<GroupModel> groups = [];

  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadGroups();
  }

  void loadGroups() {

    final box =
        Hive.box(storageBoxName);

    final savedGroups =
        List<dynamic>.from(
      box.get(
        groupsKey,
        defaultValue: [],
      ),
    );

    groups
      ..clear()
      ..addAll(
        savedGroups.map(
          (groupMap) =>
              GroupModel.fromMap(
            groupMap as Map,
          ),
        ),
      );
  }

  Future<void> saveGroups() async {

    final box =
        Hive.box(storageBoxName);

    await box.put(
      groupsKey,
      groups
          .map(
            (group) =>
                group.toMap(),
          )
          .toList(),
    );
  }

  Future<void> createGroup() async {

    final result =
        await Navigator.push<GroupModel>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const CreateGroupScreen(),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      groups.add(result);
    });

    await saveGroups();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '${result.groupName} Group Created Successfully',
        ),
      ),
    );
  }

  Future<void> openGroupDetails(
    GroupModel group,
  ) async {

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            GroupDetailsScreen(
          group: group,
          onGroupUpdated:
              saveGroups,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {});
    await saveGroups();
  }

  Future<void> openAnalytics() async {

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AnalyticsScreen(
          groups: groups,
        ),
      ),
    );
  }

  Future<void> openReport(
    GroupModel group,
  ) async {

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReportScreen(
          group: group,
        ),
      ),
    );
  }

  Future<void> confirmDeleteGroup(
    GroupModel group,
  ) async {

    final shouldDelete =
        await showDialog<bool>(
      context: context,

      builder: (context) {

        return AlertDialog(
          title:
              const Text('Delete Group?'),

          content: Text(
            'This will delete ${group.groupName} and all its expenses.',
          ),

          actions: [

            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),

              child:
                  const Text('Cancel'),
            ),

            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),

              child: const Text(
                'Delete',

                style: TextStyle(
                  color:
                      AppTheme.warning,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true ||
        !mounted) {
      return;
    }

    setState(() {
      groups.remove(group);
    });

    await saveGroups();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '${group.groupName} Group Deleted',
        ),
      ),
    );
  }

  double get totalBalance {

    return groups.fold<double>(
      0,
      (total, group) =>
          total + group.totalExpense,
    );
  }

  int get totalExpensesCount {

    int total = 0;

    for (final group in groups) {
      total += group.expenses.length;
    }

    return total;
  }

  List<GroupModel> get filteredGroups {

    if (searchQuery.trim().isEmpty) {
      return groups;
    }

    return groups.where((group) {

      return group.groupName
          .toLowerCase()
          .contains(
            searchQuery.toLowerCase(),
          );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor:
          Theme.of(context)
              .scaffoldBackgroundColor,

      appBar: AppBar(
        title: const Text(
          'SamVibhag',

          style: TextStyle(
            color: Colors.white,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [

          IconButton(
            tooltip: 'Analytics',

            icon: const Icon(
              Icons.bar_chart,
              color: Colors.white,
            ),

            onPressed:
                openAnalytics,
          ),

          const NightModeButton(),
        ],
      ),

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: createGroup,

        icon: const Icon(
          Icons.add,
          color: Colors.white,
        ),

        label: const Text(
          'Create Group',

          style: TextStyle(
            color: Colors.white,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            /// SUMMARY CARD
            Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.all(
                22,
              ),

              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(
                  24,
                ),

                gradient:
                    const LinearGradient(
                  colors: [
                    AppTheme.primary,
                    Color(0xFF1D4ED8),
                  ],
                ),
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,

                children: [

                  const Text(
                    'Total Balance',

                    style: TextStyle(
                      color:
                          Colors.white70,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(
                    height: 10,
                  ),

                  Text(
                    'Rs. ${totalBalance.toStringAsFixed(0)}',

                    style:
                        const TextStyle(
                      color:
                          Colors.white,

                      fontSize: 38,

                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .spaceBetween,

                    children: [

                      buildMiniStat(
                        title:
                            'Groups',
                        value:
                            '${groups.length}',
                      ),

                      buildMiniStat(
                        title:
                            'Expenses',
                        value:
                            '$totalExpensesCount',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            /// SEARCH BAR
            TextField(
              decoration: InputDecoration(
                hintText:
                    'Search groups...',

                prefixIcon:
                    const Icon(
                  Icons.search,
                ),

                filled: true,

                fillColor:
                    Theme.of(context)
                        .cardColor,

                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),

                  borderSide:
                      BorderSide.none,
                ),
              ),

              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),

            const SizedBox(height: 30),

            /// TITLE
            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceBetween,

              children: [

                const Text(
                  'Your Groups',

                  style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                Text(
                  '${filteredGroups.length} Total',
                ),
              ],
            ),

            const SizedBox(height: 20),

            filteredGroups.isEmpty

                ? const Center(
                    child: Padding(
                      padding:
                          EdgeInsets.all(
                        40,
                      ),

                      child: Text(
                        'No matching groups found',
                      ),
                    ),
                  )

                : ListView.builder(
                    shrinkWrap: true,

                    physics:
                        const NeverScrollableScrollPhysics(),

                    itemCount:
                        filteredGroups.length,

                    itemBuilder:
                        (context, index) {

                      final group =
                          filteredGroups[
                              index];

                      return buildGroupCard(
                        group: group,
                        color:
                            AppTheme.primary,
                      );
                    },
                  ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget buildMiniStat({
    required String title,
    required String value,
  }) {

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        Text(
          title,

          style: const TextStyle(
            color: Colors.white70,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          value,

          style: const TextStyle(
            color: Colors.white,

            fontSize: 20,

            fontWeight:
                FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget buildGroupCard({
    required GroupModel group,
    required Color color,
  }) {

    return InkWell(
      borderRadius:
          BorderRadius.circular(20),

      onTap: () =>
          openGroupDetails(group),

      child: Container(
        margin:
            const EdgeInsets.only(
          bottom: 16,
        ),

        padding:
            const EdgeInsets.all(18),

        decoration: BoxDecoration(
          color:
              Theme.of(context)
                  .cardColor,

          borderRadius:
              BorderRadius.circular(
            20,
          ),
        ),

        child: Row(
          children: [

            CircleAvatar(
              radius: 30,

              backgroundColor:
                  color.withOpacity(
                0.15,
              ),

              child: Icon(
                Icons.groups,
                color: color,
                size: 30,
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,

                children: [

                  Text(
                    group.groupName,

                    style:
                        const TextStyle(
                      fontSize: 19,

                      fontWeight:
                          FontWeight
                              .bold,
                    ),
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Text(
                    '${group.members.length} Members • ${group.expenses.length} Expenses',
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.end,

              children: [

                Text(
                  'Rs. ${group.totalExpense.toStringAsFixed(0)}',

                  style:
                      const TextStyle(
                    fontSize: 18,

                    fontWeight:
                        FontWeight.bold,

                    color:
                        AppTheme.primary,
                  ),
                ),

                Row(
                  mainAxisSize:
                      MainAxisSize.min,

                  children: [

                    IconButton(
                      tooltip:
                          'PDF Report',

                      onPressed: () =>
                          openReport(
                        group,
                      ),

                      icon: const Icon(
                        Icons.picture_as_pdf,
                        color: Colors.red,
                      ),
                    ),

                    IconButton(
                      tooltip:
                          'Delete Group',

                      onPressed: () =>
                          confirmDeleteGroup(
                        group,
                      ),

                      icon: const Icon(
                        Icons.delete_outline,

                        color:
                            AppTheme.warning,
                      ),
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
}