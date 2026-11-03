/// How the Staff Accountability log is grouped for filtering: the five tabs
/// (Dashboard, Members, Marketplace, Loans, Reports), then Broadcast and System.
/// Each tab lists its own features, so a person can narrow "Dashboard" to Prices
/// or "Loans" to Payments. A feature is the set of audited tables whose changes
/// belong to it.
///
/// This is the one place that says which table belongs to which tab. The test
/// test/staff_log_filters_test.dart checks it against the audit triggers in the
/// SQL scripts, so a table that is audited but has no tab fails there.
class StaffLogFeature {
  const StaffLogFeature(this.key, this.tables, {this.exports = false});

  /// Stable key; also picks the label (see the screen).
  final String key;

  /// Audited tables (admin_activity_log.table_name).
  final List<String> tables;

  /// The Reports export action, which the app records (there is no table).
  final bool exports;
}

class StaffLogGroup {
  const StaffLogGroup(this.key, this.features, {this.module});

  /// dashboard, members, marketplace, loans, reports, broadcast or system.
  final String key;
  final List<StaffLogFeature> features;

  /// For a group found by its module key instead of its tables (System).
  final String? module;

  List<String> get tables => [for (final f in features) ...f.tables];
  bool get exports => features.any((f) => f.exports);
}

/// The five tabs, in the app's own order.
const staffLogPrimaryGroups = <StaffLogGroup>[
  StaffLogGroup('dashboard', [
    StaffLogFeature('inventory', [
      'cooperative_inventory',
      'inventory_transactions',
      'inventory_categories',
      'units',
    ]),
    StaffLogFeature('crops', ['crop_master', 'crop_categories', 'crop_requests']),
    StaffLogFeature('programs', [
      'cooperative_programs',
      'program_activities',
      'program_members',
      'program_products',
      'program_product_purchases',
      'program_enrollment_requests',
    ]),
    StaffLogFeature('prices', ['price_records']),
    StaffLogFeature('loanItems', ['loan_items_master']),
  ]),
  StaffLogGroup('members', [
    StaffLogFeature('accounts', [
      'user_roles',
      'user_information',
      'farmer_profiles',
      'password_reset_requests',
      'account_creation_requests',
    ]),
    StaffLogFeature('contributions', ['capital_contribution_events', 'member_capital_shares']),
    StaffLogFeature('officerAccess', ['officer_permissions']),
  ]),
  StaffLogGroup('marketplace', [
    StaffLogFeature('listings', ['marketplace_listings', 'listing_edit_requests']),
    StaffLogFeature('orders', ['orders']),
    StaffLogFeature('offers', ['cooperative_purchase_offers', 'member_sales_transactions']),
    StaffLogFeature('marketLinking', [
      'market_linking_programs',
      'market_linking_sales',
      'da_amad_enrollments',
    ]),
  ]),
  StaffLogGroup('loans', [
    StaffLogFeature('loansIssued', ['farmer_loans']),
    StaffLogFeature('payments', ['farmer_loan_payments']),
    StaffLogFeature('loanRequests', ['loan_requests']),
    StaffLogFeature('loanPolicy', ['loan_policy_settings']),
  ]),
  StaffLogGroup('reports', [
    StaffLogFeature('balik', ['cooperative_annual_totals', 'member_contributions']),
    StaffLogFeature('exports', [], exports: true),
  ]),
];

/// Other screens that are not one of the five tabs.
const staffLogSecondaryGroups = <StaffLogGroup>[
  StaffLogGroup('broadcast', [
    StaffLogFeature('broadcast', ['broadcast_logs']),
  ]),
  // Work the system does on its own (the monthly BOD meeting reminder): no
  // person is behind it, so it is found by its module key.
  StaffLogGroup('system', [], module: 'system'),
];

const staffLogGroups = <StaffLogGroup>[
  ...staffLogPrimaryGroups,
  ...staffLogSecondaryGroups,
];

/// The tab an entry belongs to: found by its table, else by its module key
/// (System, Reports exports), else the module key itself.
String staffLogGroupKeyOf(String? table, String module) {
  if (table != null) {
    for (final g in staffLogGroups) {
      if (g.tables.contains(table)) return g.key;
    }
  }
  return module;
}

StaffLogGroup? staffLogGroupByKey(String? key) {
  for (final g in staffLogGroups) {
    if (g.key == key) return g;
  }
  return null;
}

StaffLogFeature? staffLogFeatureByKey(StaffLogGroup? group, String? key) {
  if (group == null || key == null) return null;
  for (final f in group.features) {
    if (f.key == key) return f;
  }
  return null;
}

/// What a filter selection means for the query: the database rows (by table, or
/// by module for System) and whether the app-written export rows are included.
class StaffLogScope {
  const StaffLogScope({required this.tables, required this.exports, this.module}) : isAll = false;

  /// Everything (no group chosen).
  const StaffLogScope.all()
      : tables = const [],
        exports = true,
        module = null,
        isAll = true;

  final List<String> tables;
  final bool exports;
  final String? module;

  /// True only for the unfiltered log (an exports-only scope also has no tables).
  final bool isAll;

  factory StaffLogScope.of(StaffLogGroup? group, StaffLogFeature? feature) {
    if (group == null) return const StaffLogScope.all();
    if (feature != null) {
      return StaffLogScope(tables: feature.tables, exports: feature.exports);
    }
    return StaffLogScope(tables: group.tables, exports: group.exports, module: group.module);
  }
}
