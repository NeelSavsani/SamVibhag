import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/models/user_model.dart';

void main() {
  group('UserModel Unit Tests', () {
    test('normalizeUsername trims, lowercases, and strips leading @', () {
      expect(UserModel.normalizeUsername('  @Neel_07  '), 'neel_07');
      expect(UserModel.normalizeUsername('@@User.Test'), 'user.test');
      expect(UserModel.normalizeUsername('plain_username'), 'plain_username');
    });

    test('generateFallbackUsername creates sanitized username from email or name', () {
      expect(UserModel.generateFallbackUsername('john.doe@example.com', 'John Doe'), 'john_doe');
      expect(UserModel.generateFallbackUsername('neel+test@domain.com', null), 'neel_test');
      expect(UserModel.generateFallbackUsername(null, 'Alice Wonderland'), 'alice_wonderland');
    });

    test('fromMap and toMap correctly serialize username and usernameSearch', () {
      final map = {
        'uid': 'user_123',
        'email': 'neel@example.com',
        'displayName': 'Neel Savsani',
        'fullName': 'Neel Savsani',
        'username': 'neel_07',
        'usernameSearch': 'neel_07',
        'phoneNumber': '+919876543210',
      };

      final user = UserModel.fromMap(map);
      expect(user.uid, 'user_123');
      expect(user.username, 'neel_07');
      expect(user.usernameSearch, 'neel_07');

      final serialized = user.toMap();
      expect(serialized['username'], 'neel_07');
      expect(serialized['usernameSearch'], 'neel_07');
      expect(serialized['email'], 'neel@example.com');
    });

    test('fromMap uses usernameSearch if username is missing or empty', () {
      final map = {
        'uid': 'user_456',
        'email': 'test@example.com',
        'usernameSearch': 'fallback_search',
      };

      final user = UserModel.fromMap(map);
      expect(user.username, 'fallback_search');
      expect(user.usernameSearch, 'fallback_search');
    });
  });
}
