import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/activity_text.dart';
import '../models/admin_dashboard_model.dart';
import '../models/admin_log_message.dart';
import '../models/staff_action_model.dart';
import '../../core/utils/staff_log_filters.dart';
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

  /// The accountability trail: every change a Manager or Officer made to an
  /// audited table, newest first. Written by the database, not the app, so it
  /// is complete whichever screen made the change. Readable by any staff member.
  ///
  /// [scope] narrows it to one tab, one feature of a tab, Broadcast or System
  /// (see staff_log_filters.dart). Everything the database wrote is included,
  /// plus the report exports, which the app records (they change no table).
  Future<List<StaffActionEntry>> fetchStaffActions({
    int limit = 30,
    int offset = 0,
    String? staffId,
    StaffLogScope scope = const StaffLogScope.all(),
  }) async {
    var query = _client.from('admin_activity_log').select(
      'id, admin_id, actor_name, actor_role, module, action_type, '
      'operation, table_name, record_id, reference_label, description, '
      'old_values, new_values, created_at',
    );
    const exportRows = 'and(source.eq.app,module.eq.reports,action_type.eq.exported)';
    if (scope.isAll) {
      query = query.or('source.eq.db,$exportRows');
    } else if (scope.module != null) {
      query = query.eq('source', 'db').eq('module', scope.module!);
    } else if (scope.tables.isNotEmpty && scope.exports) {
      query = query.or(
        'and(source.eq.db,table_name.in.(${scope.tables.join(',')})),$exportRows',
      );
    } else if (scope.tables.isNotEmpty) {
      query = query.eq('source', 'db').inFilter('table_name', scope.tables);
    } else {
      query = query
          .eq('source', 'app')
          .eq('module', 'reports')
          .eq('action_type', 'exported');
    }
    if (staffId != null) query = query.eq('admin_id', staffId);
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(StaffActionEntry.fromMap).toList();
  }

  /// The Manager and Officers, for the log's staff filter.
  Future<List<StaffOption>> fetchStaffOptions() async {
    final roles = await _client
        .from('user_roles')
        .select('user_id, role')
        .inFilter('role', ['admin', 'officer']);
    if (roles.isEmpty) return [];
    final ids = roles.map((r) => r['user_id'] as String).toList();
    final info = await _client
        .from('user_information')
        .select('user_id, full_name')
        .inFilter('user_id', ids);
    final names = {
      for (final r in info) r['user_id'] as String: r['full_name'] as String?,
    };
    final options = [
      for (final r in roles)
        StaffOption(
          id: r['user_id'] as String,
          name: names[r['user_id']] ?? '—',
          role: r['role'] as String,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return options;
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
          .eq('admin_id', uid)
          // The feed shows the readable messages the app writes. The
          // database-side trail (source 'db') is the same actions again with
          // before/after values, shown on the Staff Accountability screen.
          .eq('source', 'app');
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
