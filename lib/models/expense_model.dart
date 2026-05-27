class ExpenseModel {
  final String title;
  final double amount;
  final String paidBy;
  final List<String> splitBetween;
  final DateTime date;
  final String category;

  ExpenseModel({
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.splitBetween,
    required this.date,
    required this.category,
  });

  factory ExpenseModel.fromMap(Map<dynamic, dynamic> map) {
    return ExpenseModel(
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      paidBy: map['paidBy'] as String,
      splitBetween: List<String>.from(map['splitBetween'] as List),
      date: DateTime.parse(map['date'] as String),
      category: map['category'] as String? ?? 'Other',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'paidBy': paidBy,
      'splitBetween': splitBetween,
      'date': date.toIso8601String(),
      'category': category,
    };
  }
}