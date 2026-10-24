import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/db_error_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('readableDatabaseMessage', () {
    test('passes through a refusal the database wrote for people (P0001)', () {
      const e = PostgrestException(
        message: 'This phone number is already used by another account.',
        code: 'P0001',
      );
      expect(
        readableDatabaseMessage(e),
        'This phone number is already used by another account.',
      );
    });

    test('turns a duplicate-phone unique violation into a readable message', () {
      const e = PostgrestException(
        message:
            'duplicate key value violates unique constraint "uq_user_information_phone_normalized"',
        code: '23505',
      );
      expect(
        readableDatabaseMessage(e),
        'This phone number is already used by another account.',
      );
    });

    test('turns a duplicate-username unique violation into a readable message', () {
      const e = PostgrestException(
        message:
            'duplicate key value violates unique constraint "uq_user_information_username_ci"',
        code: '23505',
      );
      expect(readableDatabaseMessage(e), 'This username is already taken.');
    });

    test('does not expose technical errors', () {
      expect(
        readableDatabaseMessage(
          const PostgrestException(message: 'permission denied for table x', code: '42501'),
        ),
        isNull,
      );
      expect(readableDatabaseMessage(Exception('boom')), isNull);
    });
  });

  test('friendlyErrorMessage falls back to the exception text', () {
    expect(friendlyErrorMessage(Exception('Something went wrong')), 'Something went wrong');
    expect(
      friendlyErrorMessage(
        const PostgrestException(message: 'Your membership is pending approval.', code: 'P0001'),
      ),
      'Your membership is pending approval.',
    );
  });
}
