class ExpenseModel {
  final String title;
  final double amount;
  final String paidBy;
  final List<String> splitBetween;
  final DateTime date;
  final String category;

  /// equal / custom
  final String splitType;

  /// Example:
  /// {
  ///   "Neel": 500,
  ///   "Abhishek": 300
  /// }
  final Map<String, double> customSplits;

  ExpenseModel({
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.splitBetween,
    required this.date,
    required this.category,
    required this.splitType,
    required this.customSplits,
  });

  factory ExpenseModel.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    return ExpenseModel(
      title: map['title'] as String,

      amount:
          (map['amount'] as num).toDouble(),

      paidBy: map['paidBy'] as String,

      splitBetween: List<String>.from(
        map['splitBetween'] as List,
      ),

      date: DateTime.parse(
        map['date'] as String,
      ),

      category:
          map['category'] as String? ??
              'Other',

      splitType:
          map['splitType'] as String? ??
              'equal',

      customSplits:
          Map<String, double>.from(
        (map['customSplits'] ?? {}).map(
          (key, value) => MapEntry(
            key.toString(),
            (value as num).toDouble(),
          ),
        ),
      ),
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
      'splitType': splitType,
      'customSplits': customSplits,
    };
  }
}