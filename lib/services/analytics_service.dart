import '../models/group_model.dart';

class AnalyticsService {

  static double getTotalExpense(
    List<GroupModel> groups,
  ) {

    double total = 0;

    for (final group in groups) {
      total += group.totalExpense;
    }

    return total;
  }

  static Map<String, double>
      getCategoryTotals(
    List<GroupModel> groups,
  ) {

    final Map<String, double>
        categoryTotals = {};

    for (final group in groups) {

      for (final expense
          in group.expenses) {

        categoryTotals[
                expense.category] =
            (categoryTotals[
                        expense
                            .category] ??
                    0) +
                expense.amount;
      }
    }

    return categoryTotals;
  }

  static Map<String, double>
      getMonthlyTotals(
    List<GroupModel> groups,
  ) {

    final Map<String, double>
        monthlyTotals = {};

    for (final group in groups) {

      for (final expense
          in group.expenses) {

        final month =
            '${expense.date.month}/${expense.date.year}';

        monthlyTotals[month] =
            (monthlyTotals[month] ??
                    0) +
                expense.amount;
      }
    }

    return monthlyTotals;
  }

  static MapEntry<String, double>
      getHighestSpender(
    List<GroupModel> groups,
  ) {

    final Map<String, double>
        spenders = {};

    for (final group in groups) {

      for (final expense
          in group.expenses) {

        spenders[expense.paidBy] =
            (spenders[
                        expense
                            .paidBy] ??
                    0) +
                expense.amount;
      }
    }

    if (spenders.isEmpty) {
      return const MapEntry(
        'No Data',
        0,
      );
    }

    return spenders.entries.reduce(
      (a, b) =>
          a.value > b.value ? a : b,
    );
  }
}