import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore;

  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Claims or changes a username atomically via a Firestore transaction
  /// on the root `usernames` collection where each document ID is the lowercase username.
  ///
  /// Returns `true` if claimed successfully, `false` if taken by another user.
  Future<bool> claimUsername({
    required String newUsername,
    required String uid,
    String? oldUsername,
  }) async {
    final normalizedNew = UserModel.normalizeUsername(newUsername);
    if (!UserModel.isValidUsername(normalizedNew)) {
      throw ArgumentError(
        'Username "$newUsername" must be 3-20 alphanumeric characters or underscores, with no spaces or @ symbols.',
      );
    }

    final normalizedOld = oldUsername != null && oldUsername.trim().isNotEmpty
        ? UserModel.normalizeUsername(oldUsername)
        : null;

    // If new username is identical to the old username, already held by this user
    if (normalizedOld != null && normalizedOld == normalizedNew) {
      return true;
    }

    final newUsernameRef = _firestore.collection('usernames').doc(normalizedNew);
    final oldUsernameRef = normalizedOld != null
        ? _firestore.collection('usernames').doc(normalizedOld)
        : null;
    final userDocRef = _firestore.collection('users').doc(uid);

    return await _firestore.runTransaction<bool>((transaction) async {
      // 1. Check if new username is already taken
      final newDoc = await transaction.get(newUsernameRef);
      if (newDoc.exists) {
        final existingUid = newDoc.data()?['uid'];
        if (existingUid != uid) {
          // Already claimed by another user
          return false;
        }
      }

      // 2. If user is changing their username, delete the old username document
      if (oldUsernameRef != null) {
        final oldDoc = await transaction.get(oldUsernameRef);
        if (oldDoc.exists && oldDoc.data()?['uid'] == uid) {
          transaction.delete(oldUsernameRef);
        }
      }

      // 3. Claim the new username document atomically
      transaction.set(newUsernameRef, {
        'uid': uid,
        'username': normalizedNew,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Update the user document
      transaction.set(
        userDocRef,
        {
          'username': normalizedNew,
          'usernameSearch': normalizedNew,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return true;
    });
  }

  /// Checks if a username is available in the `usernames` collection.
  Future<bool> isUsernameAvailable(String username, {String? excludeUid}) async {
    final normalized = UserModel.normalizeUsername(username);
    if (!UserModel.isValidUsername(normalized)) return false;

    try {
      final doc = await _firestore.collection('usernames').doc(normalized).get();
      if (!doc.exists) return true;
      if (excludeUid != null && doc.data()?['uid'] == excludeUid) return true;
      return false;
    } catch (_) {
      try {
        final snap = await _firestore
            .collection('users')
            .where('usernameSearch', isEqualTo: normalized)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) return true;
        if (excludeUid != null && snap.docs.first.id == excludeUid) return true;
        return false;
      } catch (_) {
        return true;
      }
    }
  }

  /// Look up user by username using direct point lookup in `usernames`
  /// with fallback to `users` collection query.
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final normalized = UserModel.normalizeUsername(username);
    if (!UserModel.isValidUsername(normalized)) return null;

    // 1. Direct point lookup in usernames collection
    try {
      final usernameDoc = await _firestore.collection('usernames').doc(normalized).get();
      if (usernameDoc.exists && usernameDoc.data()?['uid'] != null) {
        final uid = usernameDoc.data()!['uid'] as String;
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = Map<String, dynamic>.from(userDoc.data()!);
          data['uid'] = uid;
          return data;
        }
      }
    } catch (_) {
      // Fallback to querying users collection if usernames collection read fails
    }

    // 2. Fallback query on users collection
    try {
      final snap = await _firestore
          .collection('users')
          .where('usernameSearch', isEqualTo: normalized)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        final data = Map<String, dynamic>.from(doc.data());
        data['uid'] = doc.id;
        return data;
      }
    } catch (_) {
      // Ignore
    }

    return null;
  }
}
