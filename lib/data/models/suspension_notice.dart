/// What a suspended account is told: the recorded reason and the reactivation
/// date. A null [suspendedUntil] means the suspension lasts until an admin
/// reactivates the account.
class SuspensionNotice {
  final String? reason;
  final DateTime? suspendedUntil;

  const SuspensionNotice({this.reason, this.suspendedUntil});
}

/// Thrown by AuthService.login when a farmer or buyer account is suspended.
/// The login screen shows the red notice from [notice]; the session is
/// already signed out when this is thrown.
class AccountSuspendedException implements Exception {
  final SuspensionNotice notice;

  const AccountSuspendedException(this.notice);
}
