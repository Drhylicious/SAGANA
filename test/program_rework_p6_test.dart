import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/program_return_model.dart';
import 'package:sagana/presentation/widgets/program_return_panel.dart';

import 'support/ignore_font_errors.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

Map<String, dynamic> _returnMap({
  double due = 10,
  double received = 4,
  String status = 'partial',
  double original = 10,
}) => {
  'id': 'r1',
  'program_id': 'p1',
  'program_member_id': 'm1',
  'program_name': 'Peanut Seed Distribution',
  'farmer_name': 'Ellen Rosal',
  'crop_name': 'Peanut',
  'unit': 'kg',
  'original_quantity': original,
  'due_quantity': due,
  'received_quantity': received,
  'status': status,
  'underreport_flag': false,
  'receipts': [
    {'id': 'x1', 'quantity': 4, 'received_at': '2026-11-03T08:00:00Z', 'recorded_by_name': 'SP3'},
  ],
  'events': [
    {'event_type': 'created', 'quantity_after': 10, 'created_at': '2026-11-01T08:00:00Z'},
    {'event_type': 'receipt', 'quantity': 4, 'quantity_after': 4, 'created_at': '2026-11-03T08:00:00Z'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));
  final sql = _read('supabase_schema/supabase_schema_program_rework_p6_harvest_return_resolutions.sql');
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  group('Return model', () {
    test('parses quantities, receipts and history', () {
      final r = ProgramReturn.fromMap(_returnMap());
      expect(r.isOpen, isTrue);
      expect(r.remaining, 6);
      expect(r.receipts.single.quantity, 4);
      expect(r.events.map((e) => e.type), ['created', 'receipt']);
    });

    test('an adjusted return remembers the original quantity', () {
      final r = ProgramReturn.fromMap(_returnMap(due: 8, original: 10));
      expect(r.wasAdjusted, isTrue);
      expect(r.originalQuantity, 10);
    });

    test('received in full or closed short is no longer open', () {
      expect(ProgramReturn.fromMap(_returnMap(status: 'received', received: 10)).isOpen, isFalse);
      expect(ProgramReturn.fromMap(_returnMap(status: 'closed_short')).isOpen, isFalse);
    });

    test('quantities print without trailing zeros', () {
      expect(formatReturnQuantity(5), '5');
      expect(formatReturnQuantity(2.5), '2.5');
      expect(formatReturnQuantity(2.25), '2.25');
    });

    test('the four resolutions are exactly the ones in the proposal', () {
      expect(FailedResolution.all, [
        'closed_no_further_obligation',
        'eligible_for_reassessment',
        'referred_for_loan_assessment',
        'pending_cooperative_decision',
      ]);
    });

    test('the Farmer snapshot holds statuses and quantities, no staff identity', () {
      final s = MyReturnsSnapshot.fromMap({
        'returns': [
          {
            'program_member_id': 'm1',
            'crop_name': 'Peanut',
            'unit': 'kg',
            'due_quantity': 10,
            'received_quantity': 4,
            'status': 'partial',
          },
        ],
        'resolutions': [
          {'program_member_id': 'm2', 'resolution': 'pending_cooperative_decision'},
        ],
      });
      expect(s.byMember['m1']!.receivedQuantity, 4);
      expect(s.resolutionByMember['m2'], 'pending_cooperative_decision');
    });
  });

  group('Proposal 12 SQL contract (read from the script)', () {
    test('a quantity change needs a reason, and keeps the original and the history', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.adjust_program_return'));
      expect(fn, contains('RETURN_REASON'));
      expect(fn, contains("'adjusted'"));
      expect(code, contains('original_quantity'));
      expect(fn, isNot(contains('original_quantity =')));
    });

    test('inventory moves only for quantities received, never for the amount due', () {
      final receipt = sql.substring(
        sql.indexOf('FUNCTION public.record_program_return_receipt'),
        sql.indexOf('FUNCTION public.close_program_return'),
      );
      expect(receipt, contains('quantity_on_hand + p_quantity'));
      expect(receipt, contains("'harvest_received'"));
      expect(receipt, contains('RETURN_OVER_RECEIPT'));
      for (final other in ['FUNCTION public.adjust_program_return', 'FUNCTION public.close_program_return']) {
        final start = sql.indexOf(other);
        final body = sql.substring(start, sql.indexOf(r'$function$;', start));
        expect(body.contains('cooperative_inventory'), isFalse, reason: other);
      }
    });

    test('closing short needs a reason and applies no penalty, deduction or loan', () {
      final fn = sql.substring(
        sql.indexOf('FUNCTION public.close_program_return'),
        sql.indexOf('FUNCTION public.record_failed_resolution'),
      );
      expect(fn, contains('RETURN_REASON'));
      for (final s in ['farmer_loans', 'loan_requests', 'member_contributions', 'penalt']) {
        expect(fn.toLowerCase().contains(s), isFalse, reason: s);
      }
      expect(sql, contains('program_returns_closed_has_reason'));
    });

    test('history is permanent: events, receipts and resolutions cannot change; returns cannot be deleted', () {
      expect(sql, contains('BEFORE UPDATE OR DELETE ON public.program_return_receipts'));
      expect(sql, contains('BEFORE UPDATE OR DELETE ON public.program_return_events'));
      expect(sql, contains('BEFORE UPDATE OR DELETE ON public.program_failure_resolutions'));
      expect(sql, contains('BEFORE DELETE ON public.program_returns'));
      expect(code, isNot(contains('DELETE FROM')));
      expect(code, isNot(contains('DROP TABLE')));
    });

    test('a Failed outcome starts at Pending Cooperative Decision; choosing one needs a note', () {
      expect(sql, contains("'pending_cooperative_decision'"));
      final fn = sql.substring(sql.indexOf('FUNCTION public.record_failed_resolution'));
      expect(fn, contains('RESOLUTION_INVALID'));
      expect(fn, contains('INSERT INTO program_failure_resolutions'));
      // A resolution only records: it writes nothing else.
      final body = fn.substring(0, fn.indexOf(r'$function$;'));
      expect(body.contains('UPDATE '), isFalse);
      expect(body.contains('farmer_loans'), isFalse);
    });

    test('the underreporting tolerance is OFF by default and Manager-only', () {
      expect(sql, contains("VALUES ('underreport_tolerance_percent', NULL)"));
      final fn = sql.substring(sql.indexOf('FUNCTION public.set_underreport_tolerance'));
      expect(fn, contains("role = 'admin'"));
      expect(sql, contains('IF v_tol IS NOT NULL'));
    });

    test('an open return blocks Mark as Completed', () {
      expect(sql, contains("'open_returns'"));
      expect(sql, contains("r.status IN ('pending', 'partial')"));
    });

    test('a Farmer can read only their own returns, with no staff names or reasons', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.get_my_program_returns'));
      final body = fn.substring(0, fn.indexOf(r'$$;'));
      expect(body, contains('auth.uid()'));
      for (final s in ['closed_reason', 'decided_by_name', 'note', 'actor_name']) {
        expect(body.contains(s), isFalse, reason: s);
      }
    });

    test('every staff action is registered with the Officer permission gate', () {
      for (final n in [
        'adjust_program_return',
        'record_program_return_receipt',
        'close_program_return',
        'record_failed_resolution',
      ]) {
        expect(sql, contains("('rpc',   '$n',"), reason: n);
      }
    });
  });

  group('Friendly messages for the new codes', () {
    test('return and resolution refusals are translated', () {
      expect(messageForDatabaseText(en, 'RETURN_CLOSED: x'), en.errReturnClosed);
      expect(messageForDatabaseText(en, 'RETURN_OVER_RECEIPT: x'), en.errReturnOverReceipt);
      expect(messageForDatabaseText(en, 'RETURN_REASON: x'), en.errReturnReason);
      expect(messageForDatabaseText(tl, 'RETURN_REASON: x'), tl.errReturnReason);
    });
  });

  group('Return widgets', () {
    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
        ),
      );
      await tester.pump();
    }

    testWidgets('the return block shows progress and opens Manage', (tester) async {
      await runIgnoringFontErrors(() async {
        var opened = false;
        await show(
          tester,
          ReturnSummaryBlock(
            ret: ProgramReturn.fromMap(_returnMap()),
            onManage: () => opened = true,
          ),
        );
        expect(find.text('Partially received'), findsOneWidget);
        expect(find.textContaining('4 of 10 kg received'), findsOneWidget);
        await tester.tap(find.text('Manage return'));
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a Failed outcome defaults to Pending Cooperative Decision', (tester) async {
      await runIgnoringFontErrors(() async {
        await show(tester, ResolutionSummaryBlock(resolution: null, onSet: () {}));
        expect(find.text('Pending Cooperative Decision'), findsOneWidget);
        expect(find.text('Set resolution'), findsOneWidget);
      });
    });
  });

  group('Wiring', () {
    test('Members shows the return for Successful and the resolution for Failed', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(screen, contains('ReturnSummaryBlock'));
      expect(screen, contains('ResolutionSummaryBlock'));
    });

    test('every staff action in the sheets checks the Officer permission first', () {
      final panel = _read('lib/presentation/widgets/program_return_panel.dart');
      expect('requireManage(context, StaffModule.dashboard)'.allMatches(panel).length, 2);
    });

    test('the Farmer sees status only', () {
      final screen = _read('lib/presentation/screens/farmer/my_programs_screen.dart');
      expect(screen, contains('_returnStatus'));
      expect(screen, contains('_resolutionStatus'));
    });
  });
}
