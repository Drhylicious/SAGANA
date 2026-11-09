import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/models/program_outcome_model.dart';
import 'package:sagana/presentation/widgets/request_card.dart';

import 'support/ignore_font_errors.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// Executable SQL only (comment lines removed).
String _code(String p) =>
    _read(p).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

Map<String, dynamic> _arb(String f) =>
    jsonDecode(_read('lib/core/l10n/$f')) as Map<String, dynamic>;

OutcomeReport _report({
  String status = 'pending_validation',
  String? reviewDecision,
  String? reviewedBy,
  String? verifiedBy,
  DateTime? verifiedAt,
  String? finalOutcome,
}) => OutcomeReport.fromMap({
  'id': 'r1',
  'program_member_id': 'm1',
  'program_id': 'p1',
  'program_name': 'Eggplant Seeds',
  'farmer_id': 'f1',
  'farmer_name': 'Juan',
  'reported_outcome': 'successful',
  'explanation': 'Grew well',
  'quantity_harvested': 120,
  'quantity_unit': 'kg',
  'status': status,
  'submitted_at': '2026-11-04T00:00:00Z',
  'review_decision': reviewDecision,
  'reviewed_by': reviewedBy,
  'verified_by': verifiedBy,
  'verified_at': verifiedAt?.toIso8601String(),
  'final_outcome': finalOutcome,
  'photos': [
    {'id': 'a', 'path': 'f1/a.jpg', 'by': 'farmer'},
    {'id': 'b', 'path': 'o1/b.jpg', 'by': 'staff'},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // ───────────────────────── Phase 2 ─────────────────────────
  group('Phase 2 — Enrollment and Purchase Requests', () {
    testWidgets('a request card shows the essentials, and opens inline on tap', (tester) async {
      await runIgnoringFontErrors(() async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: RequestCard(
                  leading: RequestAvatar(name: 'Juan Cruz', color: Colors.green),
                  title: 'Juan Cruz',
                  subtitle: 'Peanut Cookies',
                  summary: '2.0 pack · ₱450.00',
                  statusLabel: 'Pending',
                  statusColor: Colors.amber,
                  details: [RequestDetailRow(label: 'Quantity', value: '2.0 pack')],
                  actions: Text('ACTIONS HERE'),
                ),
              ),
            ),
          ),
        );
        // Essentials up front; details and actions are hidden.
        expect(find.text('Juan Cruz'), findsWidgets);
        expect(find.text('2.0 pack · ₱450.00'), findsOneWidget);
        expect(find.text('Quantity'), findsNothing);
        expect(find.text('ACTIONS HERE'), findsNothing);

        await tester.tap(find.text('Peanut Cookies'));
        await tester.pumpAndSettle();
        expect(find.text('Quantity'), findsOneWidget);
        expect(find.text('ACTIONS HERE'), findsOneWidget);

        await tester.tap(find.text('Peanut Cookies'));
        await tester.pumpAndSettle();
        expect(find.text('ACTIONS HERE'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    test('Enrollment tabs are Pending and Joined (the Purchase Requests screen no longer exists)', () {
      final en = _arb('app_en.arb');
      expect(en['reqTabPending'], 'Pending ({count})');
      expect(en['reqTabEnrolled'], 'Joined ({count})');
      final enroll = _read('lib/presentation/screens/admin/program_enrollment_requests_screen.dart');
      expect(enroll, contains('reqTabEnrolled'));
      expect(enroll, isNot(contains("'Reviewed'")));
      expect(enroll, isNot(contains('reqFilterDeclined')), reason: 'Declined was removed (follows Market Linking)');
      expect(File('lib/presentation/screens/admin/program_purchase_review_screen.dart').existsSync(), isFalse);
    });

    test('the join requests screen works inline: no modal dialog for details or for the actions', () {
      for (final f in [
        'lib/presentation/screens/admin/program_enrollment_requests_screen.dart',
      ]) {
        final src = _read(f);
        expect(src.contains('showManagementModal'), isFalse, reason: f);
        expect(src.contains('showDialog'), isFalse, reason: f);
        expect(src, contains('RequestCard'), reason: f);
      }
    });

    test('a join request is approved, never declined: no decline button and no reason box', () {
      final src = _read('lib/presentation/screens/admin/program_enrollment_requests_screen.dart');
      expect(src, contains('approveEnrollmentRequest'));
      expect(src.contains('reqDecline'), isFalse);
      expect(src.contains('reqNeedReason'), isFalse);
      expect(src.contains('respondToEnrollmentRequest'), isFalse);
      final da = _read('lib/presentation/screens/admin/da_amad_enrollment_screen.dart');
      expect(da, contains('approveEnrollment'));
      expect(da.contains('mlEnrollDecline'), isFalse);
      // Purchase Requests are gone from Program Management: Cooperative orders are handled in Marketplace > Orders.
      expect(File('lib/presentation/screens/admin/program_purchase_review_screen.dart').existsSync(), isFalse);
    });
  });

  // ───────────────────────── Phase 3 ─────────────────────────
  group('Phase 3 — outcome workflow (models)', () {
    test('a report moves through the stages', () {
      expect(_report().stage, OutcomeStage.awaitingBoth);
      expect(_report(reviewDecision: 'validated', reviewedBy: 'm').stage, OutcomeStage.awaitingVerification);
      expect(_report(verifiedBy: 'o', verifiedAt: DateTime(2026, 11, 5)).stage, OutcomeStage.awaitingReview);
      expect(
        _report(reviewDecision: 'validated', reviewedBy: 'm', verifiedBy: 'o', verifiedAt: DateTime(2026, 11, 5)).stage,
        OutcomeStage.readyToFinalize,
      );
      expect(_report(status: 'returned', reviewDecision: 'returned').stage, OutcomeStage.returned);
      expect(_report(status: 'finalized', finalOutcome: 'successful').stage, OutcomeStage.finalized);
    });

    test('the same person may review, verify and decide: no one is blocked, and both names are kept', () {
      final both = _report(
        reviewDecision: 'validated',
        reviewedBy: 'me',
        verifiedBy: 'me',
        verifiedAt: DateTime(2026, 11, 5),
      );
      expect(both.stage, OutcomeStage.readyToFinalize);
      expect(both.reviewedBy, 'me');
      expect(both.verifiedBy, 'me');
    });

    test('Farmer photos and the Officer\'s field photos are kept apart', () {
      final r = _report();
      expect(r.farmerPhotos.map((p) => p.path), ['f1/a.jpg']);
      expect(r.fieldPhotos.map((p) => p.path), ['o1/b.jpg']);
    });

    test('the current report for a member: in progress beats returned; newest returned otherwise', () {
      MyOutcomeReport mk(String id, String status) => MyOutcomeReport.fromMap({
        'id': id,
        'program_member_id': 'm1',
        'program_id': 'p',
        'reported_outcome': 'failed',
        'status': status,
        'submitted_at': '2026-11-04T00:00:00Z',
      });
      MyOutcomeReport? pick(List<MyOutcomeReport> l) => currentReportFor<MyOutcomeReport>(
        l,
        'm1',
        memberOf: (r) => r.programMemberId,
        isReturned: (r) => r.isReturned,
      );
      expect(pick([mk('new', 'pending_validation'), mk('old', 'returned')])!.id, 'new');
      expect(pick([mk('newest', 'returned'), mk('older', 'returned')])!.id, 'newest');
      expect(pick([]), isNull);
    });
  });

  group('Phase 3 — outcome workflow (SQL contract, read from the script)', () {
    const path = 'supabase_schema/supabase_schema_program_rework_p3_outcome_workflow.sql';
    final code = _code(path);

    String fn(String name) {
      final start = code.indexOf('FUNCTION public.$name');
      expect(start, greaterThan(0), reason: name);
      return code.substring(start, code.indexOf(r'$function$;', start));
    }

    test('Phase 3 as first written had separation of duties; p13 removes it (see the p13 tests)', () {
      expect(code, contains('outcome_reviewer_is_not_verifier'));
      final p13 = _code('supabase_schema/supabase_schema_program_rework_p13_outcome_any_staff.sql');
      expect(p13, contains('DROP CONSTRAINT IF EXISTS outcome_reviewer_is_not_verifier'));
    });

    test('there is no override or exception path', () {
      expect(code.toLowerCase(), isNot(contains('override')));
      expect(code, isNot(contains('p_force')));
    });

    test('Managers and Officers may review and finalize (verification: see the p13 tests)', () {
      expect(fn('review_program_outcome'), contains('public.is_staff()'));
      expect(fn('finalize_program_outcome'), contains('public.is_staff()'));
    });

    test('finalizing needs BOTH steps and creates no loan, repayment or stock movement', () {
      final f = fn('finalize_program_outcome');
      expect(f, contains("review_decision IS DISTINCT FROM 'validated'"));
      expect(f, contains('verified_by IS NULL'));
      for (final banned in ['farmer_loans', 'issue_loan', 'loan_requests', 'inventory_transactions', 'cooperative_inventory']) {
        expect(code.contains(banned), isFalse, reason: 'the workflow must not touch $banned');
      }
    });

    test('1 to 5 Farmer photos, every one in the caller\'s folder and really uploaded', () {
      expect(fn('submit_program_outcome_report'), contains('_outcome_check_paths(p_photo_paths, 1, 5)'));
      final helper = code.substring(code.indexOf('FUNCTION public._outcome_check_paths'));
      expect(helper, contains("auth.uid()::TEXT || '/%'"));
      expect(helper, contains('storage.objects'));
      expect(code, contains('at most 5 photos'));
    });

    test('a successful report needs a harvest; a failed one needs a cause (also a table constraint)', () {
      expect(code, contains('outcome_success_needs_harvest'));
      expect(code, contains('outcome_failure_needs_cause'));
    });

    test('evidence is private and a Farmer sees no staff identity', () {
      expect(code, contains("VALUES ('program_evidence', 'program_evidence', FALSE"));
      final mine = code.substring(code.indexOf('FUNCTION public.get_my_outcome_reports'), code.indexOf('FUNCTION public.get_program_outcome_reports'));
      // What the Farmer receives is the set of quoted keys in the result; a
      // staff column may be read only to compute a yes/no flag.
      for (final banned in ["'reviewed_by'", "'verified_by'", "'finalized_by'", "'reviewed_by_name'", "'verified_by_name'", "'review_note'", 'user_information', 'full_name']) {
        expect(mine.contains(banned), isFalse, reason: 'a Farmer must not receive $banned');
      }
    });

    test('the three staff actions are governed by the Officer permission gate', () {
      for (final n in ['review_program_outcome', 'verify_program_outcome', 'finalize_program_outcome']) {
        expect(code, contains("('rpc',   '$n',"));
      }
    });

    test('History reads the report rows and does not show a recorded outcome twice', () {
      final h = code.substring(code.indexOf('FUNCTION public.get_program_history'));
      expect(h, contains("'outcome_submitted'"));
      expect(h, contains("'outcome_finalized'"));
      expect(h, contains('NOT EXISTS (SELECT 1 FROM program_outcome_reports'));
    });
  });

  group('Phase 3 — the screens', () {
    test('the Farmer picks Successful or Failed, adds 1-5 photos from camera or gallery', () {
      final screen = _read('lib/presentation/screens/farmer/report_outcome_screen.dart');
      expect(screen, contains("'successful'"));
      expect(screen, contains("'failed'"));
      expect(screen, contains('OutcomePhotoPicker'));
      expect(screen, contains('_photos.isNotEmpty'));
      final picker = _read('lib/presentation/widgets/outcome_photo_picker.dart');
      expect(picker, contains('ImageSource.camera'));
      expect(picker, contains('ImageSource.gallery'));
      expect(picker, contains('this.max = 5'));
    });

    test('Members is a full page and distributes inline, with no modal on top', () {
      final s = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(s, contains('class ProgramMembersScreen'));
      expect(s, contains('AppRoutes.programMembers'));
      expect(s, contains('_distributePanel'));
      expect(s.contains('_showDistributeSheet'), isFalse);
    });

    test('the review page offers every step to a Manager or Officer with Manage access', () {
      final d = _read('lib/presentation/screens/admin/program_outcome_detail_screen.dart');
      expect(d.contains('wouldBreakSeparation'), isFalse);
      expect(d.contains('outcOfficerOnly'), isFalse);
      expect(d.contains('_isOfficer'), isFalse);
      expect(d, contains('requireManage(context, StaffModule.dashboard)'));
    });

    test('every outcome string exists in English and Tagalog', () {
      final en = _arb('app_en.arb');
      final tl = _arb('app_tl.arb');
      final keys = en.keys.where((k) => !k.startsWith('@') && (k.startsWith('outc') || k.startsWith('req') || k.startsWith('purch') || k.startsWith('cat')));
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(tl.containsKey(k), isTrue, reason: '$k missing in app_tl.arb');
      }
    });
  });

  // ───────────────────────── Phase 4 ─────────────────────────
  group('Phase 4 — member pricing', () {
    test('the member price: ₱1,000 at 10% is ₱900; a non-member or no discount pays the regular price', () {
      expect(memberUnitPrice(1000, 10), 900);
      expect(memberUnitPrice(1000, 0), 1000);
      expect(memberUnitPrice(99.99, 15), 84.99);
      expect(memberUnitPrice(500, 100), 0);
      expect(memberUnitPrice(500, 150), 0, reason: 'a discount above 100% is capped');
    });

    test('a purchase keeps regular price, discount and net separate, and they reconcile', () {
      final p = ProgramPurchase.fromMap({
        'id': 'x',
        'program_id': 'p',
        'product_id': 'pp',
        'farmer_id': 'f',
        'quantity': 2,
        'unit_price': 900,
        'total_amount': 1800,
        'regular_unit_price': 1000,
        'discount_percent': 10,
        'discount_amount': 200,
        'is_member_price': true,
        'status': 'paid',
        'requested_at': '2026-11-04T00:00:00Z',
      });
      expect(p.regularTotal, 2000);
      expect(p.discountAmount, 200);
      expect(p.netAmount, 1800);
      expect(p.regularTotal - p.discountAmount, p.netAmount);
      expect(p.hasDiscount, isTrue);
    });

    test('a purchase from before member pricing shows no discount and its own price', () {
      final p = ProgramPurchase.fromMap({
        'id': 'x',
        'program_id': 'p',
        'product_id': 'pp',
        'farmer_id': 'f',
        'quantity': 10,
        'unit_price': 50,
        'total_amount': 500,
        'status': 'paid',
        'requested_at': '2026-09-01T00:00:00Z',
      });
      expect(p.regularUnitPrice, isNull);
      expect(p.regularTotal, 500);
      expect(p.hasDiscount, isFalse);
    });

    test('the discount is configured per program and never hardcoded', () {
      final withDiscount = CooperativeProgram.fromMap({
        'id': 'p',
        'program_name': 'Cookies',
        'program_purpose': 'sales',
        'season_year': 2026,
        'member_discount_percent': 12.5,
      });
      expect(withDiscount.memberDiscountPercent, 12.5);
      expect(withDiscount.hasMemberDiscount, isTrue);
      final none = CooperativeProgram.fromMap({
        'id': 'p',
        'program_name': 'Cookies',
        'program_purpose': 'sales',
        'season_year': 2026,
      });
      expect(none.memberDiscountPercent, 0);
      expect(none.hasMemberDiscount, isFalse);
      for (final f in [
        'lib/data/models/cooperative_product_model.dart',
        'lib/data/repositories/farmer_program_repository.dart',
        'lib/data/repositories/program_repository.dart',
      ]) {
        final src = _read(f);
        expect(RegExp(r'[^\d.]10(\.0)?\s*/\s*100|\*\s*0\.9\b|\*\s*0\.90\b').hasMatch(src), isFalse,
            reason: '$f must not hardcode a 10% rate');
      }
    });

    const path = 'supabase_schema/supabase_schema_program_rework_p4_member_pricing.sql';
    final code = _code(path);

    test('SQL: the server decides the price from enrollment and snapshots it', () {
      final f = code.substring(code.indexOf('FUNCTION public.request_program_purchase'));
      expect(f, contains('member_discount_percent'));
      expect(f, contains('v_is_member'));
      expect(f, contains('regular_unit_price, discount_percent, discount_amount, is_member_price'));
      expect(f, contains('This program is Completed'));
      expect(f, contains('FOR SHARE'), reason: 'the stock checks are kept');
    });

    test('SQL: any active farmer can see products; enrollment is not required for visibility', () {
      expect(code, contains('DROP POLICY IF EXISTS "program_products: enrolled active farmers read available"'));
      final policy = code.substring(code.indexOf('CREATE POLICY "program_products: farmers read available"'));
      final body = policy.substring(0, policy.indexOf(');'));
      expect(body.contains('program_members'), isFalse);
      expect(body, contains("cp.status = 'active'"));
    });

    test('SQL: existing purchases are back-filled truthfully and nothing is hardcoded', () {
      expect(code, contains('regular_unit_price = unit_price'));
      expect(code, contains('discount_amount    = 0'));
      expect(RegExp(r"member_discount_percent\s*(=|DEFAULT)\s*10\b").hasMatch(code), isFalse);
      expect(code, contains('NUMERIC(5,2) NOT NULL DEFAULT 0'));
    });

    test('SQL: patronage, Balik-Tangkilik and contribution data are not touched', () {
      for (final banned in [
        'member_contributions',
        'cooperative_annual_totals',
        'member_sales_transactions',
        'cooperative_purchase_offers',
        'confirm_payout_decision',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });

    test('Purchase Patronage keeps counting only member-price purchases, as before', () {
      final agg = _read('lib/data/repositories/member_sales_aggregation.dart');
      expect(agg, contains(".eq('is_member_price', true)"));
      expect(agg, contains('fetchMemberProgramPurchaseBreakdown'));
      // The pool maths itself is unchanged: still the same formula in the same place.
      final bt = _read('lib/data/repositories/balik_tangkilik_repository.dart');
      expect(bt, contains('distributableProgramSurplus * purchaseShare'));
    });

    test('every farmer finds a Product Sales program\'s products in the Marketplace, not behind a program Shop button', () {
      final browse = _read('lib/presentation/screens/farmer/browse_programs_screen.dart');
      expect(browse.contains('onViewProducts'), isFalse);
      expect(browse.contains("entry.enrollmentStatus == 'active')"), isFalse);
      expect(_read('lib/presentation/screens/farmer/farmer_marketplace_tab.dart'), contains('fetchCooperativeProducts'));
    });
  });
}
