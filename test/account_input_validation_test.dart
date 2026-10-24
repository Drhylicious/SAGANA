import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/constants/farmer_registration_address.dart';
import 'package:sagana/core/utils/input_validation_utils.dart';

void main() {
  group('normalizePhilippineMobile', () {
    test('accepts the local, +63 and 63 forms and returns 09XXXXXXXXX', () {
      expect(normalizePhilippineMobile('09171234567'), '09171234567');
      expect(normalizePhilippineMobile('+639171234567'), '09171234567');
      expect(normalizePhilippineMobile('639171234567'), '09171234567');
    });

    test('ignores spaces, dashes, dots and brackets', () {
      expect(normalizePhilippineMobile('+63 917 123 4567'), '09171234567');
      expect(normalizePhilippineMobile('0917-123-4567'), '09171234567');
      expect(normalizePhilippineMobile('(0917) 123.4567'), '09171234567');
    });

    test('rejects anything that is not a Philippine mobile number', () {
      expect(normalizePhilippineMobile(''), isNull);
      expect(normalizePhilippineMobile(null), isNull);
      expect(normalizePhilippineMobile('12345'), isNull);
      expect(normalizePhilippineMobile('0817123456'), isNull); // wrong prefix
      expect(normalizePhilippineMobile('0917123456'), isNull); // too short
      expect(normalizePhilippineMobile('091712345678'), isNull); // too long
      expect(normalizePhilippineMobile('+649171234567'), isNull); // not +63
      expect(normalizePhilippineMobile('abcdefghijk'), isNull);
    });
  });

  group('isValidEmailFormat', () {
    test('accepts well-formed addresses', () {
      expect(isValidEmailFormat('example@gmail.com'), isTrue);
      expect(isValidEmailFormat('first.last+tag@sub.example.co.ph'), isTrue);
      expect(isValidEmailFormat('  padded@example.com  '), isTrue);
    });

    test('rejects malformed addresses', () {
      expect(isValidEmailFormat('examplegmail.com'), isFalse); // no @
      expect(isValidEmailFormat('a@b'), isFalse); // no dot in domain
      expect(isValidEmailFormat('a@b.c'), isFalse); // 1-letter TLD
      expect(isValidEmailFormat('a@b..com'), isFalse); // empty label
      expect(isValidEmailFormat('a@-b.com'), isFalse); // label starts with -
      expect(isValidEmailFormat('@gmail.com'), isFalse);
      expect(isValidEmailFormat('a b@gmail.com'), isFalse);
      expect(isValidEmailFormat(''), isFalse);
      expect(isValidEmailFormat(null), isFalse);
    });
  });

  group('username rules', () {
    test('normalizes by trimming and lower-casing', () {
      expect(normalizeUsername('  DrhyLicious '), 'drhylicious');
    });

    test('accepts 3-30 letters, numbers, dots, underscores and hyphens', () {
      expect(isValidUsernameFormat('drhylicious'), isTrue);
      expect(isValidUsernameFormat('Juan_Dela-Cruz.01'), isTrue); // case-folded
      expect(isValidUsernameFormat('abc'), isTrue);
      expect(isValidUsernameFormat('a' * 30), isTrue);
    });

    test('rejects too short, too long, spaces and @ (which means "email")', () {
      expect(isValidUsernameFormat('ab'), isFalse);
      expect(isValidUsernameFormat('a' * 31), isFalse);
      expect(isValidUsernameFormat('juan dela cruz'), isFalse);
      expect(isValidUsernameFormat('juan@sagana'), isFalse);
      expect(isValidUsernameFormat(''), isFalse);
      expect(isValidUsernameFormat(null), isFalse);
    });
  });

  group('FarmerRegistrationAddress', () {
    test('holds the five fixed values', () {
      expect(FarmerRegistrationAddress.regionName, 'MIMAROPA Region');
      expect(FarmerRegistrationAddress.provinceName, 'Marinduque');
      expect(FarmerRegistrationAddress.cityName, 'Torrijos');
      expect(FarmerRegistrationAddress.barangayName, 'Payanas');
      expect(FarmerRegistrationAddress.postalCode, '4903');
    });

    test('composes the one-line address in the database order', () {
      expect(
        FarmerRegistrationAddress.composeLine(
          houseNo: '12',
          building: 'Blue Bldg',
          street: 'Rizal St',
        ),
        '12, Blue Bldg, Rizal St, Payanas, Torrijos, Marinduque, '
        'MIMAROPA Region, 4903',
      );
    });

    test('leaves out an empty building', () {
      expect(
        FarmerRegistrationAddress.composeLine(
          houseNo: '12',
          building: '  ',
          street: 'Rizal St',
        ),
        '12, Rizal St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
      );
    });
  });

  group('validateLoginIdentifier (sign-in field)', () {
    test('empty is required', () {
      expect(validateLoginIdentifier(null), 'Username or email is required');
      expect(validateLoginIdentifier('   '), 'Username or email is required');
    });

    test('a username is accepted as typed', () {
      expect(validateLoginIdentifier('aldrin'), isNull);
      expect(validateLoginIdentifier('  QA_Buyer1 '), isNull);
    });

    test('anything with @ must be a well-formed email address', () {
      expect(validateLoginIdentifier('abc@'), 'Enter a valid email address');
      expect(validateLoginIdentifier('abc@gmail'), 'Enter a valid email address');
      expect(validateLoginIdentifier('@gmail.com'), 'Enter a valid email address');
      expect(validateLoginIdentifier('manager@sp3.coop'), isNull);
    });
  });
}
