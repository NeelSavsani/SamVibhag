import 'package:uuid/uuid.dart';

class SettlementModel {
  final String id;
  final String fromUser;
  final String toUser;
  final double amount;
  final bool isSettled;
  final DateTime? settledAt;

  SettlementModel({
    String? id,
    required this.fromUser,
    required this.toUser,
    required this.amount,
    this.isSettled = false,
    this.settledAt,
  }) : id = id ?? const Uuid().v4();

  // Backwards compatibility getters
  String get from => fromUser;
  String get to => toUser;

  factory SettlementModel.fromMap(Map<dynamic, dynamic> map) {
    return SettlementModel(
      id: map['id'] as String?,
      fromUser: map['fromUser'] as String? ?? map['from'] as String? ?? '',
      toUser: map['toUser'] as String? ?? map['to'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      isSettled: map['isSettled'] as bool? ?? false,
      settledAt: map['settledAt'] != null ? DateTime.parse(map['settledAt'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromUser': fromUser,
      'toUser': toUser,
      'amount': amount,
      'isSettled': isSettled,
      'settledAt': settledAt?.toIso8601String(),
    };
  }
}
