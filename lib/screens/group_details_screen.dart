import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../theme/app_theme.dart';

import 'add_expense_screen.dart';
import '../services/report_screen.dart';

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

  String searchQuery = '';
  String selectedCategory = 'All';

  List<String> get categories {

    final uniqueCategories =
        expenses
            .map(
              (e) => e.category,
            )
            .toSet()
            .toList();

    uniqueCategories.sort();

    return [
      'All',
      ...uniqueCategories,
    ];
  }

  List<ExpenseModel> get filteredExpenses {

    return expenses.where((expense) {

      final matchesSearch =
          expense.title
                  .toLowerCase()
                  .contains(
                    searchQuery
                        .toLowerCase(),
                  ) ||
              expense.category
                  .toLowerCase()
                  .contains(
                    searchQuery
                        .toLowerCase(),
                  ) ||
              expense.paidBy
                  .toLowerCase()
                  .contains(
                    searchQuery
                        .toLowerCase(),
                  );

      final matchesCategory =
          selectedCategory ==
                  'All' ||
              expense.category ==
                  selectedCategory;

      return matchesSearch &&
          matchesCategory;
    }).toList();
  }

  Future<void> addExpense() async {

    final ExpenseModel? result =
        await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddExpenseScreen(
          group: widget.group,
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      widget.group.expenses.add(result);
    });

    await widget.onGroupUpdated?.call();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '${result.title} Expense Added Successfully',
        ),
      ),
    );
  }

  Future<void> editExpense(
    int index,
  ) async {

    final currentExpense =
        filteredExpenses[index];

    final originalIndex =
        expenses.indexOf(
      currentExpense,
    );

    final ExpenseModel? updatedExpense =
        await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddExpenseScreen(
          group: widget.group,
          expense: currentExpense,
        ),
      ),
    );

    if (updatedExpense == null ||
        !mounted) {
      return;
    }

    setState(() {
      widget.group.expenses[
              originalIndex] =
          updatedExpense;
    });

    await widget.onGroupUpdated?.call();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '${updatedExpense.title} Expense Updated',
        ),
      ),
    );
  }

  Future<void> deleteExpense(
    int index,
  ) async {

    final expense =
        filteredExpenses[index];

    final shouldDelete =
        await showDialog<bool>(
      context: context,

      builder: (context) {

        return AlertDialog(
          title:
              const Text('Delete Expense?'),

          content: Text(
            'Delete ${expense.title} expense?',
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
      widget.group.expenses
          .remove(expense);
    });

    await widget.onGroupUpdated?.call();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '${expense.title} Expense Deleted',
        ),
      ),
    );
  }

  Future<void> openReport() async {

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReportScreen(
          group: widget.group,
        ),
      ),
    );
  }

  Future<void> shareSettlements() async {

    final settlements =
        widget.group.settlements;

    if (expenses.isEmpty) {

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'No expenses to share',
          ),
        ),
      );

      return;
    }

    final settlementText =
        settlements.isEmpty

            ? 'Everyone is settled up.'

            : settlements
                .map(
                  (s) =>
                      '${s.from} pays ${s.to}: Rs. ${s.amount.toStringAsFixed(0)}',
                )
                .join('\n');

    final message =
        Uri.encodeComponent(
      'SamVibhag Settlement - ${widget.group.groupName}\n\n'
      '$settlementText',
    );

    final uri = Uri.parse(
      'https://wa.me/?text=$message',
    );

    if (await canLaunchUrl(uri)) {

      await launchUrl(
        uri,
        mode:
            LaunchMode
                .externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor:
          Theme.of(context)
              .scaffoldBackgroundColor,

      appBar: AppBar(
        title: Text(
          widget.group.groupName,

          style: const TextStyle(
            color: Colors.white,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [

          IconButton(
            tooltip: 'Export PDF',

            onPressed: openReport,

            icon: const Icon(
              Icons.picture_as_pdf,
              color: Colors.white,
            ),
          ),

          IconButton(
            tooltip:
                'Share settlements',

            onPressed:
                shareSettlements,

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

                  Text(
                    '${widget.group.members.length} Members',

                    style:
                        const TextStyle(
                      color:
                          Colors.white70,

                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(
                    height: 10,
                  ),

                  Text(
                    'Rs. ${widget.group.totalExpense.toStringAsFixed(0)}',

                    style:
                        const TextStyle(
                      color:
                          Colors.white,

                      fontSize: 36,

                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  const Text(
                    'Total Group Expense',

                    style: TextStyle(
                      color:
                          Colors.white70,

                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            /// MEMBERS
            const Text(
              'Members',

              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true,

              physics:
                  const NeverScrollableScrollPhysics(),

              itemCount:
                  widget.group.members
                      .length,

              itemBuilder:
                  (context, index) {

                final member =
                    widget.group
                        .members[index];

                final balance =
                    widget.group
                            .memberBalances[
                        member] ??
                    0;

                final isPositive =
                    balance > 0.01;

                final isNegative =
                    balance < -0.01;

                return Card(
                  elevation: 0,

                  margin:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),

                  child: ListTile(
                    leading:
                        const CircleAvatar(
                      backgroundColor:
                          AppTheme.primary,

                      child: Icon(
                        Icons.person,
                        color:
                            Colors.white,
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

              const SizedBox(height: 25),

              /// SETTLEMENTS
              const Text(
                'Settlements',

                style: TextStyle(
                  fontSize: 22,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,

                physics:
                    const NeverScrollableScrollPhysics(),

                itemCount:
                    widget.group
                        .settlements
                        .length,

                itemBuilder:
                    (context, index) {

                  final settlement =
                      widget.group
                              .settlements[
                          index];

                  return Card(
                    elevation: 0,

                    margin:
                        const EdgeInsets.only(
                      bottom: 10,
                    ),

                    child: ListTile(
                      leading:
                          const CircleAvatar(
                        child: Icon(
                          Icons.swap_horiz,
                        ),
                      ),

                      title: Text(
                        '${settlement.from} pays ${settlement.to}',
                      ),

                      trailing: Text(
                        'Rs. ${settlement.amount.toStringAsFixed(0)}',

                        style:
                            const TextStyle(
                          color:
                              AppTheme
                                  .primary,

                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 25),

            /// SEARCH BAR
            TextField(
              decoration: InputDecoration(
                hintText:
                    'Search expenses...',

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

            const SizedBox(height: 16),

            /// CATEGORY FILTERS
            SizedBox(
              height: 42,

              child: ListView(
                scrollDirection:
                    Axis.horizontal,

                children:
                    categories.map(
                  (category) {

                    final selected =
                        selectedCategory ==
                            category;

                    return Padding(
                      padding:
                          const EdgeInsets.only(
                        right: 10,
                      ),

                      child: ChoiceChip(
                        label:
                            Text(category),

                        selected:
                            selected,

                        onSelected:
                            (_) {

                          setState(() {
                            selectedCategory =
                                category;
                          });
                        },
                      ),
                    );
                  },
                ).toList(),
              ),
            ),

            const SizedBox(height: 25),

            /// EXPENSES TITLE
            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceBetween,

              children: [

                const Text(
                  'Expenses',

                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                Text(
                  '${filteredExpenses.length} Total',
                ),
              ],
            ),

            const SizedBox(height: 15),

            filteredExpenses.isEmpty

                ? const Center(
                    child: Padding(
                      padding:
                          EdgeInsets.all(
                        30,
                      ),

                      child: Text(
                        'No matching expenses found',
                      ),
                    ),
                  )

                : ListView.builder(
                    shrinkWrap: true,

                    physics:
                        const NeverScrollableScrollPhysics(),

                    itemCount:
                        filteredExpenses
                            .length,

                    itemBuilder:
                        (context, index) {

                      final expense =
                          filteredExpenses[
                              index];

                      return Card(
                        elevation: 0,

                        margin:
                            const EdgeInsets.only(
                          bottom: 14,
                        ),

                        child: Padding(
                          padding:
                              const EdgeInsets.all(
                            14,
                          ),

                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,

                            children: [

                              Row(
                                children: [

                                  Expanded(
                                    child: Text(
                                      expense
                                          .title,

                                      style:
                                          const TextStyle(
                                        fontSize:
                                            18,

                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),
                                  ),

                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
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
                                            0.12,
                                          ),

                                      borderRadius:
                                          BorderRadius.circular(
                                        20,
                                      ),
                                    ),

                                    child: Text(
                                      expense
                                          .category,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                height: 8,
                              ),

                              Text(
                                'Paid by ${expense.paidBy}',
                              ),

                              const SizedBox(
                                height: 4,
                              ),

                              Text(
                                '${expense.date.day}/${expense.date.month}/${expense.date.year}',
                              ),

                              const SizedBox(
                                height: 10,
                              ),

                              if (expense
                                      .splitType ==
                                  'custom')

                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,

                                  children: expense
                                      .customSplits
                                      .entries
                                      .map(
                                    (entry) {

                                      return Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                          horizontal:
                                              10,

                                          vertical:
                                              6,
                                        ),

                                        decoration:
                                            BoxDecoration(
                                          color: Theme.of(
                                                  context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(
                                                0.08,
                                              ),

                                          borderRadius:
                                              BorderRadius.circular(
                                            20,
                                          ),
                                        ),

                                        child: Text(
                                          '${entry.key}: Rs. ${entry.value.toStringAsFixed(0)}',
                                        ),
                                      );
                                    },
                                  ).toList(),
                                ),

                              if (expense
                                      .splitType ==
                                  'custom')
                                const SizedBox(
                                  height: 10,
                                ),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment
                                        .spaceBetween,

                                children: [

                                  Text(
                                    'Rs. ${expense.amount.toStringAsFixed(0)}',

                                    style:
                                        const TextStyle(
                                      color:
                                          AppTheme
                                              .primary,

                                      fontSize:
                                          20,

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
                                          index,
                                        ),

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
                                          index,
                                        ),

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

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}