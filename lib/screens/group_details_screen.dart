import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../theme/app_theme.dart';
import 'add_expense_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.group,
    this.onGroupUpdated,
  });

  final GroupModel group;
  final Future<void> Function()? onGroupUpdated;

  @override
  State<GroupDetailsScreen> createState() =>
      _GroupDetailsScreenState();
}

class _GroupDetailsScreenState
    extends State<GroupDetailsScreen> {

  List<ExpenseModel> get expenses =>
      widget.group.expenses;

  Future<void> addExpense() async {
    final ExpenseModel? result =
        await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddExpenseScreen(group: widget.group),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      widget.group.expenses.add(result);
    });

    await widget.onGroupUpdated?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.title} Expense Added Successfully',
        ),
      ),
    );
  }

  Future<void> deleteExpense(int index) async {
    final deletedExpense = expenses[index];

    setState(() {
      widget.group.expenses.removeAt(index);
    });

    await widget.onGroupUpdated?.call();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('${deletedExpense.title} Expense Deleted'),
      ),
    );
  }

  Future<void> editExpense(int index) async {
    final currentExpense = expenses[index];

    final ExpenseModel? updatedExpense =
        await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          group: widget.group,
          expense: currentExpense,
        ),
      ),
    );

    if (updatedExpense == null || !mounted) return;

    setState(() {
      widget.group.expenses[index] = updatedExpense;
    });

    await widget.onGroupUpdated?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${updatedExpense.title} Expense Updated',
        ),
      ),
    );
  }

  Future<void> shareSettlements() async {
    final settlements = widget.group.settlements;

    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add an expense before sharing',
          ),
        ),
      );
      return;
    }

    final settlementText = settlements.isEmpty
        ? 'Everyone is settled up.'
        : settlements
            .map(
              (settlement) =>
                  '${settlement.from} pays ${settlement.to}: Rs. ${settlement.amount.toStringAsFixed(0)}',
            )
            .join('\n');

    final message = Uri.encodeComponent(
      'SamVibhag settlement for ${widget.group.groupName}\n\n'
      'Total expense: Rs. ${widget.group.totalExpense.toStringAsFixed(0)}\n\n'
      '$settlementText',
    );

    final uri =
        Uri.parse('https://wa.me/?text=$message');

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open WhatsApp'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        title: Text(
          widget.group.groupName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          if (expenses.isNotEmpty)
            IconButton(
              tooltip: 'Share settlements',
              onPressed: shareSettlements,
              icon: const Icon(
                Icons.share,
                color: Colors.white,
              ),
            ),

          const NightModeButton(),
        ],
      ),

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: addExpense,
        icon: const Icon(
          Icons.add,
          color: Colors.white,
        ),
        label: const Text(
          'Add Expense',
          style: TextStyle(color: Colors.white),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            /// SUMMARY CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary,

                borderRadius:
                    BorderRadius.circular(20),
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  Text(
                    '${widget.group.members.length} Members',

                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Rs. ${widget.group.totalExpense.toStringAsFixed(0)}',

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Total Group Expense',

                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            /// MEMBERS
            const Text(
              'Members',

              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),

              itemCount:
                  widget.group.members.length,

              itemBuilder: (context, index) {
                final member =
                    widget.group.members[index];

                final balance =
                    widget.group.memberBalances[
                            member] ??
                        0;

                final isPositive = balance > 0.01;
                final isNegative = balance < -0.01;

                return Card(
                  elevation: 0,
                  color:
                      Theme.of(context).cardColor,

                  margin:
                      const EdgeInsets.only(
                          bottom: 10),

                  child: ListTile(
                    leading:
                        const CircleAvatar(
                      backgroundColor:
                          AppTheme.primary,

                      child: Icon(
                        Icons.person,
                        color: Colors.white,
                      ),
                    ),

                    title: Text(member),

                    subtitle: Text(
                      isPositive
                          ? 'Gets Rs. ${balance.toStringAsFixed(0)}'
                          : isNegative
                              ? 'Owes Rs. ${(-balance).toStringAsFixed(0)}'
                              : 'Settled up',
                    ),
                  ),
                );
              },
            ),

            if (expenses.isNotEmpty) ...[
              const SizedBox(height: 20),

              /// SETTLEMENTS
              const Text(
                'Settlements',

                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,
                physics:
                    const NeverScrollableScrollPhysics(),

                itemCount:
                    widget.group.settlements.length,

                itemBuilder: (context, index) {
                  final settlement =
                      widget.group
                          .settlements[index];

                  return Card(
                    elevation: 0,
                    color: Theme.of(context)
                        .cardColor,

                    margin:
                        const EdgeInsets.only(
                            bottom: 10),

                    child: ListTile(
                      leading:
                          const CircleAvatar(
                        child:
                            Icon(Icons.swap_horiz),
                      ),

                      title: Text(
                        '${settlement.from} pays ${settlement.to}',
                      ),

                      trailing: Text(
                        'Rs. ${settlement.amount.toStringAsFixed(0)}',

                        style: const TextStyle(
                          color:
                              AppTheme.primary,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 20),

            /// EXPENSES TITLE
            const Text(
              'Expenses',

              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            expenses.isEmpty
                ? const Center(
                    child: Padding(
                      padding:
                          EdgeInsets.all(30),
                      child: Text(
                        'No expenses added yet',
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),

                    itemCount: expenses.length,

                    itemBuilder:
                        (context, index) {
                      final expense =
                          expenses[index];

                      return Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .cardColor,

                        margin:
                            const EdgeInsets.only(
                                bottom: 12),

                        child: Padding(
                          padding:
                              const EdgeInsets.all(
                                  12),

                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,

                            children: [

                              Row(
                                children: [

                                  Expanded(
                                    child: Text(
                                      expense.title,

                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .bold,

                                        fontSize:
                                            17,
                                      ),
                                    ),
                                  ),

                                  Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal:
                                          10,
                                      vertical:
                                          4,
                                    ),

                                    decoration:
                                        BoxDecoration(
                                      color: Theme.of(
                                              context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(
                                              0.12),

                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                                  20),
                                    ),

                                    child: Text(
                                      expense
                                          .category,

                                      style:
                                          TextStyle(
                                        color: Theme.of(
                                                context)
                                            .colorScheme
                                            .primary,

                                        fontSize:
                                            12,

                                        fontWeight:
                                            FontWeight
                                                .w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                  height: 8),

                              Text(
                                'Paid by ${expense.paidBy} • Split between ${expense.splitBetween.length}',
                              ),

                              const SizedBox(
                                  height: 4),

                              Text(
                                '${expense.date.day}/${expense.date.month}/${expense.date.year} • '
                                '${expense.date.hour}:${expense.date.minute.toString().padLeft(2, '0')}',

                                style:
                                    const TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.grey,
                                ),
                              ),

                              const SizedBox(
                                  height: 10),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment
                                        .spaceBetween,

                                children: [

                                  Text(
                                    'Rs. ${expense.amount.toStringAsFixed(0)}',

                                    style:
                                        const TextStyle(
                                      color: AppTheme
                                          .primary,

                                      fontSize: 18,

                                      fontWeight:
                                          FontWeight
                                              .bold,
                                    ),
                                  ),

                                  Row(
                                    children: [

                                      IconButton(
                                        onPressed:
                                            () =>
                                                editExpense(
                                                    index),

                                        icon:
                                            const Icon(
                                          Icons
                                              .edit_outlined,

                                          color:
                                              AppTheme
                                                  .primary,
                                        ),
                                      ),

                                      IconButton(
                                        onPressed:
                                            () =>
                                                deleteExpense(
                                                    index),

                                        icon:
                                            const Icon(
                                          Icons
                                              .delete_outline,

                                          color:
                                              AppTheme
                                                  .warning,
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

            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}