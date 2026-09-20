import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/models/group_model.dart';
import 'package:samvibhag/models/user_model.dart';
import 'package:samvibhag/widgets/add_member_dialog.dart';

void main() {
  group('Add Member Logic & Normalization Tests', () {
    test('Input normalization handles @ prefix, spaces, and casing', () {
      final input1 = '  @Neel_07  ';
      final clean1 = input1.replaceAll('@', '').trim().toLowerCase();
      expect(clean1, 'neel_07');

      final input2 = 'user@example.com';
      final clean2 = input2.replaceAll('@', '').trim().toLowerCase();
      expect(clean2, 'userexample.com');

      final bool looksLikeEmail = input2.contains('@') && input2.contains('.');
      expect(looksLikeEmail, isTrue);

      final normalizedUser = UserModel.normalizeUsername('@Alex_99');
      expect(normalizedUser, 'alex_99');
    });

    test('Identifies already existing members by UID, email, username, or display name', () {
      final group = GroupModel(
        id: 'grp_123',
        groupName: 'Trip to Goa',
        members: ['Alice Smith', 'Bob Jones'],
        memberUids: ['uid_alice_1', 'uid_bob_2'],
        memberEmails: ['alice@example.com', 'bob@example.com'],
        memberUsernames: ['alice_s', 'bob_j'],
        expenses: [],
      );

      // Helper function replicating AddMemberDialog membership check
      bool isUserAlreadyMember(Map<String, dynamic> user, GroupModel grp) {
        final uid = (user['uid'] as String?) ?? '';
        final email = (user['email'] as String? ?? '').toLowerCase().trim();
        final displayName = (user['displayName'] as String?) ?? (user['fullName'] as String?) ?? '';
        final username = (user['username'] as String?)?.toLowerCase().trim() ??
            (user['usernameSearch'] as String?)?.toLowerCase().trim();

        if (uid.isNotEmpty && grp.memberUids.contains(uid)) return true;
        if (email.isNotEmpty && grp.memberEmails.map((e) => e.toLowerCase()).contains(email)) return true;
        if (displayName.isNotEmpty && grp.members.map((m) => m.toLowerCase()).contains(displayName.toLowerCase())) return true;
        if (username != null && username.isNotEmpty && grp.memberUsernames.map((u) => u.toLowerCase()).contains(username)) return true;

        return false;
      }

      // Existing member by UID
      expect(isUserAlreadyMember({'uid': 'uid_alice_1', 'displayName': 'Other'}, group), isTrue);

      // Existing member by Email
      expect(isUserAlreadyMember({'uid': 'new_uid', 'email': 'Bob@example.com'}, group), isTrue);

      // Existing member by Username
      expect(isUserAlreadyMember({'uid': 'new_uid', 'username': 'ALICE_S'}, group), isTrue);

      // Existing member by Display Name
      expect(isUserAlreadyMember({'uid': 'new_uid', 'displayName': 'Bob Jones'}, group), isTrue);

      // New member
      expect(isUserAlreadyMember({
        'uid': 'uid_charlie',
        'email': 'charlie@example.com',
        'username': 'charlie_01',
        'displayName': 'Charlie Brown',
      }, group), isFalse);
    });

    test('AddedMemberResult constructs correctly for registered and offline users', () {
      const reg = AddedMemberResult(
        displayName: 'Charlie Brown',
        uid: 'uid_charlie',
        email: 'charlie@example.com',
        username: 'charlie_01',
        isOffline: false,
      );

      expect(reg.displayName, 'Charlie Brown');
      expect(reg.uid, 'uid_charlie');
      expect(reg.email, 'charlie@example.com');
      expect(reg.username, 'charlie_01');
      expect(reg.isOffline, isFalse);

      const offline = AddedMemberResult(
        displayName: 'Guest Friend',
        isOffline: true,
      );

      expect(offline.displayName, 'Guest Friend');
      expect(offline.uid, isNull);
      expect(offline.email, isNull);
      expect(offline.username, isNull);
      expect(offline.isOffline, isTrue);
    });
  });
}
