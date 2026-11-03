import 'package:supabase_flutter/supabase_flutter.dart';

/// The database's own explanation of why it refused a write, when it wrote one
/// for a person to read; otherwise null.
///
/// Two kinds of database error are written for people:
///  * a refusal raised on purpose (RAISE EXCEPTION, SQLSTATE P0001), such as
///    "This phone number is already used by another account." or "Your
///    membership is pending approval ...";
///  * a duplicate phone number caught by the unique index (SQLSTATE 23505),
///    which can only happen when two people save the same number at the same
///    moment;
///  * the two stock guards (Step 57): stock on hand can never go below zero
///    (SQLSTATE 23514) and one loan deducts an item only once (23505). The app
///    checks these first, so they only show when two people act at once.
/// Anything else (a network failure, a permission error, a bug) is technical
/// and must not be shown to a person as it is.
String? readableDatabaseMessage(Object error) {
  if (error is! PostgrestException) return null;
  // A code word at the start (PHOTO_REQUIRED: ...) is for the app, not the reader.
  final message = error.message.trim().replaceFirst(RegExp(r'^[A-Z_]{4,}: '), '');
  if (error.code == 'P0001' && message.isNotEmpty) return message;

  // The Officer request gate (staff_permission_gate) refuses a write in a
  // module the Officer only has View Only access to. Its message is written for
  // the Officer to read.
  if (error.code == '42501' && message.contains('view-only access')) {
    return message;
  }

  if (error.code == '23514') {
    final detail = '$message ${error.details ?? ''}'.toLowerCase();
    if (detail.contains('cooperative_inventory_quantity_non_negative')) {
      return 'There is not enough stock for this. Stock on hand cannot go below zero.';
    }
  }

  if (error.code == '23505') {
    final detail = '$message ${error.details ?? ''}'.toLowerCase();
    if (detail.contains('uq_inventory_loan_issue_once')) {
      return 'This item was already taken from stock for this loan.';
    }
    if (detail.contains('phone')) {
      return 'This phone number is already used by another account.';
    }
    if (detail.contains('username')) {
      return 'This username is already taken.';
    }
  }
  return null;
}

/// What to show for [error] in a snackbar or banner: the database's readable
/// message if it has one, otherwise the exception text without its
/// "Exception: " prefix.
String friendlyErrorMessage(Object error) {
  return readableDatabaseMessage(error) ??
      error.toString().replaceFirst('Exception: ', '');
}
