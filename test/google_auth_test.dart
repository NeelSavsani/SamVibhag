import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/models/user_model.dart';

void main() {
  group('Google Auth User Model & Username Provisioning Tests', () {
    test('generateFallbackUsername creates valid handles for Google profiles', () {
      // Common Google account formats
      final u1 = UserModel.generateFallbackUsername('neel.savsani@gmail.com', 'Neel Savsani');
      expect(UserModel.isValidUsername(u1), isTrue);
      expect(u1.contains('@'), isFalse);
      expect(u1.contains(' '), isFalse);
      expect(u1.length >= 3 && u1.length <= 20, isTrue);

      final u2 = UserModel.generateFallbackUsername('alexander.hamilton.1789@gmail.com', 'Alexander Hamilton');
      expect(UserModel.isValidUsername(u2), isTrue);
      expect(u2.length <= 20, isTrue);

      final u3 = UserModel.generateFallbackUsername('john@example.com', null);
      expect(UserModel.isValidUsername(u3), isTrue);

      final u4 = UserModel.generateFallbackUsername(null, 'User 123');
      expect(UserModel.isValidUsername(u4), isTrue);
    });

    test('normalizeUsername cleans Google profile inputs', () {
      expect(UserModel.normalizeUsername('  Google_User  '), 'google_user');
      expect(UserModel.normalizeUsername('@google_user_99'), 'google_user_99');
      expect(UserModel.normalizeUsername('google user'), 'googleuser');
    });

    test('Google user profile mapping structure', () {
      final googleUserDoc = {
        'uid': 'google_uid_123',
        'displayName': 'John Doe',
        'email': 'john.doe@gmail.com',
        'currency': 'INR',
        'countryCode': '+91',
        'username': 'john_doe',
        'usernameSearch': 'john_doe',
      };

      final userModel = UserModel.fromMap(googleUserDoc);
      expect(userModel.uid, 'google_uid_123');
      expect(userModel.displayName, 'John Doe');
      expect(userModel.email, 'john.doe@gmail.com');
      expect(userModel.username, 'john_doe');
      expect(userModel.usernameSearch, 'john_doe');
    });
  });
}
