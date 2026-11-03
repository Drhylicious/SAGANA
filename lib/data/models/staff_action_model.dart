/// One row of the staff accountability trail: a change a Manager or Officer made
/// to an audited table, recorded by the database (admin_activity_log, source
/// 'db'). It names the staff account, what was done, to which record, the
/// values before and after, and when.
class StaffActionEntry {
  final String id;
  final String? staffId;
  final String? staffName;

  /// 'admin' (the Manager) or 'officer'.
  final String? staffRole;

  /// The module key the app already uses: crops, inventory, programs, loans,
  /// prices, broadcast, members.
  final String module;

  /// 'created', 'updated' or 'deleted'.
  final String operation;
  final String? tableName;
  final String? recordId;

  /// A human reference for the record (name, loan reference, order number...).
  final String? reference;
  final String description;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final DateTime timestamp;

  const StaffActionEntry({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.staffRole,
    required this.module,
    required this.operation,
    required this.tableName,
    required this.recordId,
    required this.reference,
    required this.description,
    required this.oldValues,
    required this.newValues,
    required this.timestamp,
  });

  factory StaffActionEntry.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic>? json(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    return StaffActionEntry(
      id: m['id'] as String,
      staffId: m['admin_id'] as String?,
      staffName: m['actor_name'] as String?,
      staffRole: m['actor_role'] as String?,
      module: (m['module'] as String?) ?? '',
      operation: (m['operation'] as String?) ?? (m['action_type'] as String?) ?? '',
      tableName: m['table_name'] as String?,
      recordId: m['record_id'] as String?,
      reference: m['reference_label'] as String?,
      description: (m['description'] as String?) ?? '',
      oldValues: json(m['old_values']),
      newValues: json(m['new_values']),
      timestamp: DateTime.parse(m['created_at'] as String),
    );
  }

  /// The columns that changed, as (column, before, after). For a create only the
  /// new values exist; for a delete only the old ones.
  List<({String column, Object? before, Object? after})> get changes {
    final keys = <String>{...?oldValues?.keys, ...?newValues?.keys}.toList()
      ..sort();
    return [
      for (final k in keys)
        (column: k, before: oldValues?[k], after: newValues?[k]),
    ];
  }
}

/// A Manager or Officer the log can be filtered by.
class StaffOption {
  final String id;
  final String name;
  final String role;
  const StaffOption({required this.id, required this.name, required this.role});
}
