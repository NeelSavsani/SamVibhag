import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/group_model.dart';
import 'analytics/analytics_screen.dart';
import '../../models/expense_model.dart'; 

class ActivityLogItem {
  final String message;
  final DateTime date;
  final String category;
  final double displayAmount;
  final String groupName;

  ActivityLogItem({
    required this.message,
    required this.date,
    required this.category,
    required this.displayAmount,
    required this.groupName,
  });
}

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, this.groups});

  final List<GroupModel>? groups;

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  // FIXED: Generates clean statements for every single transaction across all your groups without filtering it out
  List<ActivityLogItem> getActivityLogs(List<GroupModel> activeGroups) {
    List<ActivityLogItem> logs = [];

    for (var group in activeGroups) {
      for (var expense in group.expenses) {
        // Log entry for the person who paid/added the expense
        logs.add(ActivityLogItem(
          message: '${expense.paidBy} added "${expense.title}" of "₹${expense.amount.toStringAsFixed(0)}" in "${group.groupName}"',
          date: expense.date,
          category: expense.category,
          displayAmount: expense.amount,
          groupName: group.groupName,
        ));
      }
    }

    // Sort chronologically, newest activities at the top
    logs.sort((a, b) => b.date.compareTo(a.date));
    return logs;
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food': return Icons.restaurant;
      case 'shopping': return Icons.shopping_bag;
      case 'travel':
      case 'transport': return Icons.directions_car;
      case 'entertainment': return Icons.movie;
      case 'bills': return Icons.receipt_long;
      default: return Icons.monetization_on_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textThemeColor = isDark ? Colors.white : Colors.black87;
    final tileColor = isDark ? const Color(0xFF1E1F24) : const Color(0xFFF1F5F9);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('groups').snapshots(),
      builder: (context, snapshot) {
        List<GroupModel> currentGroups = [];
        
        if (snapshot.hasData && snapshot.data != null) {
          currentGroups = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            
            final List<dynamic> rawExpenses = data['expenses'] as List<dynamic>? ?? [];
            final List<ExpenseModel> parsedExpenses = rawExpenses.map((e) {
              final expData = e as Map<String, dynamic>;
              return ExpenseModel(
                title: expData['title'] ?? '',
                amount: (expData['amount'] as num? ?? 0.0).toDouble(),
                paidBy: expData['paidBy'] ?? '',
                category: expData['category'] ?? 'General',
                date: _parseDateTime(expData['date']),
                splitType: expData['splitType'] ?? 'equal',
                splitBetween: List<String>.from(expData['splitBetween'] ?? []),
                customSplits: Map<String, double>.from(
                  (expData['customSplits'] as Map? ?? {}).map(
                    (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
                  ),
                ),
              );
            }).toList();

            return GroupModel(
              id: doc.id,
              groupName: data['groupName'] ?? '',
              description: data['description'] ?? '',
              avatarPath: data['avatarPath'] ?? '',
              members: List<String>.from(data['members'] ?? []),
              expenses: parsedExpenses,
              createdAt: _parseDateTime(data['createdAt']),
            );
          }).toList();
        }

        double totalExpensesCombined = currentGroups.fold<double>(0, (total, group) => total + group.totalExpense);
        int combinedExpensesCount = currentGroups.fold<int>(0, (total, group) => total + group.expenses.length);
        
        final logs = getActivityLogs(currentGroups);

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 72,
            title: Text(
              'Activity & Analytics',
              style: GoogleFonts.poppins(
                color: textThemeColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconTheme: IconThemeData(color: textThemeColor),
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
                        MaterialPageRoute(builder: (_) => AnalyticsScreen(groups: currentGroups)),
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
                              Text(
                                'Analytics Summary',
                                style: GoogleFonts.poppins(
                                  color: Colors.white70, 
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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
                                    Text('Charts', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 10),
                                  ],
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Total Shared Spending',
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalExpensesCombined.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStatItem('Monitored Groups', '${currentGroups.length}'),
                              _buildStatItem('Total Receipts', '$combinedExpensesCount'),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  /// RECENT ACTIVITY FEED BLOCK
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF83F4EB),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Recent Activities',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textThemeColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (snapshot.connectionState == ConnectionState.waiting && currentGroups.isEmpty)
                    const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                  else if (logs.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                      decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF83F4EB).withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long_outlined, color: Color(0xFF0284C7), size: 34),
                          const SizedBox(height: 12),
                          Text(
                            'No recent activity yet',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textThemeColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'New expenses will appear here.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: textThemeColor.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  else 
                    ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = logs[index];
                          
                          return Card(
                            elevation: 0,
                            margin: EdgeInsets.zero,
                            color: tileColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: const Color(0xFF83F4EB).withOpacity(0.14)),
                            ),
                            shadowColor: Colors.black.withOpacity(0.08),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFF83F4EB).withOpacity(isDark ? 0.16 : 0.24),
                                    child: Icon(
                                      _getCategoryIcon(item.category),
                                      color: const Color(0xFF0284C7),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.message,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: textThemeColor,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              DateFormat("dd MMM, hh:mm a").format(item.date),
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: textThemeColor.withOpacity(0.5),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0284C7).withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                item.category,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 11,
                                                  color: Color(0xFF0284C7),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 4),
        Text(
          val,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
