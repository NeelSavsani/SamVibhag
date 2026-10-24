import 'package:flutter_test/flutter_test.dart';
import 'package:samvibhag/services/user_service.dart';

void main() {
  group('UserService.profileHasPhoneNumber', () {
    test(
      'rejects absent, null, whitespace, and country-prefix-only values',
      () {
        expect(UserService.profileHasPhoneNumber(null), isFalse);
        expect(UserService.profileHasPhoneNumber({}), isFalse);
        expect(
          UserService.profileHasPhoneNumber({'phoneNumber': null}),
          isFalse,
        );
        expect(
          UserService.profileHasPhoneNumber({'phoneNumber': '  '}),
          isFalse,
        );
        expect(
          UserService.profileHasPhoneNumber({
            'phoneNumber': '+91',
            'countryCode': '+91',
          }),
          isFalse,
        );
      },
    );

    test('accepts a saved profile number and the legacy phone field', () {
      expect(
        UserService.profileHasPhoneNumber({
          'phoneNumber': '+91 98765 43210',
          'countryCode': '+91',
        }),
        isTrue,
      );
      expect(
        UserService.profileHasPhoneNumber({'phone': '9876543210'}),
        isTrue,
      );
    });
  });
}
