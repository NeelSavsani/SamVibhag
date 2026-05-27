class ExpenseModel {
  final String title;
  final double amount;
  final String paidBy;
  final List<String> splitBetween;
  final DateTime date;

  ExpenseModel({
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.splitBetween,
    required this.date,
  });

  factory ExpenseModel.fromMap(Map<dynamic, dynamic> map) {
    return ExpenseModel(
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      paidBy: map['paidBy'] as String,
      splitBetween: List<String>.from(map['splitBetween'] as List),
      date: DateTime.parse(map['date'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'paidBy': paidBy,
      'splitBetween': splitBetween,
      'date': date.toIso8601String(),
    };
  }
}
