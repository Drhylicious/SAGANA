import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/member_activity_label.dart';
import 'package:sagana/data/models/staff_action_model.dart';

/// The accountability logbook for the Members tab. Each row is shaped exactly as
/// the database writes it (see the "N5" checks in test/sql_harness/run.mjs); the
/// Manager must read it as "who did what to which member, and why".
StaffActionEntry row({
  required String table,
  required String operation,
  String module = 'members',
  String? reference = 'Nora Five',
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
  String description = 'database text',
}) =>
    StaffActionEntry.fromMap({
      'id': 'x',
      'admin_id': 'o1',
      'actor_name': 'Olivia One',
      'actor_role': 'officer',
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

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));
  String? headline(StaffActionEntry e, [AppLocalizations? l10n]) => memberActionHeadline(e, l10n ?? en);

  group('what was done, to which member', () {
    test('suspending', () {
      final e = row(
        table: 'user_roles', operation: 'updated',
        before: {'status': 'active', 'suspension_reason': null},
        after: {'status': 'suspended', 'suspension_reason': 'Unpaid contributions'},
      );
      expect(headline(e), 'Suspended Nora Five');
      expect(memberActionDetail(e, en), 'Reason: Unpaid contributions');
    });

    test('reactivating', () {
      expect(
        headline(row(table: 'user_roles', operation: 'updated', before: {'status': 'suspended'}, after: {'status': 'active'})),
        'Reactivated Nora Five',
      );
    });

    test('approving an applicant', () {
      expect(
        headline(row(table: 'user_roles', operation: 'updated', before: {'status': 'pending'}, after: {'status': 'active'})),
        'Approved the membership of Nora Five',
      );
    });

    test('disapproving, with the reason', () {
      final e = row(
        table: 'user_roles', operation: 'updated',
        before: {'status': 'pending', 'rejection_reason': null},
        after: {'status': 'rejected', 'rejection_reason': 'Duplicate member'},
      );
      expect(headline(e), 'Disapproved the application of Nora Five');
      expect(memberActionDetail(e, en), 'Reason: Duplicate member');
    });

    test('creating a Farmer account and an Officer account', () {
      expect(headline(row(table: 'user_roles', operation: 'created', after: {'role': 'farmer', 'status': 'pending'})),
          'Created a Farmer account: Nora Five');
      expect(headline(row(table: 'user_roles', operation: 'created', after: {'role': 'officer', 'status': 'active'})),
          'Created an Officer account: Nora Five');
    });

    test('resetting a password', () {
      expect(
        headline(row(table: 'user_roles', operation: 'updated', before: {'must_change_password': false}, after: {'must_change_password': true})),
        'Reset the password of Nora Five',
      );
    });

    test('deleting a disapproved account', () {
      expect(headline(row(table: 'user_roles', operation: 'deleted', before: {'role': 'farmer', 'status': 'rejected'})),
          'Deleted the account of Nora Five');
    });

    test('adding a contribution: amount, member and the note', () {
      final e = row(
        table: 'capital_contribution_events', operation: 'created',
        after: {'farmer_id': 'f', 'amount': 250, 'source': 'member_payment', 'note': 'March'},
      );
      expect(headline(e), 'Recorded a contribution of ₱250.00 for Nora Five');
      expect(memberActionDetail(e, en), 'Note: March');
      // The amount can arrive as text (a decimal column).
      expect(
        headline(row(table: 'capital_contribution_events', operation: 'created', after: {'amount': '1250.5'})),
        'Recorded a contribution of ₱1,250.50 for Nora Five',
      );
    });

    test('cancelling a contribution: the amount without a sign, the member and the reason', () {
      final e = row(
        table: 'capital_contribution_events', operation: 'created',
        after: {'amount': -250, 'source': 'member_payment', 'reverses_event_id': 'e1', 'reversal_reason': 'Wrong member'},
      );
      expect(headline(e), 'Cancelled a contribution of ₱250.00 for Nora Five');
      expect(memberActionDetail(e, en), 'Reason: Wrong member');
      expect(
        headline(e, tl),
        'Kinansela ang ambag na ₱250.00 para kay Nora Five',
      );
      expect(memberActionDetail(e, tl), 'Dahilan: Wrong member');
      // An ordinary negative adjustment is still "recorded", with its sign.
      expect(
        headline(row(table: 'capital_contribution_events', operation: 'created', after: {'amount': -50, 'source': 'manual_adjustment'})),
        'Recorded a contribution of ₱-50.00 for Nora Five',
      );
    });

    test('changing an Officer\'s access says which module and the new level', () {
      expect(
        headline(row(table: 'officer_permissions', operation: 'updated', reference: 'Omar Two',
            before: {'module': 'loans', 'access_level': 'manage'}, after: {'module': 'loans', 'access_level': 'view'})),
        'Changed the Loans access of Omar Two to View Only',
      );
      expect(
        headline(row(table: 'officer_permissions', operation: 'created', reference: 'Omar Two', after: {'module': 'reports', 'access_level': 'manage'})),
        'Changed the Reports access of Omar Two to Manage',
      );
    });

    test('handling a password help request and editing member information', () {
      expect(headline(row(table: 'password_reset_requests', operation: 'updated')), 'Handled a password help request from Nora Five');
      expect(headline(row(table: 'user_information', operation: 'updated', after: {'phone_number': '0917'})), 'Edited the information of Nora Five');
      expect(headline(row(table: 'farmer_profiles', operation: 'updated', after: {'gender': 'female'})), 'Edited the information of Nora Five');
    });
  });

  group('safe fallbacks', () {
    test('a row it does not know is left to the database description', () {
      expect(headline(row(table: 'member_capital_shares', operation: 'updated', after: {'total_contribution': 250})), isNull);
      expect(headline(row(table: 'user_roles', operation: 'updated', before: {'status': 'rejected'}, after: {'status': 'pending'})), isNull);
      expect(headline(row(table: 'user_roles', operation: 'created', after: {'role': 'buyer'})), isNull);
    });

    test('rows from other modules are never reworded', () {
      expect(headline(row(table: 'user_roles', operation: 'updated', module: 'loans', after: {'status': 'suspended'})), isNull);
      expect(memberActionDetail(row(table: 'user_roles', operation: 'updated', module: 'crops', after: {'rejection_reason': 'x'}), en), isNull);
    });

    test('a missing member name reads as a dash, not "null"', () {
      expect(headline(row(table: 'user_roles', operation: 'updated', reference: null, before: {'status': 'active'}, after: {'status': 'suspended'})),
          'Suspended —');
    });

    test('no reason or note means no detail line', () {
      expect(memberActionDetail(row(table: 'user_roles', operation: 'updated', after: {'status': 'suspended', 'suspension_reason': '  '}), en), isNull);
      expect(memberActionDetail(row(table: 'capital_contribution_events', operation: 'created', after: {'amount': 5}), en), isNull);
    });
  });

  group('Tagalog', () {
    test('the same actions read naturally in Tagalog', () {
      final suspended = row(table: 'user_roles', operation: 'updated', before: {'status': 'active'},
          after: {'status': 'suspended', 'suspension_reason': 'Hindi nagbayad'});
      expect(headline(suspended, tl), 'Sinuspinde si Nora Five');
      expect(memberActionDetail(suspended, tl), 'Dahilan: Hindi nagbayad');
      expect(
        headline(row(table: 'capital_contribution_events', operation: 'created', after: {'amount': 250, 'note': 'Marso'}), tl),
        'Nagtala ng ambag na ₱250.00 para kay Nora Five',
      );
      expect(
        headline(row(table: 'officer_permissions', operation: 'updated', reference: 'Omar Two', after: {'module': 'loans', 'access_level': 'view'}), tl),
        'Pinalitan ang Mga Utang access ni Omar Two sa View Only',
      );
    });
  });
}
