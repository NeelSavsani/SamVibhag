import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/services/user_service.dart';

void main() {
  group('UserService.profileHasPhoneNumber', () {
    test('treats absent, null, and whitespace values as missing', () {
      expect(UserService.profileHasPhoneNumber(null), isFalse);
      expect(UserService.profileHasPhoneNumber({}), isFalse);
      expect(UserService.profileHasPhoneNumber({'phoneNumber': null}), isFalse);
      expect(
        UserService.profileHasPhoneNumber({'phoneNumber': '   '}),
        isFalse,
      );
    });

    test('does not treat a country prefix alone as a phone number', () {
      expect(
        UserService.profileHasPhoneNumber({
          'phoneNumber': '+91',
          'countryCode': '+91',
        }),
        isFalse,
      );
    });

    test('accepts the saved phoneNumber field with its country prefix', () {
      expect(
        UserService.profileHasPhoneNumber({
          'phoneNumber': '+91 98765 43210',
          'countryCode': '+91',
        }),
        isTrue,
      );
    });

    test('supports the existing legacy phone field', () {
      expect(
        UserService.profileHasPhoneNumber({'phone': '9876543210'}),
        isTrue,
      );
    });
  });
}
