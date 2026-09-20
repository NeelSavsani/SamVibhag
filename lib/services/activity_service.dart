import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/group_activity_model.dart';
import '../models/group_model.dart';

class ActivityService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Set<String> _backfilledGroupIds = {};

  ActivityService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static final ActivityService instance = ActivityService();

  /// Logs an immutable audit activity event to `groups/{groupId}/activities`.
  Future<void> logGroupActivity({
    required String groupId,
    required String type,
    required String message,
    Map<String, dynamic>? metadata,
    String? performedByUid,
    String? performedByName,
    DateTime? timestamp,
  }) async {
    if (groupId.trim().isEmpty) return;

    try {
      final currentUser = _auth.currentUser;
      final effectiveUid = performedByUid ?? currentUser?.uid ?? 'unknown';

      String effectiveName = performedByName ?? '';
      if (effectiveName.isEmpty) {
        if (currentUser != null) {
          if (currentUser.displayName != null && currentUser.displayName!.trim().isNotEmpty) {
            effectiveName = currentUser.displayName!.trim();
          } else if (currentUser.email != null && currentUser.email!.isNotEmpty) {
            effectiveName = currentUser.email!.split('@').first;
          }
        }
      }
      if (effectiveName.isEmpty) {
        effectiveName = 'User';
      }

      final activityDocRef = _firestore
          .collection('groups')
          .doc(groupId)
          .collection('activities')
          .doc();

      final data = <String, dynamic>{
        'id': activityDocRef.id,
        'groupId': groupId,
        'type': type,
        'performedByUid': effectiveUid,
        'performedByName': effectiveName,
        'message': message,
        'timestamp': timestamp != null
            ? Timestamp.fromDate(timestamp)
            : FieldValue.serverTimestamp(),
      };
      if (metadata != null) {
        data['metadata'] = metadata;
      }

      await activityDocRef.set(data);

      debugPrint('Activity logged: [$type] in group $groupId -> $message');
    } catch (e, st) {
      debugPrint('ActivityService.logGroupActivity note (non-fatal): $e\n$st');
    }
  }

  /// Retroactive historical activity backfill for existing groups.
  /// Idempotently reconstructs group_created, expense_created, and settlement_recorded
  /// using batched writes so no duplicate events are created.
  Future<void> ensureHistoricalActivitiesLogged(GroupModel group) async {
    if (group.id.trim().isEmpty) return;
    if (_backfilledGroupIds.contains(group.id)) return;

    try {
      final activitiesCol = _firestore
          .collection('groups')
          .doc(group.id)
          .collection('activities');

      final existingDocs = await activitiesCol.get();

      bool hasGroupCreated = false;
      final existingExpenseIds = <String>{};
      final existingSettlementIds = <String>{};

      for (final doc in existingDocs.docs) {
        final data = doc.data();
        final type = data['type'] as String?;
        if (type == GroupActivity.typeGroupCreated) {
          hasGroupCreated = true;
        }

        if (data['metadata'] is Map) {
          final meta = data['metadata'] as Map;
          if (meta['expenseId'] != null) {
            existingExpenseIds.add(meta['expenseId'].toString());
          }
          if (meta['settlementId'] != null) {
            existingSettlementIds.add(meta['settlementId'].toString());
          }
        }
        if (doc.id.startsWith('hist_exp_')) {
          existingExpenseIds.add(doc.id.replaceFirst('hist_exp_', ''));
        }
        if (doc.id.startsWith('hist_stl_')) {
          existingSettlementIds.add(doc.id.replaceFirst('hist_stl_', ''));
        }
      }

      final batch = _firestore.batch();
      int queuedWrites = 0;

      // 1. Group Created Backfill
      if (!hasGroupCreated) {
        final creatorUid = group.memberUids.isNotEmpty ? group.memberUids.first : '';
        final creatorName = group.members.isNotEmpty ? group.members.first : 'Admin';
        final docRef = activitiesCol.doc('hist_created_${group.id}');
        batch.set(docRef, {
          'id': docRef.id,
          'groupId': group.id,
          'type': GroupActivity.typeGroupCreated,
          'performedByUid': creatorUid,
          'performedByName': creatorName,
          'message': '$creatorName created group "${group.groupName}"',
          'timestamp': Timestamp.fromDate(group.createdAt),
          'metadata': {
            'initialMembers': group.members,
            'groupType': group.description.isNotEmpty ? group.description : 'General',
            'isBackfilled': true,
          },
        });
        queuedWrites++;
      }

      // 2. Existing Expenses Backfill
      for (final expense in group.expenses) {
        if (!existingExpenseIds.contains(expense.id)) {
          final expDocRef = activitiesCol.doc('hist_exp_${expense.id}');
          batch.set(expDocRef, {
            'id': expDocRef.id,
            'groupId': group.id,
            'type': GroupActivity.typeExpenseCreated,
            'performedByUid': '',
            'performedByName': expense.paidBy,
            'message': '${expense.paidBy} added ₹${expense.amount.toStringAsFixed(0)} for "${expense.title}"',
            'timestamp': Timestamp.fromDate(expense.date),
            'metadata': {
              'expenseId': expense.id,
              'title': expense.title,
              'amount': expense.amount,
              'paidBy': expense.paidBy,
              'category': expense.category,
              'splitBetween': expense.splitBetween,
              'splitType': expense.splitType,
              'isBackfilled': true,
            },
          });
          queuedWrites++;
        }
      }

      // 3. Existing Settlements Backfill
      for (final settlement in group.recordedSettlements) {
        if (!existingSettlementIds.contains(settlement.id)) {
          final stlDocRef = activitiesCol.doc('hist_stl_${settlement.id}');
          batch.set(stlDocRef, {
            'id': stlDocRef.id,
            'groupId': group.id,
            'type': GroupActivity.typeSettlementRecorded,
            'performedByUid': '',
            'performedByName': settlement.fromUser,
            'message': '${settlement.fromUser} settled ₹${settlement.amount.toStringAsFixed(0)} with ${settlement.toUser}',
            'timestamp': Timestamp.fromDate(settlement.settledAt ?? group.createdAt),
            'metadata': {
              'settlementId': settlement.id,
              'fromUser': settlement.fromUser,
              'toUser': settlement.toUser,
              'amount': settlement.amount,
              'isBackfilled': true,
            },
          });
          queuedWrites++;
        }
      }

      if (queuedWrites > 0) {
        await batch.commit();
        debugPrint('Committed $queuedWrites historical backfill activity records for group ${group.id}');
      }

      _backfilledGroupIds.add(group.id);
    } catch (e, st) {
      debugPrint('ensureHistoricalActivitiesLogged note (non-fatal): $e\n$st');
    }
  }

  /// Real-time stream of group activity events, ordered newest first.
  Stream<List<GroupActivity>> getGroupActivitiesStream(String groupId) {
    if (groupId.trim().isEmpty) {
      return Stream.value([]);
    }

    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('activities')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return GroupActivity.fromMap(doc.data(), doc.id);
          }).toList();
        })
        .handleError((error) {
          debugPrint('ActivityService getGroupActivitiesStream note (non-fatal): $error');
          return <GroupActivity>[];
        });
  }
}
