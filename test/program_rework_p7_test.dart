import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/program_assistance_model.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final sql = _read('supabase_schema/supabase_schema_program_rework_p7_failed_program_assistance.sql');
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  String fn(String name, String until) {
    final start = sql.indexOf('FUNCTION public.$name');
    expect(start, greaterThan(0), reason: name);
    final end = sql.indexOf(until, start + 10);
    return sql.substring(start, end < 0 ? sql.length : end);
  }

  group('Assistance model', () {
    test('a request carries its numbers, items and status', () {
      final r = AssistanceRequest.fromMap({
        'id': 'a1',
        'request_number': 'LQR-20261104-A001',
        'assistance_reference': 'LRN-20261104-A003',
        'program_member_id': 'm1',
        'program_name': 'Peanut Seed Distribution',
        'status': 'approved',
        'created_at': '2026-11-04T01:00:00Z',
        'items': [
          {'item_name': 'Peanut Seed', 'unit': 'kg', 'quantity': 2.5},
        ],
      });
      expect(r.isApproved, isTrue);
      expect(r.assistanceReference, startsWith('LRN-'));
      expect(r.items.single.quantity, 2.5);
    });

    test('a rejected request shows the reason to the Farmer', () {
      final r = AssistanceRequest.fromMap({
        'id': 'a2',
        'request_number': 'LQR-1',
        'program_member_id': 'm1',
        'status': 'rejected',
        'rejection_reason': 'Not enough stock this season',
        'created_at': '2026-11-04T01:00:00Z',
      });
      expect(r.isRejected, isTrue);
      expect(r.reviewNote, 'Not enough stock this season');
    });

    test('an option may ask only when nothing blocks it', () {
      expect(const AssistanceOption(programMemberId: 'm', programName: 'p').canRequest, isTrue);
      expect(
        const AssistanceOption(programMemberId: 'm', programName: 'p', blocker: 'pending').canRequest,
        isFalse,
      );
    });
  });

  group('Phase 6 SQL contract (read from the script)', () {
    test('assistance is separate from loans: no loan table is read or written', () {
      for (final t in ['farmer_loans', 'loan_requests', 'loan_payments', 'issue_loan', 'monthly_payment']) {
        expect(code.contains(t), isFalse, reason: t);
      }
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.program_assistance_requests'));
    });

    test('only a FAILED outcome of the caller may ask; a resolution never blocks', () {
      final blocker = fn('_assistance_blocker', r'$function$;');
      expect(blocker, contains("COALESCE(v_m.distribution_outcome, '') <> 'failed'"));
      expect(blocker, contains('v_m.farmer_id IS DISTINCT FROM p_farmer'));
      expect(blocker.contains('program_failure_resolutions'), isFalse);
    });

    test('items come from the active loan catalog and must be in stock', () {
      final submit = fn('submit_assistance_request', r'$function$;');
      expect(submit, contains('lim.is_loan_eligible'));
      expect(submit, contains('ci.is_active'));
      expect(submit, contains('quantity_on_hand - v_ci.quantity_reserved < v_qty'));
      expect(submit, contains('ASSIST_ITEMS'));
      expect(submit, contains('next_loan_request_reference'));
    });

    test('approval re-checks and deducts the stock once, with a ledger row and an LRN', () {
      final review = fn('review_assistance_request', r'$function$;');
      expect(review, contains('FOR UPDATE'));
      expect(review, contains('quantity_on_hand = quantity_on_hand - v_it.quantity'));
      expect(review, contains('INSERT INTO inventory_transactions'));
      expect(review, contains('next_loan_reference'));
      expect(review, contains("v_r.status <> 'pending'"));
      expect(review, contains('Give a reason when rejecting'));
    });

    test('there is at most one pending request per failed outcome', () {
      expect(sql, contains('CREATE UNIQUE INDEX IF NOT EXISTS program_assistance_one_pending'));
      expect(sql, contains("WHERE status = 'pending'"));
    });

    test('requests are kept for good', () {
      expect(sql, contains('BEFORE DELETE ON public.program_assistance_requests'));
      expect(code, isNot(contains('DELETE FROM')));
      expect(code, isNot(contains('DROP TABLE')));
    });

    test('a Farmer sees no staff identity', () {
      final mine = fn('get_my_assistance_requests', r'$$;');
      expect(mine.contains('reviewed_by_name'), isFalse);
      expect(mine, contains('auth.uid()'));
    });

    test('reviewing is a Loans action in the Officer gate', () {
      expect(sql, contains("('rpc',   'review_assistance_request',     'loans')"));
    });
  });

  group('Friendly messages', () {
    test('assistance refusals are translated', () {
      expect(messageForDatabaseText(en, 'ASSIST_NOT_ELIGIBLE: x'), en.errAssistNotEligible);
      expect(messageForDatabaseText(en, 'ASSIST_PENDING: x'), en.errAssistPending);
      expect(messageForDatabaseText(en, 'ASSIST_ITEMS: x'), en.errAssistItems);
      expect(
        messageForDatabaseText(en, 'Insufficient stock for Peanut Seed: 1 on hand, 3 requested'),
        en.errNoStock,
      );
    });
  });

  group('Wiring', () {
    test('Loan Requests links to the assistance list and the screen checks the Loans module', () {
      final loans = _read('lib/presentation/screens/admin/loan_requests_screen.dart');
      expect(loans, contains('AppRoutes.assistanceRequests'));
      final screen = _read('lib/presentation/screens/admin/assistance_requests_screen.dart');
      expect('requireManage(context, StaffModule.loans)'.allMatches(screen).length, 2);
      expect(screen, contains('assistBadge'));
    });

    test('the Farmer asks from My Programs, only where the database allows', () {
      final mine = _read('lib/presentation/screens/farmer/my_programs_screen.dart');
      expect(mine, contains('opt.canRequest'));
      expect(mine, contains('AppRoutes.requestAssistance'));
      final screen = _read('lib/presentation/screens/farmer/request_assistance_screen.dart');
      expect(screen, contains('fetchLoanableItems'));
    });
  });

  group('Farmer catalog (now the Marketplace\'s Cooperative Products)', () {
    final tab = _read('lib/presentation/screens/farmer/farmer_marketplace_tab.dart');
    final detail = _read('lib/presentation/screens/farmer/cooperative_product_details_screen.dart');

    test('has search, category chips and the same two-column grid as every product screen', () {
      expect(tab, contains('buyerBrowseSearchHint'));
      expect(tab, contains('_buildCategoryChips'));
      // The grid is defined once, in the shared ProductCard (two columns), so Buyer Browse and the
      // Farmer Marketplace (listings and Cooperative Products) are the same size.
      expect(tab, contains('ProductCard.gridDelegate'));
      expect(File('lib/presentation/widgets/product_card.dart').readAsStringSync(),
          contains('crossAxisCount: 2'));
    });

    test('an enrolled member sees the member price with the regular price struck through', () {
      expect(detail, contains('TextDecoration.lineThrough'));
      expect(detail, contains('cpYouPayMember'));
    });

    test('anyone else sees the regular price and the member price hint; no Enroll button', () {
      expect(tab, contains('cpMemberPriceHint'));
      expect(detail, contains('cpMembersPay'));
      expect(detail.contains("label: 'Enroll"), isFalse);
    });

    test('the Program Details page explains the membership benefit', () {
      final details = _read('lib/presentation/screens/farmer/program_details_screen.dart');
      expect(details, contains('catMemberBenefitTitle'));
      expect(details, contains('catMemberBenefitEnrolled'));
      expect(details, contains('catMemberBenefitNotEnrolled'));
    });
  });
}
