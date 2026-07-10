import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';

import '../../core/theme/app_theme.dart';

import 'add_expense_screen.dart';
import 'group_info_screen.dart';

import '../report_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.group,
    this.onGroupUpdated,
  });

  final GroupModel group;

  final Future<void> Function()? onGroupUpdated;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  List<ExpenseModel> get expenses => widget.group.expenses;

  String searchQuery = '';

  String selectedCategory = 'All';

  List<String> get categories {
    final uniqueCategories = expenses.map((e) => e.category).toSet().toList();

    uniqueCategories.sort();

    return ['All', ...uniqueCategories];
  }

  List<ExpenseModel> get filteredExpenses {
    return expenses.where((expense) {
      final search = searchQuery.toLowerCase();

      final matchesSearch =
          expense.title.toLowerCase().contains(search) ||
          expense.category.toLowerCase().contains(search) ||
          expense.paidBy.toLowerCase().contains(search);

      final matchesCategory =
          selectedCategory == "All" || expense.category == selectedCategory;

      return matchesSearch && matchesCategory;
    }).toList();
  }

  Future<void> openGroupInfo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupInfoScreen(group: widget.group)),
    );

    if (!mounted) return;

    setState(() {});

    await widget.onGroupUpdated?.call();
  }

  Future<void> addExpense() async {
    final ExpenseModel? result = await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(builder: (_) => AddExpenseScreen(group: widget.group)),
    );

    if (result == null) return;

    setState(() {
      widget.group.expenses.add(result);
    });

    await widget.onGroupUpdated?.call();
  }

  Future<void> editExpense(int index) async {
    final expense = filteredExpenses[index];

    final originalIndex = expenses.indexOf(expense);

    final ExpenseModel? updatedExpense = await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(group: widget.group, expense: expense),
      ),
    );

    if (updatedExpense == null) {
      return;
    }

    setState(() {
      widget.group.expenses[originalIndex] = updatedExpense;
    });

    await widget.onGroupUpdated?.call();
  }

  Future<void> deleteExpense(int index) async {
    final expense = filteredExpenses[index];

    final confirm = await showDialog<bool>(
      context: context,

      builder: (_) => AlertDialog(
        title: const Text("Delete Expense"),

        content: Text("Delete ${expense.title} ?"),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),

            child: const Text("Cancel"),
          ),

          FilledButton(
            onPressed: () => Navigator.pop(context, true),

            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      widget.group.expenses.remove(expense);
    });

    await widget.onGroupUpdated?.call();
  }

  Future<void> openReport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(group: widget.group)),
    );
  }

  Future<void> shareSettlements() async {
    final settlements = widget.group.settlements;

    if (settlements.isEmpty) {
      return;
    }

    final message = settlements
        .map(
          (e) => "${e.from} pays ${e.to} : Rs. ${e.amount.toStringAsFixed(0)}",
        )
        .join("\n");

    final uri = Uri.parse(
      "https://wa.me/?text=${Uri.encodeComponent(message)}",
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        title: Text(
          widget.group.groupName,

          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            tooltip: "Group Information",

            icon: const Icon(Icons.edit, color: Colors.white),

            onPressed: openGroupInfo,
          ),

          IconButton(
            tooltip: "Export PDF",

            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),

            onPressed: openReport,
          ),

          IconButton(
            tooltip: "Share",

            icon: const Icon(Icons.share, color: Colors.white),

            onPressed: shareSettlements,
          ),

          const NightModeButton(),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: addExpense,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Expense", style: TextStyle(color: Colors.white)),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            /// GROUP INFO CARD
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),

              child: Padding(
                padding: const EdgeInsets.all(20),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    CircleAvatar(
                      radius: 38,

                      backgroundColor: AppTheme.primary.withOpacity(.12),

                      backgroundImage: widget.group.avatarPath.isNotEmpty
                          ? FileImage(File(widget.group.avatarPath))
                          : null,

                      child: widget.group.avatarPath.isEmpty
                          ? const Icon(
                              Icons.groups,
                              size: 34,
                              color: AppTheme.primary,
                            )
                          : null,
                    ),

                    const SizedBox(width: 18),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            widget.group.groupName,

                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          if (widget.group.description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                widget.group.description,
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ),

                          const SizedBox(height: 10),

                          Row(
                            children: [
                              const Icon(
                                Icons.people,
                                size: 18,
                                color: Colors.grey,
                              ),

                              const SizedBox(width: 6),

                              Text("${widget.group.members.length} Members"),
                            ],
                          ),

                          const SizedBox(height: 6),

                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 18,
                                color: Colors.grey,
                              ),

                              const SizedBox(width: 6),

                              Text(
                                "Created ${widget.group.createdAt.day}/${widget.group.createdAt.month}/${widget.group.createdAt.year}",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// SUMMARY CARD
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(22),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),

                gradient: const LinearGradient(
                  colors: [AppTheme.primary, Color(0xFF1D4ED8)],
                ),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    "${widget.group.members.length} Members",

                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "₹ ${widget.group.totalExpense.toStringAsFixed(0)}",

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    "Total Group Expense",

                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            /// MEMBERS
            const Text(
              "Members",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 14),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.group.members.length,
              itemBuilder: (context, index) {
                final member = widget.group.members[index];

                final balance = widget.group.memberBalances[member] ?? 0;

                final isGets = balance > 0.01;
                final isOwes = balance < -0.01;

                Color avatarColor;
                IconData trailingIcon;
                Color trailingColor;
                String subtitle;

                if (isGets) {
                  avatarColor = Colors.green;

                  trailingIcon = Icons.arrow_downward;

                  trailingColor = Colors.green;

                  subtitle = "Gets ₹ ${balance.toStringAsFixed(0)}";
                } else if (isOwes) {
                  avatarColor = Colors.orange;

                  trailingIcon = Icons.arrow_upward;

                  trailingColor = Colors.orange;

                  subtitle = "Owes ₹ ${(-balance).toStringAsFixed(0)}";
                } else {
                  avatarColor = Colors.blue;

                  trailingIcon = Icons.check_circle;

                  trailingColor = Colors.blue;

                  subtitle = "Settled";
                }

                return Card(
                  elevation: 0,

                  margin: const EdgeInsets.only(bottom: 12),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),

                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: avatarColor.withOpacity(.15),

                      child: Icon(Icons.person, color: avatarColor),
                    ),

                    title: Text(member),

                    subtitle: Text(subtitle),

                    trailing: Icon(trailingIcon, color: trailingColor),
                  ),
                );
              },
            ),

            const SizedBox(height: 28),

            if (expenses.isNotEmpty) ...[
              const Text(
                "Settlements",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 14),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.group.settlements.length,
                itemBuilder: (context, index) {
                  final settlement = widget.group.settlements[index];

                  return Card(
                    elevation: 0,

                    margin: const EdgeInsets.only(bottom: 12),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8EEFF),

                        child: Icon(Icons.swap_horiz, color: AppTheme.primary),
                      ),

                      title: Text("${settlement.from} pays ${settlement.to}"),

                      subtitle: const Text("Settlement"),

                      trailing: Text(
                        "₹ ${settlement.amount.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),
            ],

            /// SEARCH BAR
            TextField(
              decoration: InputDecoration(
                hintText: "Search expenses...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),

            const SizedBox(height: 18),

            /// CATEGORY FILTER
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: categories.map((category) {
                  final selected = selectedCategory == category;

                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          selectedCategory = category;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 28),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Expenses",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                Text("${filteredExpenses.length} Total"),
              ],
            ),

            const SizedBox(height: 18),

            if (filteredExpenses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text("No Expenses Found")),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredExpenses.length,

                itemBuilder: (context, index) {
                  final expense = filteredExpenses[index];

                  return Card(
                    elevation: 0,

                    margin: const EdgeInsets.only(bottom: 16),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: Padding(
                      padding: const EdgeInsets.all(16),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  expense.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),

                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(.12),

                                  borderRadius: BorderRadius.circular(20),
                                ),

                                child: Text(expense.category),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          Text("Paid by ${expense.paidBy}"),

                          const SizedBox(height: 4),

                          Text(
                            "${expense.date.day}/${expense.date.month}/${expense.date.year}",
                          ),

                          const SizedBox(height: 12),
                          if (expense.splitType == "custom")
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: expense.customSplits.entries.map((
                                entry,
                              ) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(.08),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    "${entry.key}: ₹ ${entry.value.toStringAsFixed(0)}",
                                  ),
                                );
                              }).toList(),
                            ),

                          if (expense.splitType == "custom")
                            const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "₹ ${expense.amount.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),

                              Row(
                                children: [
                                  IconButton(
                                    tooltip: "Edit Expense",
                                    onPressed: () => editExpense(index),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: AppTheme.primary,
                                    ),
                                  ),

                                  IconButton(
                                    tooltip: "Delete Expense",
                                    onPressed: () => deleteExpense(index),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppTheme.warning,
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
                },
              ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
