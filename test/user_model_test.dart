import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/models/user_model.dart';

void main() {
  group('UserModel Strict Validation & Normalization Unit Tests', () {
    test('isValidUsername enforces strict constraints', () {
      // Valid usernames: 3-20 chars, lowercase alphanumeric and _ only
      expect(UserModel.isValidUsername('neel_07'), isTrue);
      expect(UserModel.isValidUsername('alex_99'), isTrue);
      expect(UserModel.isValidUsername('abc'), isTrue);
      expect(UserModel.isValidUsername('abcdefghijklmnopqrst'), isTrue); // 20 chars

      // Invalid: null / empty
      expect(UserModel.isValidUsername(null), isFalse);
      expect(UserModel.isValidUsername(''), isFalse);

      // Invalid: contains spaces
      expect(UserModel.isValidUsername('neel 07'), isFalse);
      expect(UserModel.isValidUsername(' neel'), isFalse);
      expect(UserModel.isValidUsername('neel '), isFalse);

      // Invalid: contains @ symbol
      expect(UserModel.isValidUsername('@neel_07'), isFalse);
      expect(UserModel.isValidUsername('neel@07'), isFalse);

      // Invalid: length < 3
      expect(UserModel.isValidUsername('ab'), isFalse);
      expect(UserModel.isValidUsername('a'), isFalse);

      // Invalid: length > 20
      expect(UserModel.isValidUsername('abcdefghijklmnopqrstu'), isFalse); // 21 chars

      // Invalid: special characters (dots, dashes, symbols)
      expect(UserModel.isValidUsername('neel.07'), isFalse);
      expect(UserModel.isValidUsername('neel-07'), isFalse);
      expect(UserModel.isValidUsername('neel!07'), isFalse);

      // Invalid: uppercase letters
      expect(UserModel.isValidUsername('Neel_07'), isFalse);
    });

    test('normalizeUsername trims, lowercases, and strips all @ and spaces', () {
      expect(UserModel.normalizeUsername('  @Neel_07  '), 'neel_07');
      expect(UserModel.normalizeUsername('@@User_Test'), 'user_test');
      expect(UserModel.normalizeUsername('plain_username'), 'plain_username');
      expect(UserModel.normalizeUsername('user @ name'), 'username');
    });

    test('generateFallbackUsername creates sanitized 3-20 char username matching regex', () {
      final u1 = UserModel.generateFallbackUsername('john.doe@example.com', 'John Doe');
      expect(UserModel.isValidUsername(u1), isTrue);
      expect(u1.length >= 3 && u1.length <= 20, isTrue);

      final u2 = UserModel.generateFallbackUsername('a@domain.com', null);
      expect(UserModel.isValidUsername(u2), isTrue);
      expect(u2.length >= 3 && u2.length <= 20, isTrue);

      final u3 = UserModel.generateFallbackUsername(null, 'VeryLongNameExceedingTwentyCharacters');
      expect(UserModel.isValidUsername(u3), isTrue);
      expect(u3.length <= 20, isTrue);

      final u4 = UserModel.generateFallbackUsername(null, null);
      expect(UserModel.isValidUsername(u4), isTrue);
      expect(u4.length >= 3 && u4.length <= 20, isTrue);
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
