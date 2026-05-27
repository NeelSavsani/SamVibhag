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
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  List<ExpenseModel> get expenses => widget.group.expenses;

  Future<void> addExpense() async {
    final result = await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(group: widget.group),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      widget.group.expenses.add(result);
    });

    await widget.onGroupUpdated?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.title} Expense Added Successfully'),
      ),
    );
  }

  Future<void> deleteExpense(int index) async {
    final deletedExpense = expenses[index];

    setState(() {
      widget.group.expenses.removeAt(index);
    });

    await widget.onGroupUpdated?.call();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${deletedExpense.title} Expense Deleted'),
      ),
    );
  }

  Future<void> editExpense(int index) async {
    final currentExpense = expenses[index];
    final updatedExpense = await Navigator.push<ExpenseModel>(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          group: widget.group,
          expense: currentExpense,
        ),
      ),
    );

    if (updatedExpense == null || !mounted) {
      return;
    }

    setState(() {
      widget.group.expenses[index] = updatedExpense;
    });

    await widget.onGroupUpdated?.call();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${updatedExpense.title} Expense Updated'),
      ),
    );
  }

  Future<void> shareSettlements() async {
    final settlements = widget.group.settlements;

    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an expense before sharing')),
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
    final uri = Uri.parse('https://wa.me/?text=$message');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp')),
    );
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addExpense,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Expense',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSummaryCard(),
            const SizedBox(height: 28),
            const Text(
              'Members',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            buildMembersList(),
            if (expenses.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Settlements',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              buildSettlementsList(),
            ],
            const SizedBox(height: 20),
            const Text(
              'Expenses',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            expenses.isEmpty ? buildEmptyExpenses() : buildExpensesList(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }

  Widget buildMembersList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.group.members.length,
      itemBuilder: (context, index) {
        final member = widget.group.members[index];
        final balance = widget.group.memberBalances[member] ?? 0;
        final isPositive = balance > 0.01;
        final isNegative = balance < -0.01;
        final balanceText = isPositive
            ? 'Gets Rs. ${balance.toStringAsFixed(0)}'
            : isNegative
                ? 'Owes Rs. ${(-balance).toStringAsFixed(0)}'
                : 'Settled up';

        return Card(
          elevation: 0,
          color: Theme.of(context).cardColor,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppTheme.primary,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(
              member,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(balanceText),
            trailing: Icon(
              isPositive
                  ? Icons.arrow_downward
                  : isNegative
                      ? Icons.arrow_upward
                      : Icons.check,
              color: isPositive
                  ? Colors.green
                  : isNegative
                      ? AppTheme.warning
                      : Colors.grey,
            ),
          ),
        );
      },
    );
  }

  Widget buildSettlementsList() {
    final settlements = widget.group.settlements;

    if (settlements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Everyone is settled up',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: settlements.length,
      itemBuilder: (context, index) {
        final settlement = settlements[index];

        return Card(
          elevation: 0,
          color: Theme.of(context).cardColor,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.14),
              child: Icon(
                Icons.swap_horiz,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text('${settlement.from} pays ${settlement.to}'),
            trailing: Text(
              'Rs. ${settlement.amount.toStringAsFixed(0)}',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildEmptyExpenses() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: const Text(
        'No expenses added yet',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget buildExpensesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final expense = expenses[index];

        return Card(
          elevation: 0,
          color: Theme.of(context).cardColor,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFEDD5),
              child: Icon(
                Icons.receipt_long,
                color: AppTheme.primary,
              ),
            ),
            title: Text(
              expense.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Paid by ${expense.paidBy} - Split between ${expense.splitBetween.length}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rs. ${expense.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit expense',
                  onPressed: () => editExpense(index),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppTheme.primary,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete expense',
                  onPressed: () => deleteExpense(index),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
