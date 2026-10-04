import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_dashboard_model.dart';
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

  Future<List<AdminActivityItem>> fetchActivity({
    int limit = 30,
    int offset = 0,
    List<String>? moduleFilters,
  }) async {
    try {
      var query = _client
          .from('admin_activity_log')
          .select(
            'id, admin_id, module, description, reference_id, created_at',
          );
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
          plainDescription: r['description'] as String,
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
