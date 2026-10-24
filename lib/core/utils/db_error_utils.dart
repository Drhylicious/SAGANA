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
///    moment.
/// Anything else (a network failure, a permission error, a bug) is technical
/// and must not be shown to a person as it is.
String? readableDatabaseMessage(Object error) {
  if (error is! PostgrestException) return null;
  final message = error.message.trim();
  if (error.code == 'P0001' && message.isNotEmpty) return message;
  if (error.code == '23505') {
    final detail = '$message ${error.details ?? ''}'.toLowerCase();
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
