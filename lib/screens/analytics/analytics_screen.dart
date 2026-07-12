// import 'package:fl_chart/fl_chart.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../services/analytics_service.dart';
import '../../core/theme/app_theme.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key, required this.groups});

  final List<GroupModel> groups;

  @override
  Widget build(BuildContext context) {
    final totalExpense = AnalyticsService.getTotalExpense(groups);

    final categoryTotals = AnalyticsService.getCategoryTotals(groups);

    final monthlyTotals = AnalyticsService.getMonthlyTotals(groups);

    final highestSpender = AnalyticsService.getHighestSpender(groups);

    final List<Color> chartColors = [
      Colors.blue,
      Colors.red,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.pink,
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        title: const Text(
          'Analytics',

          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            /// TOTAL EXPENSE
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: AppTheme.primary,

                borderRadius: BorderRadius.circular(20),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const Text(
                    'Total Expense',

                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Rs. ${totalExpense.toStringAsFixed(0)}',

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// CATEGORY TITLE
            const Text(
              'Category Breakdown',

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 350,

              child: SfCircularChart(
                legend: const Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                ),

                tooltipBehavior: TooltipBehavior(enable: true),

                series: <CircularSeries>[
                  DoughnutSeries<MapEntry<String, double>, String>(
                    dataSource: categoryTotals.entries.toList(),

                    xValueMapper: (data, _) => data.key,

                    yValueMapper: (data, _) => data.value,

                    pointColorMapper: (data, index) =>
                        chartColors[index % chartColors.length],

                    dataLabelMapper: (data, _) =>
                        "₹${data.value.toStringAsFixed(0)}",

                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      textStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    innerRadius: "45%",

                    radius: "95%",

                    explode: true,

                    explodeIndex: 0,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// MONTHLY TOTALS
            const Text(
              'Monthly Expenses',

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 15),

            SizedBox(
              height: 300,

              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(),

                tooltipBehavior: TooltipBehavior(enable: true),

                series: [
                  ColumnSeries<MapEntry<String, double>, String>(
                    dataSource: monthlyTotals.entries.toList(),

                    xValueMapper: (data, _) => data.key,

                    yValueMapper: (data, _) => data.value,

                    borderRadius: BorderRadius.circular(10),

                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// HIGHEST SPENDER
            const Text(
              'Highest Spender',

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 15),

            Card(
              elevation: 0,

              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.primary,

                  child: Icon(Icons.person, color: Colors.white),
                ),

                title: Text(highestSpender.key),

                subtitle: const Text('Top Contributor'),

                trailing: Text(
                  'Rs. ${highestSpender.value.toStringAsFixed(0)}',

                  style: const TextStyle(
                    fontWeight: FontWeight.bold,

                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
