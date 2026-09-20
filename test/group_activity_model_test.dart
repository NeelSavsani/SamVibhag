import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/models/group_activity_model.dart';

void main() {
  group('GroupActivity Model Unit Tests', () {
    test('Correctly serializes and deserializes fromMap and toMap', () {
      final now = DateTime.now();
      final activity = GroupActivity(
        id: 'act_123',
        groupId: 'grp_abc',
        type: GroupActivity.typeExpenseCreated,
        performedByUid: 'user_001',
        performedByName: 'Alice',
        message: 'Alice added ₹500 for Dinner',
        timestamp: now,
        metadata: {
          'title': 'Dinner',
          'amount': 500.0,
          'category': 'Food',
        },
      );

      final map = activity.toMap();
      expect(map['id'], 'act_123');
      expect(map['groupId'], 'grp_abc');
      expect(map['type'], 'expense_created');
      expect(map['performedByUid'], 'user_001');
      expect(map['performedByName'], 'Alice');
      expect(map['message'], 'Alice added ₹500 for Dinner');
      expect(map['metadata']['title'], 'Dinner');
      expect(map['metadata']['amount'], 500.0);

      final deserialized = GroupActivity.fromMap(map, 'act_123');
      expect(deserialized.id, 'act_123');
      expect(deserialized.groupId, 'grp_abc');
      expect(deserialized.type, GroupActivity.typeExpenseCreated);
      expect(deserialized.performedByUid, 'user_001');
      expect(deserialized.performedByName, 'Alice');
      expect(deserialized.message, 'Alice added ₹500 for Dinner');
      expect(deserialized.metadata?['title'], 'Dinner');
      expect(deserialized.metadata?['amount'], 500.0);
    });

    test('Safely parses different timestamp formats', () {
      final fixedDate = DateTime(2026, 9, 20, 10, 30);
      final ts = Timestamp.fromDate(fixedDate);

      // Firestore Timestamp
      final fromTimestamp = GroupActivity.fromMap({'timestamp': ts}, 'doc_1');
      expect(fromTimestamp.timestamp.year, 2026);
      expect(fromTimestamp.timestamp.month, 9);
      expect(fromTimestamp.timestamp.day, 20);

      // ISO String
      final fromString = GroupActivity.fromMap({
        'timestamp': '2026-09-20T10:30:00.000Z',
      }, 'doc_2');
      expect(fromString.timestamp.year, 2026);
      expect(fromString.timestamp.month, 9);

      // Null fallback
      final fromNull = GroupActivity.fromMap({}, 'doc_3');
      expect(fromNull.timestamp, isNotNull);
      expect(fromNull.performedByName, 'User');
      expect(fromNull.type, GroupActivity.typeExpenseCreated);
    });

    test('Provides appropriate typeLabel, iconData, and color for each activity type', () {
      final now = DateTime.now();

      final groupCreated = GroupActivity(
        id: '0',
        groupId: 'g',
        type: GroupActivity.typeGroupCreated,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(groupCreated.typeLabel, 'Group Created');
      expect(groupCreated.iconData, Icons.group_add_rounded);
      expect(groupCreated.color, const Color(0xFF0D9488));

      final memberAdded = GroupActivity(
        id: '01',
        groupId: 'g',
        type: GroupActivity.typeMemberAdded,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(memberAdded.typeLabel, 'Member Added');
      expect(memberAdded.iconData, Icons.person_add_alt_1_rounded);
      expect(memberAdded.color, const Color(0xFF4F46E5));

      final created = GroupActivity(
        id: '1',
        groupId: 'g',
        type: GroupActivity.typeExpenseCreated,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(created.typeLabel, 'Expense Added');
      expect(created.iconData, Icons.receipt_long_rounded);
      expect(created.color, const Color(0xFF2563EB));

      final updated = GroupActivity(
        id: '2',
        groupId: 'g',
        type: GroupActivity.typeExpenseUpdated,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(updated.typeLabel, 'Expense Edited');
      expect(updated.iconData, Icons.edit_note_rounded);
      expect(updated.color, const Color(0xFFD97706));

      final deleted = GroupActivity(
        id: '3',
        groupId: 'g',
        type: GroupActivity.typeExpenseDeleted,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(deleted.typeLabel, 'Expense Deleted');
      expect(deleted.iconData, Icons.delete_outline_rounded);
      expect(deleted.color, const Color(0xFFEF4444));

      final settled = GroupActivity(
        id: '4',
        groupId: 'g',
        type: GroupActivity.typeSettlementRecorded,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(settled.typeLabel, 'Settlement Recorded');
      expect(settled.iconData, Icons.check_circle_outline_rounded);
      expect(settled.color, const Color(0xFF10B981));

      final undone = GroupActivity(
        id: '5',
        groupId: 'g',
        type: GroupActivity.typeSettlementUndone,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now,
      );
      expect(undone.typeLabel, 'Settlement Undone');
      expect(undone.iconData, Icons.undo_rounded);
      expect(undone.color, const Color(0xFFEA580C));
    });

    test('formattedTime produces readable output', () {
      final now = DateTime.now();

      final justNow = GroupActivity(
        id: '1',
        groupId: 'g',
        type: GroupActivity.typeExpenseCreated,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now.subtract(const Duration(seconds: 15)),
      );
      expect(justNow.formattedTime, 'Just now');

      final minsAgo = GroupActivity(
        id: '2',
        groupId: 'g',
        type: GroupActivity.typeExpenseCreated,
        performedByUid: 'u',
        performedByName: 'Name',
        message: 'msg',
        timestamp: now.subtract(const Duration(minutes: 10)),
      );
      expect(minsAgo.formattedTime, '10m ago');
    });
  });
}
