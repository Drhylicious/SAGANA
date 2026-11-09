import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Statuses are only Active and Completed', () {
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');

    test('the form no longer has an editable status; Completed is set by the action', () {
      expect(screen, isNot(contains('_statusOptions')));
      expect(screen, isNot(contains('suspended')));
      expect(screen, contains('_completeProgram'));
    });

    test('Completed programs are shown in their own, greyed-out section', () {
      expect(screen, contains("p.status != 'completed'"));
      expect(screen, contains('programMgmtCompletedSection'));
      expect(screen, contains("opacity: p.status == 'completed' ? 0.6 : 1"));
    });

    test('no Suspended wording is left in the strings', () {
      for (final f in ['app_en.arb', 'app_tl.arb']) {
        final m = jsonDecode(_read('lib/core/l10n/$f')) as Map<String, dynamic>;
        expect(
          m.keys.where((k) => k.toLowerCase().contains('programmgmtstatussuspended')),
          isEmpty,
          reason: f,
        );
      }
    });
  });

  group('Old outcome / loan-conversion workflow is gone from the app', () {
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
    final repo = _read('lib/data/repositories/program_repository.dart');

    test('no Record Outcome, Record Return or Convert to Loan action remains', () {
      for (final s in [
        '_showRecordOutcomeSheet',
        '_showRecordReturnSheet',
        '_showConvertToLoanSheet',
        'recordThrivingOutcome',
        'convertDistributionToLoan',
        'confirmProgramReturn',
      ]) {
        expect(screen.contains(s), isFalse, reason: 'screen still has $s');
        expect(repo.contains(s), isFalse, reason: 'repository still has $s');
      }
    });

    test('Members shows each outcome report status instead', () {
      expect(screen, contains('_outcomeSection'));
      expect(screen, contains('memWaitingDays'));
      expect(screen, isNot(contains('programMgmtOutcomeComingSoon')));
    });

    test('earlier outcomes stay visible but read-only (no tap handler)', () {
      // An outcome recorded before reports has no report: its result line is plain text.
      expect(screen, contains('if (m.isOutcomeRecorded) return _finalLine(m, null, l10n);'));
      expect(screen.replaceAll(RegExp(r'\s+'), ''), contains('child:r==null?row'));
    });
  });

  group('Activities removed from the app, kept in the database', () {
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
    final repo = _read('lib/data/repositories/program_repository.dart');
    final farmerRepo = _read('lib/data/repositories/farmer_program_repository.dart');
    final farmerScreen = _read('lib/presentation/screens/farmer/my_programs_screen.dart');

    test('no tab, no Activities code, no Farmer activities', () {
      expect(screen.contains('_ProgramActivitiesTab'), isFalse);
      for (final s in ['fetchActivities', 'createActivity', 'updateActivity', 'deleteActivity']) {
        expect(repo.contains(s), isFalse, reason: s);
      }
      expect(farmerRepo.contains('get_my_program_activities'), isFalse);
      expect(farmerScreen.contains('ProgramActivity'), isFalse);
    });

    test('the dashboard calendar still reads program_activities', () {
      expect(
        _read('lib/data/repositories/admin_dashboard_repository.dart'),
        contains(".from('program_activities')"),
      );
    });

    test('earlier "Activity" entries still render in the staff activity log', () {
      final log = _read('lib/data/models/admin_log_message.dart');
      expect(log, contains('adminLogProgramActivityCreated'));
      expect(log, contains('adminLogProgramActivityDeleted'));
    });

    test('History still words activity events from the accountability trail', () {
      final h = _read('lib/presentation/widgets/program_history_sheet.dart');
      expect(h, contains('programHistActivityCreated'));
      expect(h, contains('programHistActivityDeleted'));
    });
  });

  group('Phase 1 SQL contract (read from the script, not the database)', () {
    final sql = _read(
      'supabase_schema/supabase_schema_program_rework_p1_rules_cleanup.sql',
    );
    // Executable statements only: comment lines (such as the verification
    // examples at the bottom) are not part of what runs.
    final code = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');

    test('status is limited to active / completed and refuses to guess', () {
      expect(sql, contains("CHECK (status IN ('active', 'completed'))"));
      expect(sql, contains("status NOT IN ('active', 'completed')"));
    });

    test('the delete guard exists (Phase 5 completion then blocks every delete)', () {
      expect(sql, contains('FUNCTION public.protect_program_from_delete'));
      expect(sql, contains('BEFORE DELETE ON public.cooperative_programs'));
    });

    test('direct deletes of member and purchase rows are blocked, cascades are not', () {
      expect(sql, contains('auth.uid() IS NULL OR pg_trigger_depth() > 1'));
      expect(sql, contains('BEFORE DELETE ON public.program_members'));
      expect(sql, contains('BEFORE DELETE ON public.program_product_purchases'));
    });

    test('a Completed program refuses new distributions, purchases and approvals', () {
      expect(sql, contains('no longer distributes items'));
      expect(sql, contains('no longer accepts purchases'));
      expect(sql, contains('no longer accepts new members'));
      // Existing members' processing is not blocked by these checks.
      expect(sql, isNot(contains('confirm_program_purchase')));
    });

    test('the three guarded functions keep their existing protections', () {
      final dist = sql.substring(
        sql.indexOf('FUNCTION public.distribute_program_benefit'),
        sql.indexOf('3b. request_program_purchase'),
      );
      expect(dist, contains('public.is_staff()'));
      expect(dist, contains('already received a distribution'));
      expect(dist, contains('FOR UPDATE'));
      final enroll = sql.substring(sql.indexOf('FUNCTION public.respond_to_program_enrollment_request'));
      expect(enroll, contains('public.is_staff()'));
      expect(enroll, contains('Request already reviewed'));
    });

    test('the old workflow functions only refuse, and change no data', () {
      for (final fn in [
        'record_program_thriving_outcome',
        'convert_program_distribution_to_loan',
        'confirm_program_return',
      ]) {
        final start = sql.indexOf('FUNCTION public.$fn');
        expect(start, greaterThan(0), reason: fn);
        final body = sql.substring(start, sql.indexOf(r'$function$;', start));
        expect(body, contains('RAISE EXCEPTION'), reason: fn);
        expect(body, isNot(contains('UPDATE ')), reason: fn);
        expect(body, isNot(contains('INSERT ')), reason: fn);
      }
    });

    test('Activities: only the Farmer function is dropped; the table is kept', () {
      expect(sql, contains('DROP FUNCTION IF EXISTS public.get_my_program_activities()'));
      expect(code, isNot(contains('DROP TABLE')));
      expect(code, isNot(contains('DELETE FROM')));
    });

    test('nothing in Product Sales pricing, patronage or contribution is touched', () {
      for (final s in [
        'member_contributions',
        'cooperative_annual_totals',
        'program_products SET',
        'unit_price =',
      ]) {
        expect(code.contains(s), isFalse, reason: s);
      }
    });
  });
}
