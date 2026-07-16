import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../core/theme/app_theme.dart';

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
  bool _isLoading = false; // Prevents double taps during database network operations

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
      customSplitControllers[member]?.text = (memberCents / 100).toStringAsFixed(2);
    }
  }

  void updateCustomAmount(String member) {
    manuallyEditedMembers.add(member);
    redistributeCustomAmounts();
  }

  // FIXED: Converts saving method into a Cloud Firestore sync transaction engine
  Future<void> saveExpense() async {
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
          const SnackBar(content: Text('Custom split total must equal expense amount')),
        );
        return;
      }
    }

    final updatedExpense = ExpenseModel(
      title: title,
      amount: amount,
      paidBy: paidBy,
      splitBetween: List<String>.from(selectedMembers),
      date: widget.expense?.date ?? DateTime.now(),
      category: selectedCategory,
      splitType: splitType,
      customSplits: customSplits,
    );

    setState(() => _isLoading = true);

    try {
      // Create a local duplicate tracking copy of the current list state
      final currentExpenses = List<ExpenseModel>.from(widget.group.expenses);

      if (widget.expense == null) {
        // Mode A: Append a fresh transaction artifact
        currentExpenses.add(updatedExpense);
      } else {
        // Mode B: Find and swap out the outdated match inside your array
        final index = currentExpenses.indexWhere((e) => e.title == widget.expense!.title && e.amount == widget.expense!.amount);
        if (index != -1) {
          currentExpenses[index] = updatedExpense;
        } else {
          currentExpenses.add(updatedExpense);
        }
      }

      // Overwrite the Firestore array collection with your newly verified dataset
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .update({
            'expenses': currentExpenses.map((e) => e.toMap()).toList(),
          });

      if (!mounted) return;
      Navigator.pop(context, updatedExpense);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update expense in Cloud: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          widget.expense == null ? 'Add Expense' : 'Edit Expense',
          style: GoogleFonts.poppins(
            fontSize: 19,
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [NightModeButton()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.expense == null ? 'Add a new expense' : 'Update expense details',
                    style: GoogleFonts.poppins(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Keep everyone in the group in sync.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    style: GoogleFonts.poppins(color: theme.colorScheme.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Expense Title',
                      labelStyle: GoogleFonts.poppins(fontSize: 13),
                      prefixIcon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0284C7)),
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF83F4EB), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.poppins(color: theme.colorScheme.onSurface, fontSize: 14),
                    onChanged: (_) => redistributeCustomAmounts(),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'Rs. ',
                      labelStyle: GoogleFonts.poppins(fontSize: 13),
                      prefixIcon: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF0284C7)),
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF83F4EB), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: theme.cardColor,
                    style: GoogleFonts.poppins(color: theme.colorScheme.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Category',
                      labelStyle: GoogleFonts.poppins(fontSize: 13),
                      prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF0284C7)),
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                    items: categories.map((category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedCategory = value);
                    },
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: paidBy,
                    dropdownColor: theme.cardColor,
                    style: GoogleFonts.poppins(color: theme.colorScheme.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Paid By',
                      labelStyle: GoogleFonts.poppins(fontSize: 13),
                      prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF0284C7)),
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                    items: widget.group.members.map((member) {
                      return DropdownMenuItem<String>(
                        value: member,
                        child: Text(member),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => paidBy = value);
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Split Type',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
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
                  Text(
                    'Split Between',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
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
                          color: theme.cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: const Color(0xFF83F4EB).withOpacity(0.14)),
                          ),
                          child: CheckboxListTile(
                            activeColor: theme.colorScheme.primary,
                            value: isSelected,
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                if (splitType == 'custom')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: TextField(
                                      controller: customSplitControllers[member],
                                      enabled: isSelected,
                                      style: TextStyle(color: theme.colorScheme.onSurface),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      onChanged: (_) => updateCustomAmount(member),
                                      decoration: InputDecoration(
                                        labelText: 'Custom Amount',
                                        prefixText: 'Rs. ',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withOpacity(0.26),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: saveExpense,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        widget.expense == null ? 'Save Expense' : 'Update Expense',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
