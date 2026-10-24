import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/suspension_notice.dart';

/// Watches the signed-in user's own user_roles row, so an admin's suspension
/// takes effect while the user is already logged in.
///
/// Two paths feed the same [suspensions] stream:
///   - Realtime: a live listener on the user's row (the primary path).
///   - Check: [checkNow] reads the row once. The app calls it on resume and
///     before each Sync, which covers a missed or delayed realtime event.
///
/// Only emits once per start(): the first suspended status ends the session,
/// so later events are ignored until start() is called again on the next login.
class AccountStatusWatcher {
  AccountStatusWatcher._();
  static final AccountStatusWatcher instance = AccountStatusWatcher._();

  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  final StreamController<SuspensionNotice> _controller =
      StreamController<SuspensionNotice>.broadcast();
  bool _reported = false;

  Stream<SuspensionNotice> get suspensions => _controller.stream;

  /// Starts the realtime listener for the signed-in user. Safe to call again:
  /// it replaces any listener already running.
  void start() {
    stop();
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    _reported = false;
    _sub = _client
        .from('user_roles')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', uid)
        .listen(
          (rows) {
            if (rows.isNotEmpty) _report(rows.first);
          },
          onError: (Object e) =>
              debugPrint('AccountStatusWatcher: realtime error: $e'),
        );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Reads the row once. Returns true when the account is suspended, so a
  /// caller (such as Sync) can stop before doing any more work.
  Future<bool> checkNow() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final row = await _client
          .from('user_roles')
          .select('status, suspension_reason, suspended_until')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return false;
      return _report(row);
    } catch (e) {
      // Offline or failed: not a verdict either way. Realtime and the next
      // check will catch a real suspension.
      debugPrint('AccountStatusWatcher.checkNow failed: $e');
      return false;
    }
  }

  bool _report(Map<String, dynamic> row) {
    if (row['status'] != 'suspended') return false;
    if (!_reported) {
      _reported = true;
      _controller.add(
        SuspensionNotice(
          reason: row['suspension_reason'] as String?,
          suspendedUntil: row['suspended_until'] == null
              ? null
              : DateTime.parse(row['suspended_until'] as String).toLocal(),
        ),
      );
    }
    return true;
  }
}
