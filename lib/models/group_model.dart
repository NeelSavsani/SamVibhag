import 'expense_model.dart';
import 'settlement_model.dart';

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
  List<String> memberUids;
  List<String> memberEmails;

  List<ExpenseModel> expenses;
  
  List<SettlementModel> recordedSettlements;

  GroupModel({
    required this.id,
    required this.groupName,
    required this.members,
    this.memberUids = const [],
    this.memberEmails = const [],
    required this.expenses,
    this.recordedSettlements = const [],

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

    for (final settlement in recordedSettlements) {
      if (settlement.isSettled) {
        balances[settlement.fromUser] = (balances[settlement.fromUser] ?? 0) + settlement.amount;
        balances[settlement.toUser] = (balances[settlement.toUser] ?? 0) - settlement.amount;
      }
    }

    return balances;
  }

  List<SettlementModel> get allSettlements {
    return [...settlements, ...recordedSettlements];
  }

  List<SettlementModel> get settlements {
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

    final result = <SettlementModel>[];

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
        SettlementModel(
          fromUser: debtor.key,
          toUser: creditor.key,
          amount: amount,
          isSettled: false,
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

      memberUids: (map['memberUids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          (map['createdBy'] != null ? [map['createdBy'].toString()] : <String>[]),

      memberEmails: (map['memberEmails'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          <String>[],

      expenses: (map['expenses'] as List<dynamic>?)
              ?.map(
                (expense) =>
                    ExpenseModel.fromMap(expense as Map<dynamic, dynamic>),
              )
              .toList() ??
          <ExpenseModel>[],

      recordedSettlements: (map['recordedSettlements'] as List<dynamic>?)
              ?.map(
                (settlement) =>
                    SettlementModel.fromMap(settlement as Map<dynamic, dynamic>),
              )
              .toList() ??
          <SettlementModel>[],
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
      'memberUids': memberUids,
      'memberEmails': memberEmails,

      'expenses': expenses
          .map(
            (expense) =>
                expense.toMap(),
          )
          .toList(),

      'recordedSettlements': recordedSettlements
          .map(
            (settlement) =>
                settlement.toMap(),
          )
          .toList(),
    };
  }
}