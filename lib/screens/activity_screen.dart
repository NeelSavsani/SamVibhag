import 'package:flutter/material.dart';
import '../../models/group_model.dart';
import 'analytics/analytics_screen.dart';

class ActivityScreen extends StatelessWidget {
  // FIXED: Made groups optional/nullable with a default safe empty list fallback
  const ActivityScreen({super.key, this.groups});

  final List<GroupModel>? groups;

  // Safe getter to guarantee a non-null List everywhere in this class
  List<GroupModel> get _safeGroups => groups ?? const [];

  // Compute calculated values safely using the non-null helper
  double get totalExpensesCombined {
    return _safeGroups.fold<double>(0, (total, group) => total + group.totalExpense);
  }

  int get combinedExpensesCount {
    int total = 0;
    for (final group in _safeGroups) {
      total += group.expenses.length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Activity & Analytics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'View Full Analytics',
            icon: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 26),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AnalyticsScreen(groups: _safeGroups)),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// INTEGRATED ANALYTICS MINI CARD MODULE
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AnalyticsScreen(groups: _safeGroups)),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF0369A1)], 
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withOpacity(0.25),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Analytics Summary',
                            style: TextStyle(
                              color: Colors.white70, 
                              fontSize: 14, 
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Text('Charts', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 10),
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Total Shared Spending',
                        style: TextStyle(
                          color: Colors.white70, 
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rs. ${totalExpensesCombined.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatItem('Monitored Groups', '${_safeGroups.length}'),
                          _buildStatItem('Total Receipts', '$combinedExpensesCount'),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              /// RECENT ACTIVITY FEED BLOCK
              const Text(
                'Recent Activities',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              _safeGroups.isEmpty 
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('No active transaction actions logging yet.'),
                    ),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('Activity logs are fully synchronized.'),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}