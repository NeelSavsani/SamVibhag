import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupMembershipException implements Exception {
  const GroupMembershipException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Performs group leave and deletion using the signed-in user's Firestore
/// client, so these actions do not require a paid Cloud Functions plan.
class GroupMembershipService {
  GroupMembershipService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  static const int _activityDeleteBatchSize = 400;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const GroupMembershipException('Please sign in again and retry.');
    }

    final groupRef = _firestore.collection('groups').doc(groupId);
    final userRef = _firestore.collection('users').doc(user.uid);
    final activityRef = groupRef.collection('activities').doc();

    try {
      await _firestore.runTransaction((transaction) async {
        final groupSnapshot = await transaction.get(groupRef);
        final userSnapshot = await transaction.get(userRef);
        if (!groupSnapshot.exists) {
          throw const GroupMembershipException(
            'This group is no longer available.',
          );
        }

        final data = groupSnapshot.data()!;
        _ensureNotDeleting(data);
        final members = _readStringList(data, 'members');
        final memberUids = _alignedMemberUids(data, members);
        final uidIndex = memberUids.indexOf(user.uid);
        if (uidIndex < 0 || memberUids.lastIndexOf(user.uid) != uidIndex) {
          throw const GroupMembershipException(
            'You are not a registered member of this group.',
          );
        }

        final memberName = members[uidIndex];
        final offlineMembers = _readStringList(data, 'offlineMembers');
        if (offlineMembers.contains(memberName)) {
          throw const GroupMembershipException(
            'This group has duplicate member names that make the offline member record ambiguous. Ask the owner to review them.',
          );
        }

        final ownerUid = _ownerUid(data);
        final isOwnerLeaving = ownerUid == user.uid;
        final nextMembers = List<String>.from(members)..removeAt(uidIndex);
        final nextMemberUids = List<String>.from(memberUids)
          ..removeAt(uidIndex);

        var nextOwnerUid = ownerUid;
        if (isOwnerLeaving) {
          nextOwnerUid = nextMemberUids.firstWhere(
            (memberUid) => memberUid.trim().isNotEmpty,
            orElse: () => '',
          );
          if (nextOwnerUid.isEmpty) {
            throw const GroupMembershipException(
              'Add a registered member before leaving so the group has an owner.',
            );
          }
        }

        final profile = userSnapshot.data() ?? <String, dynamic>{};
        final profileEmail = (profile['email'] as String?) ?? user.email ?? '';
        final profileUsername = (profile['username'] as String?) ?? '';
        final actorName =
            (profile['fullName'] as String?)?.trim().isNotEmpty == true
            ? (profile['fullName'] as String).trim()
            : ((profile['displayName'] as String?)?.trim().isNotEmpty == true
                  ? (profile['displayName'] as String).trim()
                  : (user.displayName?.trim().isNotEmpty == true
                        ? user.displayName!.trim()
                        : memberName));

        final updates = <String, dynamic>{
          'members': nextMembers,
          'memberUids': nextMemberUids,
          'memberEmails': _withoutKnownValue(
            data,
            'memberEmails',
            profileEmail,
          ),
          'memberUsernames': _withoutKnownValue(
            data,
            'memberUsernames',
            profileUsername,
          ),
          'offlineMembers': offlineMembers,
          'lastUpdatedBy': user.uid,
          'lastUpdatedByName': actorName,
        };
        if (isOwnerLeaving) updates['ownerUid'] = nextOwnerUid;

        transaction.update(groupRef, updates);
        transaction.set(activityRef, {
          'id': activityRef.id,
          'groupId': groupId,
          'type': 'member_left',
          'performedByUid': user.uid,
          'performedByName': actorName,
          'message': '$actorName left the group',
          'timestamp': FieldValue.serverTimestamp(),
          'metadata': {
            'memberUid': user.uid,
            if (isOwnerLeaving) 'newOwnerUid': nextOwnerUid,
          },
        });
      });
    } on GroupMembershipException {
      rethrow;
    } on FirebaseException catch (error) {
      throw GroupMembershipException(_messageFor(error.code));
    } catch (_) {
      throw const GroupMembershipException(
        'Could not leave this group. Please try again.',
      );
    }
  }

  Future<void> deleteGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const GroupMembershipException('Please sign in again and retry.');
    }

    final groupRef = _firestore.collection('groups').doc(groupId);
    try {
      // This owner-only marker prevents new activity writes while history is
      // removed. If interrupted, the same owner can call delete again.
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(groupRef);
        if (!snapshot.exists) {
          throw const GroupMembershipException(
            'This group is no longer available.',
          );
        }
        final data = snapshot.data()!;
        if (_ownerUid(data) != user.uid) {
          throw const GroupMembershipException(
            'Only the current group owner can delete it.',
          );
        }
        final existingLock = data['deletionInProgressBy']?.toString();
        if (existingLock != null &&
            existingLock.isNotEmpty &&
            existingLock != user.uid) {
          throw const GroupMembershipException(
            'Group deletion is already in progress.',
          );
        }
        transaction.update(groupRef, {
          'deletionInProgressBy': user.uid,
          'deletionStartedAt': FieldValue.serverTimestamp(),
        });
      });

      final activities = groupRef.collection('activities');
      while (true) {
        final page = await activities
            .orderBy(FieldPath.documentId)
            .limit(_activityDeleteBatchSize)
            .get();
        if (page.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final activity in page.docs) {
          batch.delete(activity.reference);
        }
        await batch.commit();
      }

      // Expenses and settlements are embedded in the group document; deleting
      // this final document removes those records together with the group.
      await groupRef.delete();
    } on GroupMembershipException {
      rethrow;
    } on FirebaseException catch (error) {
      throw GroupMembershipException(_messageFor(error.code));
    } catch (_) {
      throw const GroupMembershipException(
        'Could not delete this group. You can retry safely.',
      );
    }
  }

  List<String> _readStringList(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value == null) return <String>[];
    if (value is! List || value.any((item) => item is! String)) {
      throw const GroupMembershipException(
        'This group has inconsistent member records. Ask the owner to review them.',
      );
    }
    return value.cast<String>();
  }

  List<String> _alignedMemberUids(
    Map<String, dynamic> data,
    List<String> members,
  ) {
    final uids = _readStringList(data, 'memberUids');
    if (members.length == uids.length) return uids;

    final offlineMembers = _readStringList(data, 'offlineMembers');
    final offlineSet = offlineMembers.toSet();
    if (offlineSet.length != offlineMembers.length ||
        offlineSet.any((name) => !members.contains(name)) ||
        members.length - offlineSet.length != uids.length) {
      throw const GroupMembershipException(
        'This group has inconsistent member records. Ask the owner to review them.',
      );
    }

    var uidIndex = 0;
    return members.map((name) {
      if (offlineSet.contains(name)) return '';
      if (uidIndex >= uids.length) {
        throw const GroupMembershipException(
          'This group has inconsistent member records. Ask the owner to review them.',
        );
      }
      return uids[uidIndex++];
    }).toList();
  }

  String _ownerUid(Map<String, dynamic> data) {
    final ownerUid = data['ownerUid']?.toString().trim();
    if (ownerUid?.isNotEmpty == true) return ownerUid!;
    return data['createdBy']?.toString().trim() ?? '';
  }

  List<String> _withoutKnownValue(
    Map<String, dynamic> data,
    String field,
    String value,
  ) {
    final values = _readStringList(data, field);
    if (value.trim().isEmpty) return values;
    return values
        .where((item) => item.toLowerCase() != value.toLowerCase())
        .toList();
  }

  void _ensureNotDeleting(Map<String, dynamic> data) {
    if (data['deletionInProgressBy'] != null) {
      throw const GroupMembershipException(
        'This group is being deleted and cannot be changed.',
      );
    }
  }

  String _messageFor(String code) {
    switch (code) {
      case 'permission-denied':
        return 'You do not have permission to perform this group action.';
      case 'not-found':
        return 'This group is no longer available.';
      case 'failed-precondition':
        return 'This group’s member records need the owner’s attention before this action can be completed.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The group service is unavailable. Please try again shortly.';
      default:
        return 'Could not complete this group action. Please try again.';
    }
  }
}
