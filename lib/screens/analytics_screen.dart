import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/group_model.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({
    super.key,
    required this.groups,
  });

  final List<GroupModel> groups;

  @override
  Widget build(BuildContext context) {

    final totalExpense =
        AnalyticsService.getTotalExpense(
      groups,
    );

    final categoryTotals =
        AnalyticsService.getCategoryTotals(
      groups,
    );

    final monthlyTotals =
        AnalyticsService.getMonthlyTotals(
      groups,
    );

    final highestSpender =
        AnalyticsService.getHighestSpender(
      groups,
    );

    return Scaffold(
      backgroundColor:
          Theme.of(context)
              .scaffoldBackgroundColor,

      appBar: AppBar(
        title: const Text(
          'Analytics',

          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            /// TOTAL EXPENSE
            Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: AppTheme.primary,

                borderRadius:
                    BorderRadius.circular(
                  20,
                ),
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  const Text(
                    'Total Expense',

                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Rs. ${totalExpense.toStringAsFixed(0)}',

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// CATEGORY TITLE
            const Text(
              'Category Breakdown',

              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 250,

              child: PieChart(
                PieChartData(
                  sections:
                      categoryTotals.entries.map(
                    (entry) {

                      return PieChartSectionData(
                        value: entry.value,
                        title:
                            '${entry.key}\nRs.${entry.value.toStringAsFixed(0)}',

                        radius: 90,

                        titleStyle:
                            const TextStyle(
                          fontSize: 12,
                          fontWeight:
                              FontWeight.bold,

                          color: Colors.white,
                        ),
                      );
                    },
                  ).toList(),
                ),
              ),
            ),

            const SizedBox(height: 30),

            /// MONTHLY TOTALS
            const Text(
              'Monthly Expenses',

              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            ...monthlyTotals.entries.map(
              (entry) {

                return Card(
                  elevation: 0,

                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_month,
                    ),

                    title: Text(entry.key),

                    trailing: Text(
                      'Rs. ${entry.value.toStringAsFixed(0)}',

                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,

                        color:
                            AppTheme.primary,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 30),

            /// HIGHEST SPENDER
            const Text(
              'Highest Spender',

              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            Card(
              elevation: 0,

              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor:
                      AppTheme.primary,

                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                  ),
                ),

                title: Text(
                  highestSpender.key,
                ),

                subtitle: const Text(
                  'Top Contributor',
                ),

                trailing: Text(
                  'Rs. ${highestSpender.value.toStringAsFixed(0)}',

                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,

                    color:
                        AppTheme.primary,
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