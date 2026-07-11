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

  // State management for expandable search logic
  bool _isSearchExpanded = false;
  final _searchController = TextEditingController();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      // FIXED: Titlebar copied from appearance_screen.dart configuration
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : Colors.black87,
            size: 22,
          ),
        ),
        title: Text(
          widget.group.groupName,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Export PDF",
            icon: Icon(Icons.picture_as_pdf, color: isDark ? Colors.white : Colors.black87),
            onPressed: openReport,
          ),
          IconButton(
            tooltip: "Group Settings",
            icon: Icon(Icons.settings, color: isDark ? Colors.white : Colors.black87),
            onPressed: openGroupInfo,
          ),
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

            /// EXPANDABLE SEARCH BAR WITH CIRCULAR BACKGROUND ON LEFT
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _isSearchExpanded
                  ? TextField(
                      key: const ValueKey('expanded_expense_search'),
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: "Search expenses...",
                        prefixIcon: const Icon(Icons.search),
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
                        setState(() {
                          searchQuery = value;
                        });
                      },
                    )
                  : Align(
                      key: const ValueKey('circle_expense_search_icon'),
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isSearchExpanded = true;
                          });
                        },
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
                                  color: theme.colorScheme.primary.withOpacity(.12),
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
                              children: expense.customSplits.entries.map((entry) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(.08),
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