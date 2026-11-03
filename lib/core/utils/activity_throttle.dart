/// Decides when the app should record "this account is in use" again.
///
/// The Manager's Active / Inactive status comes from
/// `user_information.last_active_at`. It used to be written only when someone
/// typed their password. A Buyer who stays signed in (the session survives
/// closing the app) never signs in again, so after 30 days of daily use they
/// would have been shown as Inactive. The app now also records activity when
/// it starts with a saved session and when it returns to the foreground. This
/// keeps that from being a request on every resume: at most one per
/// [minGap].
class ActivityThrottle {
  /// The status only changes at a 30-day boundary, so an hour is far finer than
  /// it needs to be while still being a handful of requests a day at most.
  static const Duration minGap = Duration(hours: 1);

  DateTime? _lastStamped;

  /// True when it is time to record activity. [force] is for an explicit
  /// sign-in, which always records.
  bool shouldStamp(DateTime now, {bool force = false}) {
    if (force) return true;
    final last = _lastStamped;
    return last == null || now.difference(last) >= minGap;
  }

  /// Call when a record was sent.
  void markStamped(DateTime now) => _lastStamped = now;

  /// Call when a record could not be sent (offline), so the next chance retries.
  void markFailed() => _lastStamped = null;
}
