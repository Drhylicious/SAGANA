import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/activity_text.dart';
import '../models/admin_dashboard_model.dart';
import '../models/admin_log_message.dart';
import 'farmer_lookup.dart';

/// Reads and writes admin_activity_log (see
/// supabase_schema_admin_activity_log.sql) — the one source of truth for
/// admin-performed actions. [fetchActivity] is what the Admin's own Recent
/// Activity screen reads from (admin_activity_log ONLY — unlike
/// AdminDashboardRepository.fetchRecentActivity, which additionally polls 6
/// other tables to build the Dashboard's broader "what's happening"
/// preview; that's a deliberately separate, unrelated concern and is left
/// untouched).
///
/// Call [log] right after a mutating admin action succeeds. Never throws —
/// a logging failure must not surface as if the actual action (the loan
/// issued, the item added, the listing approved) had failed.
class AdminActivityRepository {
  final _client = Supabase.instance.client;

  Future<void> log({
    required String module,
    required String actionType,
    required AdminLogMessage message,
    String? referenceId,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final row = {
        'admin_id': uid,
        'module': module,
        'action_type': actionType,
        // English copy for any reader that doesn't know the key yet.
        'description': adminLogEnglish(message),
        if (referenceId != null) 'reference_id': referenceId,
      };
      await _client.from('admin_activity_log').insert(row);
    } catch (_) {
      // Best-effort — logging must never break the action it's logging.
    }
  }

  Future<List<AdminActivityItem>> fetchActivity({
    int limit = 30,
    int offset = 0,
    List<String>? moduleFilters,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      // Recent Activity shows only this user's own actions. The table's RLS
      // lets every staff member read the whole log, so the scope is applied
      // here rather than relied on implicitly.
      var query = _client
          .from('admin_activity_log')
          .select(
            'id, admin_id, module, description, reference_id, created_at',
          )
          .eq('admin_id', uid);
      if (moduleFilters != null) {
        query = query.inFilter('module', moduleFilters);
      }
      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      if (rows.isEmpty) return [];

      final adminIds = rows
          .map((r) => r['admin_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final infoMap = await fetchFarmerInfoMap(_client, adminIds);

      return rows.map((r) {
        final adminId = r['admin_id'] as String?;
        return AdminActivityItem(
          id: r['id'] as String,
          type: AdminActivityType.logged,
          plainDescription: localizeAdminLogRow(r),
          adminName: adminId != null ? infoMap[adminId]?.fullName : null,
          timestamp: DateTime.parse(r['created_at'] as String),
          isPrimary: false,
          sourceModule: r['module'] as String,
          referenceId: r['reference_id'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('AdminActivityRepository.fetchActivity failed: $e');
      return [];
    }
  }
}
