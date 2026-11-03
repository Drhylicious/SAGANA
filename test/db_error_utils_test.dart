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

    test('stock can never go below zero: the 23514 guard is readable', () {
      const e = PostgrestException(
        message:
            'new row for relation "cooperative_inventory" violates check constraint "cooperative_inventory_quantity_non_negative"',
        code: '23514',
      );
      expect(
        readableDatabaseMessage(e),
        'There is not enough stock for this. Stock on hand cannot go below zero.',
      );
    });

    test('a loan takes an item from stock only once: the unique index is readable', () {
      const e = PostgrestException(
        message:
            'duplicate key value violates unique constraint "uq_inventory_loan_issue_once"',
        code: '23505',
      );
      expect(
        readableDatabaseMessage(e),
        'This item was already taken from stock for this loan.',
      );
    });

    test('another check violation stays technical', () {
      const e = PostgrestException(
        message: 'violates check constraint "some_other_check"',
        code: '23514',
      );
      expect(readableDatabaseMessage(e), isNull);
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
