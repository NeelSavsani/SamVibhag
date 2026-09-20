import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GroupActivity {
  final String id;
  final String groupId;
  final String type; // expense_created, expense_updated, expense_deleted, settlement_recorded, settlement_undone
  final String performedByUid;
  final String performedByName;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const GroupActivity({
    required this.id,
    required this.groupId,
    required this.type,
    required this.performedByUid,
    required this.performedByName,
    required this.message,
    required this.timestamp,
    this.metadata,
  });

  static const String typeGroupCreated = 'group_created';
  static const String typeMemberAdded = 'member_added';
  static const String typeExpenseCreated = 'expense_created';
  static const String typeExpenseUpdated = 'expense_updated';
  static const String typeExpenseDeleted = 'expense_deleted';
  static const String typeSettlementRecorded = 'settlement_recorded';
  static const String typeSettlementUndone = 'settlement_undone';

  factory GroupActivity.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return GroupActivity(
      id: id,
      groupId: (map['groupId'] as String?) ?? '',
      type: (map['type'] as String?) ?? typeExpenseCreated,
      performedByUid: (map['performedByUid'] as String?) ?? '',
      performedByName: (map['performedByName'] as String?) ?? 'User',
      message: (map['message'] as String?) ?? '',
      timestamp: parseDate(map['timestamp']),
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'type': type,
      'performedByUid': performedByUid,
      'performedByName': performedByName,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// User-friendly label for activity type
  String get typeLabel {
    switch (type) {
      case typeGroupCreated:
        return 'Group Created';
      case typeMemberAdded:
        return 'Member Added';
      case typeExpenseCreated:
        return 'Expense Added';
      case typeExpenseUpdated:
        return 'Expense Edited';
      case typeExpenseDeleted:
        return 'Expense Deleted';
      case typeSettlementRecorded:
        return 'Settlement Recorded';
      case typeSettlementUndone:
        return 'Settlement Undone';
      default:
        return 'Activity';
    }
  }

  /// Corresponding icon for activity type
  IconData get iconData {
    switch (type) {
      case typeGroupCreated:
        return Icons.group_add_rounded;
      case typeMemberAdded:
        return Icons.person_add_alt_1_rounded;
      case typeExpenseCreated:
        return Icons.receipt_long_rounded;
      case typeExpenseUpdated:
        return Icons.edit_note_rounded;
      case typeExpenseDeleted:
        return Icons.delete_outline_rounded;
      case typeSettlementRecorded:
        return Icons.check_circle_outline_rounded;
      case typeSettlementUndone:
        return Icons.undo_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  /// Accent color based on activity type
  Color get color {
    switch (type) {
      case typeGroupCreated:
        return const Color(0xFF0D9488); // Teal
      case typeMemberAdded:
        return const Color(0xFF4F46E5); // Indigo
      case typeExpenseCreated:
        return const Color(0xFF2563EB); // Blue
      case typeExpenseUpdated:
        return const Color(0xFFD97706); // Amber
      case typeExpenseDeleted:
        return const Color(0xFFEF4444); // Red Accent
      case typeSettlementRecorded:
        return const Color(0xFF10B981); // Emerald Green
      case typeSettlementUndone:
        return const Color(0xFFEA580C); // Deep Orange
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  /// Formatted relative or friendly timestamp
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60 && difference.inSeconds >= 0) {
      return 'Just now';
    } else if (difference.inMinutes < 60 && difference.inMinutes >= 0) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24 && now.day == timestamp.day && now.month == timestamp.month && now.year == timestamp.year) {
      final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = timestamp.hour >= 12 ? 'PM' : 'AM';
      return 'Today at $hour:$minute $period';
    } else if (difference.inDays < 2 && now.subtract(const Duration(days: 1)).day == timestamp.day) {
      final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = timestamp.hour >= 12 ? 'PM' : 'AM';
      return 'Yesterday at $hour:$minute $period';
    } else {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = months[timestamp.month - 1];
      final day = timestamp.day;
      final year = timestamp.year;
      final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = timestamp.hour >= 12 ? 'PM' : 'AM';
      return '$month $day, $year, $hour:$minute $period';
    }
  }
}
