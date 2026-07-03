import 'package:flutter/material.dart';

import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../theme/app_theme.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, required this.group, this.expense});

  final GroupModel group;
  final ExpenseModel? expense;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final TextEditingController titleController = TextEditingController();

  final TextEditingController amountController = TextEditingController();

  late String paidBy;

  late List<String> selectedMembers;

  late String selectedCategory;

  String splitType = 'equal';

  final Map<String, TextEditingController> customSplitControllers = {};

  final Set<String> manuallyEditedMembers = {};

  final List<String> categories = [
    'Food',
    'Travel',
    'Shopping',
    'Fuel',
    'Rent',
    'Party',
    'Other',
  ];

  @override
  void initState() {
    super.initState();

    final expense = widget.expense;

    paidBy = expense?.paidBy ?? widget.group.members.first;

    selectedMembers = List<String>.from(
      expense?.splitBetween ?? widget.group.members,
    );

    selectedCategory = expense?.category ?? 'Food';

    splitType = expense?.splitType ?? 'equal';

    for (final member in widget.group.members) {
      customSplitControllers[member] = TextEditingController(
        text: expense?.customSplits[member]?.toStringAsFixed(0) ?? '',
      );
    }

    if (expense != null) {
      titleController.text = expense.title;

      amountController.text = expense.amount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();

    for (final controller in customSplitControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void redistributeCustomAmounts() {
    final totalAmount = double.tryParse(amountController.text.trim());

    if (splitType != 'custom' ||
        totalAmount == null ||
        totalAmount < 0 ||
        selectedMembers.isEmpty) {
      return;
    }

    manuallyEditedMembers.removeWhere(
      (member) => !selectedMembers.contains(member),
    );

    double manuallyAssigned = 0;

    for (final member in manuallyEditedMembers) {
      manuallyAssigned +=
          double.tryParse(customSplitControllers[member]?.text.trim() ?? '') ??
          0;
    }

    final automaticMembers = selectedMembers
        .where((member) => !manuallyEditedMembers.contains(member))
        .toList();

    if (automaticMembers.isEmpty) {
      return;
    }

    final remainingCents = ((totalAmount - manuallyAssigned) * 100)
        .round()
        .clamp(0, 1 << 31);

    final baseCents = remainingCents ~/ automaticMembers.length;

    final extraCents = remainingCents % automaticMembers.length;

    for (var index = 0; index < automaticMembers.length; index++) {
      final member = automaticMembers[index];

      final memberCents = baseCents + (index < extraCents ? 1 : 0);

      customSplitControllers[member]?.text = (memberCents / 100)
          .toStringAsFixed(2);
    }
  }

  void updateCustomAmount(String member) {
    manuallyEditedMembers.add(member);
    redistributeCustomAmounts();
  }

  void saveExpense() {
    final title = titleController.text.trim();

    final amount = double.tryParse(amountController.text.trim());

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter expense title')),
      );

      return;
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid amount')),
      );

      return;
    }

    if (selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );

      return;
    }

    Map<String, double> customSplits = {};

    if (splitType == 'custom') {
      double totalCustomAmount = 0;

      for (final member in selectedMembers) {
        final customAmount =
            double.tryParse(customSplitControllers[member]?.text ?? '') ?? 0;

        customSplits[member] = customAmount;

        totalCustomAmount += customAmount;
      }

      if ((totalCustomAmount - amount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom split total must equal expense amount'),
          ),
        );

        return;
      }
    }

    final expense = ExpenseModel(
      title: title,
      amount: amount,
      paidBy: paidBy,
      splitBetween: List<String>.from(selectedMembers),
      date: widget.expense?.date ?? DateTime.now(),
      category: selectedCategory,
      splitType: splitType,
      customSplits: customSplits,
    );

    Navigator.pop(context, expense);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        title: Text(
          widget.expense == null ? 'Add Expense' : 'Edit Expense',

          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: const [NightModeButton()],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            /// TITLE
            TextField(
              controller: titleController,

              decoration: InputDecoration(
                labelText: 'Expense Title',

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 18),

            /// AMOUNT
            TextField(
              controller: amountController,

              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),

              onChanged: (_) {
                redistributeCustomAmounts();
              },

              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: 'Rs. ',

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 18),

            /// CATEGORY
            DropdownButtonFormField<String>(
              value: selectedCategory,

              decoration: InputDecoration(
                labelText: 'Category',

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),

              items: categories.map((category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),

              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  selectedCategory = value;
                });
              },
            ),

            const SizedBox(height: 18),

            /// PAID BY
            DropdownButtonFormField<String>(
              value: paidBy,

              decoration: InputDecoration(
                labelText: 'Paid By',

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),

              items: widget.group.members.map((member) {
                return DropdownMenuItem<String>(
                  value: member,
                  child: Text(member),
                );
              }).toList(),

              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  paidBy = value;
                });
              },
            ),

            const SizedBox(height: 24),

            /// SPLIT TYPE
            const Text(
              'Split Type',

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'equal',
                    groupValue: splitType,
                    title: const Text('Equal'),

                    onChanged: (value) {
                      setState(() {
                        splitType = value!;

                        manuallyEditedMembers.clear();

                        redistributeCustomAmounts();
                      });
                    },
                  ),
                ),

                Expanded(
                  child: RadioListTile<String>(
                    value: 'custom',
                    groupValue: splitType,
                    title: const Text('Custom'),

                    onChanged: (value) {
                      setState(() {
                        splitType = value!;

                        manuallyEditedMembers.clear();

                        redistributeCustomAmounts();
                      });
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            /// SPLIT BETWEEN
            const Text(
              'Split Between',

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: widget.group.members.length,

                itemBuilder: (context, index) {
                  final member = widget.group.members[index];

                  final isSelected = selectedMembers.contains(member);

                  return Card(
                    elevation: 0,

                    color: Theme.of(context).cardColor,

                    child: CheckboxListTile(
                      activeColor: Theme.of(context).colorScheme.primary,

                      value: isSelected,

                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(member),

                          if (splitType == 'custom')
                            Padding(
                              padding: const EdgeInsets.only(top: 10),

                              child: TextField(
                                controller: customSplitControllers[member],

                                enabled: isSelected,

                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),

                                onChanged: (_) => updateCustomAmount(member),

                                decoration: InputDecoration(
                                  labelText: 'Custom Amount',

                                  prefixText: 'Rs. ',

                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            selectedMembers.add(member);

                            manuallyEditedMembers.remove(member);
                          } else {
                            selectedMembers.remove(member);

                            manuallyEditedMembers.remove(member);

                            customSplitControllers[member]?.clear();
                          }

                          redistributeCustomAmounts();
                        });
                      },
                    ),
                  );
                },
              ),
            ),

            /// SAVE BUTTON
            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: saveExpense,

                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),

                child: Text(
                  widget.expense == null ? 'Save Expense' : 'Update Expense',

                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
