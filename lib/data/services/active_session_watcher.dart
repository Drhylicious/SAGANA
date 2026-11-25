import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notice emitted when the currently signed-in account is opened on a newer
/// device, so Device A can explain why it was signed out.
class SessionReplacedNotice {
  final String deviceName;
  final DateTime? replacedAt;

  const SessionReplacedNotice({required this.deviceName, this.replacedAt});
}

/// Decodes the `session_id` claim from a Supabase JWT access token, or null
/// when unavailable or malformed.
String? extractSessionIdFromJwt(String? accessToken) {
  if (accessToken == null || accessToken.isEmpty) return null;
  final parts = accessToken.split('.');
  if (parts.length < 2) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (payload is Map) {
      final sid = payload['session_id']?.toString().trim();
      return (sid == null || sid.isEmpty) ? null : sid;
    }
  } catch (_) {
    // Ignore malformed JWT payloads.
  }
  return null;
}

/// Parses a device name out of a `SESSION_REPLACED: ... (<device>).` database
/// pre-request error raised by `staff_permission_gate()`.
String? parseSessionReplacedDevice(Object error) {
  final msg = error.toString();
  final idx = msg.indexOf('SESSION_REPLACED:');
  if (idx < 0) return null;
  final tail = msg.substring(idx);
  final paren = RegExp(r'\(([^)]+)\)\.?').firstMatch(tail);
  final device = paren?.group(1)?.trim();
  return (device == null || device.isEmpty) ? 'another device' : device;
}

/// Watches `public.user_active_sessions` for the signed-in user across ALL
/// roles (Manager, Officer, Farmer, Buyer).
///
/// Whenever Device B claims the account, two paths fire [replacements]:
///   1. Realtime listener on the user's `user_active_sessions` row.
///   2. Explicit [checkNow] calls on boot, app resume, and before Sync replay.
class ActiveSessionWatcher {
  ActiveSessionWatcher._();
  static final ActiveSessionWatcher instance = ActiveSessionWatcher._();

  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  final StreamController<SessionReplacedNotice> _controller =
      StreamController<SessionReplacedNotice>.broadcast();

  bool _reported = false;

  Stream<SessionReplacedNotice> get replacements => _controller.stream;

  /// True while the UI is displaying the session-replaced notice and tearing
  /// down the local session, so `onAuthStateChange(signedOut)` does not race
  /// and skip the dialog.
  bool handlingReplacement = false;

  void start() {
    stop();
    final session = _client.auth.currentSession;
    final uid = session?.user.id ?? _client.auth.currentUser?.id;
    if (uid == null) return;
    _reported = false;
    handlingReplacement = false;
    _sub = _client
        .from('user_active_sessions')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', uid)
        .listen(
          (rows) {
            if (rows.isNotEmpty) _handleRow(rows.first);
          },
          onError: (Object e) =>
              debugPrint('ActiveSessionWatcher: realtime error: $e'),
        );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Checks with the database whether this device's JWT `session_id` is still
  /// the sole active session. Returns `true` when replaced by another device.
  Future<bool> checkNow() async {
    final session = _client.auth.currentSession;
    if (session == null) return false;
    final localSid = extractSessionIdFromJwt(session.accessToken);
    if (localSid == null) return false;
    try {
      final res = await _client.rpc('get_active_session_status');
      if (res is Map) {
        final active = res['active'] as bool? ?? true;
        if (!active) {
          final device =
              (res['device_name'] as String?)?.trim().isNotEmpty == true
              ? (res['device_name'] as String).trim()
              : 'another device';
          final atRaw = res['signed_in_at'] as String?;
          _emit(
            deviceName: device,
            replacedAt: atRaw == null
                ? null
                : DateTime.tryParse(atRaw)?.toLocal(),
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      final replacedDevice = parseSessionReplacedDevice(e);
      if (replacedDevice != null) {
        _emit(deviceName: replacedDevice);
        return true;
      }
      debugPrint('ActiveSessionWatcher.checkNow skipped: $e');
      return false;
    }
  }

  /// Called by any repository/interceptor when a `SESSION_REPLACED:` error is
  /// returned directly from PostgREST's pre-request hook.
  void reportServerError(Object error) {
    final device = parseSessionReplacedDevice(error);
    if (device != null) {
      _emit(deviceName: device);
    }
  }

  void _handleRow(Map<String, dynamic> row) {
    final localSid = extractSessionIdFromJwt(
      _client.auth.currentSession?.accessToken,
    );
    final activeSid = row['session_id']?.toString().trim();
    if (localSid == null || activeSid == null || activeSid.isEmpty) return;
    if (activeSid == localSid) return;
    final device =
        (row['device_name'] as String?)?.trim().isNotEmpty == true
        ? (row['device_name'] as String).trim()
        : 'another device';
    final atRaw = row['signed_in_at'] as String?;
    _emit(
      deviceName: device,
      replacedAt: atRaw == null ? null : DateTime.tryParse(atRaw)?.toLocal(),
    );
  }

  void _emit({required String deviceName, DateTime? replacedAt}) {
    if (_reported) return;
    _reported = true;
    handlingReplacement = true;
    _controller.add(
      SessionReplacedNotice(deviceName: deviceName, replacedAt: replacedAt),
    );
  }
}
