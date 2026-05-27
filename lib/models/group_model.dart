import 'expense_model.dart';

class SettlementModel {
  final String from;
  final String to;
  final double amount;

  SettlementModel({
    required this.from,
    required this.to,
    required this.amount,
  });
}

class GroupModel {
  final String groupName;
  final List<String> members;
  final List<ExpenseModel> expenses;

  GroupModel({
    required this.groupName,
    required this.members,
    List<ExpenseModel>? expenses,
  }) : expenses = expenses ?? [];

  factory GroupModel.fromMap(Map<dynamic, dynamic> map) {
    final expenseMaps = List<dynamic>.from(map['expenses'] as List? ?? []);

    return GroupModel(
      groupName: map['groupName'] as String,
      members: List<String>.from(map['members'] as List),
      expenses: expenseMaps
          .map((expenseMap) => ExpenseModel.fromMap(expenseMap as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'groupName': groupName,
      'members': members,
      'expenses': expenses.map((expense) => expense.toMap()).toList(),
    };
  }

  double get totalExpense {
    return expenses.fold<double>(
      0,
      (total, expense) => total + expense.amount,
    );
  }

  Map<String, double> get memberBalances {
    final balances = {
      for (final member in members) member: 0.0,
    };

    for (final expense in expenses) {
      if (expense.splitBetween.isEmpty) {
        continue;
      }

      final share = expense.amount / expense.splitBetween.length;
      balances[expense.paidBy] =
          (balances[expense.paidBy] ?? 0) + expense.amount;

      for (final member in expense.splitBetween) {
        balances[member] = (balances[member] ?? 0) - share;
      }
    }

    return balances;
  }

  List<SettlementModel> get settlements {
    final balances = memberBalances;
    final debtors = <MapEntry<String, double>>[];
    final creditors = <MapEntry<String, double>>[];

    for (final entry in balances.entries) {
      if (entry.value < -0.01) {
        debtors.add(MapEntry(entry.key, -entry.value));
      } else if (entry.value > 0.01) {
        creditors.add(entry);
      }
    }

    final settlements = <SettlementModel>[];
    var debtorIndex = 0;
    var creditorIndex = 0;

    while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
      final debtor = debtors[debtorIndex];
      final creditor = creditors[creditorIndex];
      final amount = debtor.value < creditor.value ? debtor.value : creditor.value;

      settlements.add(
        SettlementModel(
          from: debtor.key,
          to: creditor.key,
          amount: amount,
        ),
      );

      debtors[debtorIndex] = MapEntry(debtor.key, debtor.value - amount);
      creditors[creditorIndex] = MapEntry(
        creditor.key,
        creditor.value - amount,
      );

      if (debtors[debtorIndex].value <= 0.01) {
        debtorIndex++;
      }

      if (creditors[creditorIndex].value <= 0.01) {
        creditorIndex++;
      }
    }

    return settlements;
  }
}
