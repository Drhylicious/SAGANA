import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/presentation/widgets/program_history_sheet.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

ProgramHistoryEntry _e(String type, Map<String, dynamic> details, {String? subject = 'Ellen Rosal'}) =>
    ProgramHistoryEntry(
      at: DateTime(2026, 11, 4, 9),
      type: type,
      actorName: 'SP3',
      actorRole: 'admin',
      subjectName: subject,
      details: details,
    );

void main() {
  layoutRegressionTests();
  formAndFabTests();
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));
  final sql = _read('supabase_schema/supabase_schema_program_rework_p8_history_returns_assistance.sql');
  final p3 = _read('supabase_schema/supabase_schema_program_rework_p3_outcome_workflow.sql');

  group('History migration (SQL contract)', () {
    test('every branch of the last applied version is kept verbatim', () {
      final s = p3.indexOf('CREATE OR REPLACE FUNCTION public.get_program_history');
      final old = p3.substring(s, p3.indexOf('  ORDER BY 1 DESC;', s)).trimRight();
      final newer = sql.substring(sql.indexOf('CREATE OR REPLACE FUNCTION public.get_program_history'));
      expect(newer.contains(old), isTrue);
    });

    test('same signature, staff-only check and grants', () {
      expect(sql, contains('RETURNS TABLE ('));
      expect(sql, contains('IF NOT public.is_staff() THEN'));
      expect(sql, contains('REVOKE ALL ON FUNCTION public.get_program_history(uuid) FROM PUBLIC, anon;'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.get_program_history(uuid) TO authenticated;'));
    });

    test('it refuses to run over a live function that differs from the one it extends', () {
      expect(sql, contains('pg_get_functiondef'));
      expect(sql, contains('differs from the version this migration extends'));
    });

    test('it only reads: no table is written, changed or dropped', () {
      final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      for (final w in ['INSERT INTO', 'UPDATE ', 'DELETE FROM', 'DROP TABLE', 'ALTER TABLE']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });

    test('the new events come from the new tables, scoped to the program', () {
      for (final t in ['program_return_events', 'program_failure_resolutions', 'program_assistance_requests']) {
        expect(sql, contains('FROM $t'), reason: t);
      }
      for (final ev in [
        'return_opened', 'return_adjusted', 'return_receipt', 'return_closed',
        'resolution_recorded', 'assistance_requested', 'assistance_approved',
        'assistance_rejected', 'assistance_cancelled',
      ]) {
        expect(sql, contains("'$ev'"), reason: ev);
      }
    });
  });

  group('History wording (English and Tagalog)', () {
    final cases = <ProgramHistoryEntry>[
      _e('return_opened', {'after': 10, 'unit': 'kg', 'crop': 'Peanut'}),
      _e('return_adjusted', {'before': 10, 'after': 8, 'unit': 'kg', 'reason': 'Drought'}),
      _e('return_receipt', {'quantity': 4, 'unit': 'kg', 'crop': 'Peanut', 'reason': 'First batch'}),
      _e('return_closed', {'before': 10, 'after': 6, 'unit': 'kg', 'reason': 'Crop lost'}),
      _e('resolution_recorded', {'resolution': 'eligible_for_reassessment', 'note': 'Next season'}),
      _e('resolution_recorded', {'resolution': 'pending_cooperative_decision', 'default': true}),
      _e('assistance_requested', {'request_number': 'LQR-1', 'items': '2 kg Peanut Seed'}),
      _e('assistance_approved', {'reference': 'LRN-1'}),
      _e('assistance_rejected', {'note': 'No stock'}),
      _e('assistance_cancelled', {}),
    ];

    test('each new event has a real sentence, an icon, and no raw type code', () {
      for (final e in cases) {
        for (final l in [en, tl]) {
          final h = ProgramHistoryText.headline(l, e);
          expect(h, isNot(e.type), reason: e.type);
          expect(h, contains('Ellen Rosal'), reason: e.type);
        }
        expect(ProgramHistoryText.styleFor(e.type).icon, isNot(Icons.circle_outlined), reason: e.type);
      }
    });

    test('quantities, reasons and notes appear as detail lines', () {
      expect(
        ProgramHistoryText.changeLines(en, cases[1]),
        ['Quantity: 10 → 8 kg', '"Drought"'],
      );
      expect(
        ProgramHistoryText.changeLines(en, cases[3]),
        ['Received 6 of 10 kg', '"Crop lost"'],
      );
      expect(ProgramHistoryText.changeLines(en, cases[4]), ['"Next season"']);
      expect(ProgramHistoryText.changeLines(en, cases[6]), ['2 kg Peanut Seed']);
    });

    test('the automatic default resolution says so', () {
      expect(ProgramHistoryText.headline(en, cases[5]), contains('set automatically'));
      expect(ProgramHistoryText.headline(en, cases[5]), contains('Pending Cooperative Decision'));
    });

    test('earlier events read exactly as before', () {
      final created = ProgramHistoryEntry(at: DateTime(2026, 1, 1), type: 'program_created');
      expect(ProgramHistoryText.headline(en, created), en.programHistCreated);
      final fin = _e('outcome_finalized', {'outcome': 'failed'});
      expect(ProgramHistoryText.headline(en, fin), contains('Ellen Rosal'));
    });
  });

}

// The app theme gives Elevated and Outlined buttons an infinite minimum width.
// Inside a Row (or a Wrap, where it would fill the line) that breaks layout, so
// those buttons must override it.
void layoutRegressionTests() {
  group('Buttons placed in rows keep a finite width', () {
    test('Save price, Distribute and the return actions override the theme width', () {
      final products = _read('lib/presentation/screens/admin/program_products_screen.dart');
      expect(products, contains('minimumSize: const Size(0, 44)'));
      final mgmt = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(mgmt, contains('ElevatedButton.styleFrom(minimumSize: const Size(0, 44))'));
      final panel = _read('lib/presentation/widgets/program_return_panel.dart');
      expect('minimumSize: const Size(0, '.allMatches(panel).length, greaterThanOrEqualTo(2));
    });
  });
}

void formAndFabTests() {
  group('Edit follows the creation rules; Manage Products uses a round + button', () {
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');

    test('the form has no lenient mode: every required field must be filled to save', () {
      expect(screen.contains('strict'), isFalse);
      expect(screen, contains('final photoOk = hasPhoto();'));
      expect(screen, contains('programMgmtFillRequired'));
    });

    test('Member Discount is required for Product Sales (0 means none)', () {
      expect(screen, contains('programMgmtMemberDiscountRequired'));
      expect(screen, contains('existing != null && existing.isSalesProgram'));
    });

    test('Distribution fields are required on edit too', () {
      for (final k in [
        'programMgmtSourcesRequired',
        'programMgmtBudgetRequired',
        'programMgmtDescRequired',
        'programMgmtNameRequired',
        'programMgmtTypeRequired',
      ]) {
        expect(screen, contains(k), reason: k);
      }
    });

    test('the products page uses the same floating + button as the other management screens', () {
      final page = _read('lib/presentation/screens/admin/program_products_screen.dart');
      expect(page, contains('floatingActionButton'));
      expect(page.contains('CircleBorder'), isFalse);
      expect(page, contains('AppConstants.primaryGreen'));
      expect(page.contains('ElevatedButton.icon'), isFalse);
    });
  });
}
