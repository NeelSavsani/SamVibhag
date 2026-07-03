import 'expense_model.dart';

class Settlement {
  final String from;
  final String to;
  final double amount;

  Settlement({
    required this.from,
    required this.to,
    required this.amount,
  });

  factory Settlement.fromMap(Map<dynamic, dynamic> map) {
    return Settlement(
      from: map['from'],
      to: map['to'],
      amount: (map['amount'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'from': from,
      'to': to,
      'amount': amount,
    };
  }
}

class GroupModel {
  final String id;

  String groupName;

  /// NEW
  String description;

  /// Local image path
  String avatarPath;

  /// Group creation date
  DateTime createdAt;

  List<String> members;

  List<ExpenseModel> expenses;

  GroupModel({
    required this.id,
    required this.groupName,
    required this.members,
    required this.expenses,

    this.description = '',
    this.avatarPath = '',

    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get totalExpense {
    return expenses.fold(
      0,
      (sum, expense) => sum + expense.amount,
    );
  }

  Map<String, double> get memberBalances {
    final balances = <String, double>{};

    for (final member in members) {
      balances[member] = 0;
    }

    for (final expense in expenses) {
      balances[expense.paidBy] =
          (balances[expense.paidBy] ?? 0) + expense.amount;

      if (expense.splitType == 'custom') {
        expense.customSplits.forEach((member, amount) {
          balances[member] =
              (balances[member] ?? 0) - amount;
        });
      } else {
        final share =
            expense.amount / expense.splitBetween.length;

        for (final member in expense.splitBetween) {
          balances[member] =
              (balances[member] ?? 0) - share;
        }
      }
    }

    return balances;
  }

  List<Settlement> get settlements {
    final balances =
        Map<String, double>.from(memberBalances);

    final creditors = <MapEntry<String, double>>[];
    final debtors = <MapEntry<String, double>>[];

    balances.forEach((member, balance) {
      if (balance > 0.01) {
        creditors.add(MapEntry(member, balance));
      } else if (balance < -0.01) {
        debtors.add(MapEntry(member, -balance));
      }
    });

    final result = <Settlement>[];

    int i = 0;
    int j = 0;

    while (i < debtors.length &&
        j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];

      final amount =
          debtor.value < creditor.value
              ? debtor.value
              : creditor.value;

      result.add(
        Settlement(
          from: debtor.key,
          to: creditor.key,
          amount: amount,
        ),
      );

      debtors[i] =
          MapEntry(debtor.key, debtor.value - amount);

      creditors[j] = MapEntry(
          creditor.key,
          creditor.value - amount);

      if (debtors[i].value <= 0.01) {
        i++;
      }

      if (creditors[j].value <= 0.01) {
        j++;
      }
    }

    return result;
  }

  factory GroupModel.fromMap(
      Map<dynamic, dynamic> map) {
    return GroupModel(
      id: map['id'] as String,

      groupName: map['groupName'] as String,

      description:
          map['description'] as String? ?? '',

      avatarPath:
          map['avatarPath'] as String? ?? '',

      createdAt: map['createdAt'] == null
          ? DateTime.now()
          : DateTime.parse(
              map['createdAt']),

      members: List<String>.from(
        map['members'],
      ),

      expenses: (map['expenses'] as List)
          .map(
            (expense) =>
                ExpenseModel.fromMap(expense),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,

      'groupName': groupName,

      'description': description,

      'avatarPath': avatarPath,

      'createdAt':
          createdAt.toIso8601String(),

      'members': members,

      'expenses': expenses
          .map(
            (expense) =>
                expense.toMap(),
          )
          .toList(),
    };
  }
}