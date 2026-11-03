import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/member_activity_label.dart';
import 'package:sagana/core/utils/staff_log_filters.dart';
import 'package:sagana/data/models/admin_log_message.dart';
import 'package:sagana/data/models/staff_action_model.dart';

/// Staff Accountability must cover every audited table under one of the tabs,
/// read well in both languages, and filter the way the chips say.
StaffActionEntry entry({
  String module = 'marketplace',
  String? table,
  String operation = 'created',
  String? reference,
  String role = 'officer',
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
  String description = 'database text',
}) =>
    StaffActionEntry.fromMap({
      'id': 'x',
      'admin_id': 'o1',
      'actor_name': 'Olivia One',
      'actor_role': role,
      'module': module,
      'operation': operation,
      'table_name': table,
      'record_id': 'r',
      'reference_label': reference,
      'description': description,
      'old_values': before,
      'new_values': after,
      'created_at': '2026-11-03T08:30:00Z',
    });

Future<void> main() async {
  await initializeDateFormatting('en');
  await initializeDateFormatting('tl');
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));
  String sql(String name) => File('supabase_schema/$name').readAsStringSync().replaceAll('\r\n', '\n');

  /// Every table an audit trigger is attached to, read from the SQL scripts.
  Set<String> auditedTables() {
    final out = <String>{};
    // Script 05: ('table', 'module_key'[, 'flag']) rows of the attach loop.
    final s05 = sql('supabase_schema_officer_permissions_05_accountability.sql');
    final from = s05.indexOf('FOR r IN');
    final to = s05.indexOf('AS t(tbl', from);
    expect(from, isNonNegative);
    for (final m in RegExp(r"\('(\w+)',\s*'\w+'").allMatches(s05.substring(from, to))) {
      out.add(m.group(1)!);
    }
    // Script 22: one pg_temp.sagana_set_audit('table', ...) call per table (the payout table too).
    final s22 = sql('supabase_schema_officer_permissions_22_accountability_coverage.sql');
    final calls = RegExp(r"sagana_set_audit\('(\w+)'").allMatches(s22).map((m) => m.group(1)!).toSet();
    expect(calls.length, 10);
    out.addAll(calls);
    // Script 12: the member-information tables, and the Officer access function's table.
    final s12 = sql('supabase_schema_officer_permissions_12_member_activity_logbook.sql');
    final arr = RegExp(r"FOREACH t IN ARRAY ARRAY\[([^\]]*)\]").firstMatch(s12)!.group(1)!;
    out.addAll(RegExp(r"'(\w+)'").allMatches(arr).map((m) => m.group(1)!));
    out.add('officer_permissions');
    return out;
  }

  group('every audited table belongs to a tab', () {
    test('the SQL audit list is read (not empty)', () {
      expect(auditedTables().length, greaterThan(30));
    });

    test('each audited table is under exactly one of the tabs, Broadcast or System', () {
      final owner = <String, List<String>>{};
      for (final g in staffLogGroups) {
        for (final t in g.tables) {
          owner.putIfAbsent(t, () => []).add(g.key);
        }
      }
      final missing = auditedTables().where((t) => !owner.containsKey(t)).toList()..sort();
      expect(missing, isEmpty, reason: 'audited, but no filter shows it: $missing');
      final twice = owner.entries.where((e) => e.value.length > 1).map((e) => e.key).toList();
      expect(twice, isEmpty, reason: 'in two tabs: $twice');
    });

    test('no filter names a table that is not audited', () {
      final audited = auditedTables();
      final stray = [for (final g in staffLogGroups) ...g.tables].where((t) => !audited.contains(t)).toList();
      expect(stray, isEmpty, reason: 'a chip that can never show anything: $stray');
    });

    test('every audited table has a sentence label in both languages', () {
      for (final t in auditedTables()) {
        expect(staffThingLabel(en, t), isNotNull, reason: 'English: $t');
        expect(staffThingLabel(tl, t), isNotNull, reason: 'Tagalog: $t');
      }
    });

    test('the five tabs are Dashboard, Members, Marketplace, Loans, Reports; Broadcast and System are separate', () {
      expect(staffLogPrimaryGroups.map((g) => g.key), ['dashboard', 'members', 'marketplace', 'loans', 'reports']);
      expect(staffLogSecondaryGroups.map((g) => g.key), ['broadcast', 'system']);
    });

    test('every tab and feature has a label in both languages (not a bare key)', () {
      // Reads the screen's own label functions through the generated strings.
      final src = File('lib/presentation/screens/admin/staff_accountability_screen.dart').readAsStringSync();
      for (final g in staffLogGroups) {
        expect(src, contains("case '${g.key}':"), reason: 'tab label ${g.key}');
        for (final f in g.features) {
          if (f.key == g.key) continue; // Broadcast: the tab label is used
          expect(src, contains("case '${f.key}':"), reason: 'feature label ${f.key}');
        }
      }
    });
  });

  group('what a filter means for the query', () {
    test('no tab: everything the database wrote plus the exports', () {
      final s = StaffLogScope.of(null, null);
      expect(s.isAll, isTrue);
    });

    test('a tab covers all of its features; a feature only its own tables', () {
      final dashboard = staffLogGroupByKey('dashboard')!;
      final all = StaffLogScope.of(dashboard, null);
      expect(all.tables, containsAll(['cooperative_inventory', 'crop_master', 'cooperative_programs', 'price_records', 'loan_items_master']));
      expect(all.exports, isFalse);
      final prices = StaffLogScope.of(dashboard, staffLogFeatureByKey(dashboard, 'prices'));
      expect(prices.tables, ['price_records']);
    });

    test('Loans does not take the loan items catalogue (that is Dashboard)', () {
      final loans = StaffLogScope.of(staffLogGroupByKey('loans'), null);
      expect(loans.tables, containsAll(['farmer_loans', 'farmer_loan_payments', 'loan_requests', 'loan_policy_settings']));
      expect(loans.tables, isNot(contains('loan_items_master')));
    });

    test('Reports covers the Balik-Tangkilik tables AND the exports; Exports alone is only the exports', () {
      final reports = staffLogGroupByKey('reports')!;
      final whole = StaffLogScope.of(reports, null);
      expect(whole.exports, isTrue);
      expect(whole.tables, containsAll(['cooperative_annual_totals', 'member_contributions']));
      final exports = StaffLogScope.of(reports, staffLogFeatureByKey(reports, 'exports'));
      expect(exports.exports, isTrue);
      expect(exports.tables, isEmpty);
    });

    test('System is found by its module key', () {
      final s = StaffLogScope.of(staffLogGroupByKey('system'), null);
      expect(s.module, 'system');
    });

    test('an entry is filed under the tab its table belongs to', () {
      expect(staffLogGroupKeyOf('orders', 'marketplace'), 'marketplace');
      expect(staffLogGroupKeyOf('loan_items_master', 'loans'), 'dashboard', reason: 'the catalogue is a Dashboard feature');
      expect(staffLogGroupKeyOf('farmer_loans', 'loans'), 'loans');
      expect(staffLogGroupKeyOf(null, 'reports'), 'reports', reason: 'an export has no table');
      expect(staffLogGroupKeyOf('notifications', 'system'), 'system');
    });
  });

  group('the sentence for any row', () {
    test('added, changed and deleted, with the record', () {
      final listing = entry(table: 'marketplace_listings', reference: 'Eggplant');
      expect(staffActionHeadline(listing, en), 'Added listing: Eggplant');
      expect(staffActionHeadline(entry(table: 'orders', operation: 'updated', reference: 'ORD-1'), en), 'Changed order: ORD-1');
      expect(staffActionHeadline(entry(table: 'price_records', operation: 'deleted', reference: 'Tomato'), en), 'Deleted price: Tomato');
      expect(staffActionHeadline(entry(table: 'farmer_loans', reference: 'LRN-1'), en), 'Added loan: LRN-1');
    });

    test('with no record name the colon is left out', () {
      expect(staffActionHeadline(entry(table: 'units', reference: null), en), 'Added unit');
      expect(staffActionHeadline(entry(table: 'units', reference: '  ', operation: 'deleted'), en), 'Deleted unit');
    });

    test('the same rows read in Tagalog', () {
      expect(staffActionHeadline(entry(table: 'price_records', operation: 'updated', reference: 'Tomato'), tl), 'Binago ang presyo: Tomato');
      expect(staffActionHeadline(entry(table: 'farmer_loan_payments', reference: 'LRN-1'), tl), 'Nagdagdag ng bayad sa pautang: LRN-1');
      expect(staffActionHeadline(entry(table: 'orders', operation: 'deleted', reference: 'ORD-9'), tl), 'Binura ang order: ORD-9');
    });

    test('the Members wording still wins where it exists', () {
      final e = entry(
        module: 'members', table: 'user_roles', operation: 'updated', reference: 'Farah One',
        before: {'status': 'active'}, after: {'status': 'suspended', 'suspension_reason': 'Unpaid'},
      );
      expect(staffActionHeadline(e, en), 'Suspended Farah One');
    });

    test('a table it does not know shows the database text, never nothing', () {
      expect(staffActionHeadline(entry(table: 'something_new', description: 'Updated something new: X'), en), 'Updated something new: X');
    });

    test('a status that moved is shown as a line under the sentence', () {
      final e = entry(table: 'orders', operation: 'updated', reference: 'ORD-1', before: {'status': 'pending'}, after: {'status': 'ready'});
      expect(staffActionDetail(e, en), 'Status: pending → ready');
      expect(staffActionDetail(e, tl), 'Katayuan: pending → ready');
      expect(staffActionDetail(entry(table: 'orders', operation: 'updated', before: {'note': 'a'}, after: {'note': 'b'}), en), isNull);
      expect(staffActionDetail(entry(table: 'orders', operation: 'created', after: {'status': 'pending'}), en), isNull, reason: 'only a change');
    });

    test('the BOD reminder line: date and how many were told, in both languages', () {
      final e = entry(
        module: 'system', table: 'notifications', role: 'system', reference: '2026-12-05',
        after: {'meeting_date': '2026-12-05', 'farmers': 120, 'staff': 4},
      );
      expect(staffActionHeadline(e, en), 'BOD meeting reminder sent for December 5, 2026 to 120 Farmers and 4 staff');
      expect(staffActionHeadline(e, tl), contains('Naipadala ang paalala sa pulong ng BOD'));
      expect(staffActionHeadline(e, tl), contains('120'));
    });

    test('a report export (written by the app, no table) is translated from its key', () {
      final description = adminLogEnglish(const AdminLogMessage('adminLogExportGenerated', {'format': 'PDF', 'count': '3'}));
      final e = entry(module: 'reports', table: null, operation: 'exported', description: description);
      expect(staffActionHeadline(e, en), description);
      expect(staffActionHeadline(e, tl), isNot(description), reason: 'Tagalog reads Tagalog');
    });
  });
}
