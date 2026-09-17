import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/settlement_model.dart';
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

  Future<void> markAsSettled(SettlementModel settlement) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Mark as Settled"),
        content: Text("Mark ₹${settlement.amount.toStringAsFixed(0)} from ${settlement.fromUser} to ${settlement.toUser} as settled?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final newSettlement = SettlementModel(
      fromUser: settlement.fromUser,
      toUser: settlement.toUser,
      amount: settlement.amount,
      isSettled: true,
      settledAt: DateTime.now(),
    );

    if (!mounted) return;

    setState(() {
      widget.group.recordedSettlements = List.from(widget.group.recordedSettlements)..add(newSettlement);
    });

    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .update({
            'recordedSettlements': FieldValue.arrayUnion([newSettlement.toMap()]),
          });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settlement recorded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update settlement: $e')),
        );
      }
    }
  }

  Future<void> openGroupInfo() async {
    // FIXED: Catch the updated GroupModel structure returned from the pop execution context
    final GroupModel? updatedGroup = await Navigator.push<GroupModel>(
      context,
      MaterialPageRoute(builder: (_) => GroupInfoScreen(group: widget.group)),
    );

    if (!mounted) return;
    
    // Explicitly command the layout container to re-render using the freshly caught cloud URL
    setState(() {
      if (updatedGroup != null) {
        widget.group.groupName = updatedGroup.groupName;
        widget.group.description = updatedGroup.description;
        widget.group.avatarPath = updatedGroup.avatarPath;
        widget.group.members = updatedGroup.members;
      }
    });
    
    await widget.onGroupUpdated?.call();
  }

  Future<void> addExpense() async {
    final ExpenseModel? result = await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(builder: (_) => AddExpenseScreen(group: widget.group)),
    );

    if (result == null) return;

    if (!mounted) return;

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

    if (updatedExpense == null) return;

    if (!mounted) return;

    setState(() {
      widget.group.expenses[originalIndex] = updatedExpense;
    });

    await widget.onGroupUpdated?.call();
  }

  Future<void> deleteExpense(int index) async {
    final expense = filteredExpenses[index];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Delete Expense"),
        content: Text("Delete ${expense.title} ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    setState(() {
      widget.group.expenses.remove(expense);
    });

    await widget.onGroupUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    
    final tileBackgroundColor = isDark ? theme.cardColor : const Color(0xFFF4F3F9);

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
          onPressed: addExpense,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            "Add Expense",
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// COVER PHOTO CONTAINER
            Container(
              width: double.infinity,
              height: 220, 
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1B21) : const Color(0xFFE2E8F0),
                image: widget.group.avatarPath.isNotEmpty
                    ? DecorationImage(
                        image: widget.group.avatarPath.startsWith('http')
                            ? NetworkImage(widget.group.avatarPath)
                            : FileImage(File(widget.group.avatarPath)) as ImageProvider,
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(isDark ? 0.45 : 0.25),
                          BlendMode.srcOver,
                        ),
                      )
                    : DecorationImage(
                        image: AssetImage(isDark ? 'assets/images/SamDark.png' : 'assets/images/SamLight.png'),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          isDark ? Colors.black38 : Colors.black.withOpacity(0.05),
                          BlendMode.srcOver,
                        ),
                      ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                    children: [
                      /// Action Controls Header Navigation Bar Layer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          /// Circular background for Back Icon matching the people badge
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: isDark ? Colors.white : Colors.black87,
                                size: 20,
                              ),
                            ),
                          ),
                          
                          /// FIXED: Translucent background pill wrapping the Group Name with 0.8 opacity
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.group.groupName.toUpperCase(),
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.black87 : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          
                          /// Circular background for Settings Icon matching the people badge
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              tooltip: "Group Settings",
                              icon: Icon(Icons.settings, color: isDark ? Colors.white : Colors.black87),
                              onPressed: openGroupInfo,
                            ),
                          ),
                        ],
                      ),
                      
                      const Spacer(), 

                      /// People Oval Badge Layout Element
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_alt_outlined, color: isDark ? Colors.white70 : Colors.black54, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              "${widget.group.members.length} People",
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            /// TOTAL EXPENSE BOX POSITIONED OUTSIDE AFTER THE COVER PHOTO
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withOpacity(0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total Group Expense",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      "₹ ${widget.group.totalExpense.toStringAsFixed(0)}",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            /// CONTENT LIST BODY INTERFACES
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (expenses.isNotEmpty) ...[
                    Text(
                      "Settlements",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (widget.group.allSettlements.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            "All settled up! 🎉",
                            style: GoogleFonts.poppins(
                              color: textColor.withOpacity(0.5),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.group.allSettlements.length,
                        itemBuilder: (context, index) {
                          final settlement = widget.group.allSettlements[index];

                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            color: tileBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: const Color(0xFF83F4EB).withOpacity(0.14)),
                            ),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFE8EEFF),
                                child: Icon(Icons.swap_horiz, color: AppTheme.primary),
                              ),
                              title: Text(
                                "${settlement.fromUser} pays ${settlement.toUser}",
                                style: TextStyle(
                                  color: settlement.isSettled ? textColor.withOpacity(0.5) : textColor,
                                  decoration: settlement.isSettled ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              subtitle: Text(
                                settlement.isSettled ? "Settled" : "Pending",
                                style: TextStyle(
                                  color: settlement.isSettled ? Colors.green : textColor.withOpacity(0.7),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "₹ ${settlement.amount.toStringAsFixed(0)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: settlement.isSettled ? Colors.grey : AppTheme.primary,
                                      fontSize: 14,
                                      decoration: settlement.isSettled ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  if (!settlement.isSettled) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                      onPressed: () => markAsSettled(settlement),
                                    ),
                                  ] else ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.check_circle, color: Colors.green),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 28),
                  ],

                  /// EXPANDABLE SEARCH BAR
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
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: "Search expenses...",
                              hintStyle: TextStyle(color: textColor.withOpacity(0.5)),
                              prefixIcon: Icon(Icons.search, color: textColor.withOpacity(0.7)),
                              suffixIcon: IconButton(
                                icon: Icon(Icons.close_rounded, color: textColor.withOpacity(0.7)),
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
                              fillColor: tileBackgroundColor,
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
                                backgroundColor: tileBackgroundColor,
                                child: Icon(
                                  Icons.search_rounded,
                                  color: textColor.withOpacity(0.7),
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),

                  /// CATEGORY FILTER CHIPS
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
                      Text(
                        "Expenses",
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      Text(
                        "${filteredExpenses.length} Total",
                        style: GoogleFonts.poppins(fontSize: 12, color: textColor.withOpacity(0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  if (filteredExpenses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(child: Text("No Expenses Found", style: TextStyle(color: textColor.withOpacity(0.5)))),
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
                          color: tileBackgroundColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: const Color(0xFF83F4EB).withOpacity(0.14)),
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
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        expense.category,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text("Paid by ${expense.paidBy}", style: TextStyle(color: textColor.withOpacity(0.8))),
                                const SizedBox(height: 4),
                                Text(
                                  "${expense.date.day}/${expense.date.month}/${expense.date.year}",
                                  style: TextStyle(color: textColor.withOpacity(0.6)),
                                ),
                                const SizedBox(height: 12),
                                if (expense.splitType == "custom")
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: expense.customSplits.entries.map((entry) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withOpacity(.08),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          "${entry.key}: ₹ ${entry.value.toStringAsFixed(0)}",
                                          style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 11),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                if (expense.splitType == "custom") const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "₹ ${expense.amount.toStringAsFixed(0)}",
                                      style: GoogleFonts.poppins(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          tooltip: "Edit Expense",
                                          onPressed: () => editExpense(index),
                                          icon: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                                        ),
                                        IconButton(
                                          tooltip: "Delete Expense",
                                          onPressed: () => deleteExpense(index),
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
                      },
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
