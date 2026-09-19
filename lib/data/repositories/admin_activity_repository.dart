import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes to admin_activity_log (see supabase_schema_admin_activity_log.sql)
/// — the generic activity log Recent Activity reads from, alongside the
/// original 6 polled sources in AdminDashboardRepository.fetchRecentActivity.
///
/// Call [log] right after a mutating admin action succeeds. Never throws —
/// a logging failure must not surface as if the actual action (the loan
/// issued, the item added, the listing approved) had failed.
class AdminActivityRepository {
  final _client = Supabase.instance.client;

  Future<void> log({
    required String module,
    required String actionType,
    required String description,
    String? referenceId,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('admin_activity_log').insert({
        'admin_id': uid,
        'module': module,
        'action_type': actionType,
        'description': description,
        if (referenceId != null) 'reference_id': referenceId,
      });
    } catch (_) {
      // Best-effort — logging must never break the action it's logging.
    }
  }
}
