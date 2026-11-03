import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/dashboard_summary_model.dart';
import 'package:sagana/data/models/farmer_transaction_model.dart';
import 'package:sagana/data/models/loan_request_model.dart';
import 'package:sagana/data/repositories/completed_order_dates.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

/// A code-only view of an SQL file (comment lines removed).
String sqlCode(String path) =>
    read(path).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Annual Yield and Annual Earnings', () {
    test('a year with no records shows zero, not an old total', () {
      final s = AnnualFarmSummary.empty(2027);
      expect(s.year, 2027);
      expect(s.earnings, 0);
      expect(s.yieldText, '0 kg');
      expect(s.hasYield, isFalse);
    });

    test('the yield is added per unit and never mixed', () {
      const s = AnnualFarmSummary(
        year: 2026,
        yieldByUnit: {'kg': 12500.5, 'sack': 3},
        marketplace: 0,
        cooperative: 0,
        informal: 0,
        marketLinking: 0,
      );
      expect(s.yieldText, '12,500.50 kg + 3 sack');
      expect(s.hasYield, isTrue);
    });

    test('earnings are the four channels added, each counted once', () {
      const s = AnnualFarmSummary(
        year: 2026,
        yieldByUnit: {},
        marketplace: 1200.50,
        cooperative: 3000,
        informal: 450.25,
        marketLinking: 6000,
      );
      expect(s.earnings, closeTo(10650.75, 0.0001));
    });

    test('each year is loaded on its own, bounded on both sides', () {
      final src = read('lib/data/repositories/dashboard_repository.dart');
      final from = src.indexOf('Future<Map<String, double>> _loadYearYield(int year)');
      final loaders = src.substring(from, src.indexOf('// ─── Recent Activity'));
      // Every query has an inclusive start and an EXCLUSIVE end, so a record
      // dated in the next year is never counted in this one.
      expect(RegExp("\\.gte\\('harvest_date'").hasMatch(loaders), isTrue);
      expect(RegExp("\\.lt\\('harvest_date'").hasMatch(loaders), isTrue);
      expect(RegExp("\\.lt\\('sale_date'").hasMatch(loaders), isTrue);
      expect(RegExp("\\.lt\\('completed_at'").hasMatch(loaders), isTrue);
      // Only completed sales: completed orders, the settled cooperative sale,
      // recorded informal sales and recorded Market Linking sales.
      expect(loaders, contains(".eq('status', 'completed')"));
      expect(loaders, contains("'market_linking_sales'"));
      expect(loaders, isNot(contains("'market_linking_programs'")));
    });

    test('Profile reads the same per-year figures as Home', () {
      final home = read('lib/data/repositories/dashboard_repository.dart');
      expect(home, contains('await _loadYearYield(now.year)'));
      expect(home, contains('await _loadYearEarnings(now.year)'));
      final profile = read('lib/presentation/screens/farmer/farmer_profile_screen.dart');
      expect(profile, contains('fetchAnnualSummary(_selectedYear)'));
      // Years can be stepped back; the future is not selectable.
      expect(profile, contains('canGoForward: year < currentYear'));
    });
  });

  group('A sale counts on the day it was completed', () {
    test('a marketplace order is dated by the buyer\'s receipt, not its creation', () {
      final d = CompletedOrderDates.of({
        'created_at': '2026-12-30T10:00:00Z',
        'received_at': '2027-01-02T08:00:00Z',
      });
      expect(d.toUtc(), DateTime.utc(2027, 1, 2, 8));
    });

    test('an order completed before received_at existed keeps its creation day', () {
      final d = CompletedOrderDates.of({'created_at': '2026-03-05T01:00:00Z'});
      expect(d.toUtc(), DateTime.utc(2026, 3, 5, 1));
    });

    test('the window covers received orders and the ones with no receipt date', () {
      final w = CompletedOrderDates.window(DateTime.utc(2026), DateTime.utc(2027))!;
      expect(w, contains('and(received_at.gte.2026-01-01T00:00:00.000Z,received_at.lt.2027-01-01T00:00:00.000Z)'));
      expect(w, contains('and(received_at.is.null,created_at.gte.2026-01-01T00:00:00.000Z,created_at.lt.2027-01-01T00:00:00.000Z)'));
      expect(CompletedOrderDates.window(null, null), isNull);
    });

    test('the Farmer\'s history, Home, Analytics and the Sales Report share the rule', () {
      for (final f in [
        'lib/data/repositories/farmer_transaction_repository.dart',
        'lib/data/repositories/dashboard_repository.dart',
        'lib/data/repositories/admin_reports_repository.dart',
      ]) {
        expect(read(f), contains('CompletedOrderDates'), reason: f);
      }
    });
  });

  group('Farmer Transaction History', () {
    test('keeps the original harvest unit and decimals, and adds the crop details', () {
      final t = FarmerTransactionModel(
        id: 't1',
        sellingType: 'marketplace',
        cropName: 'Tomato',
        quantityKg: 12.75,
        unit: 'crate',
        amount: 1275.50,
        transactionDate: DateTime.utc(2026, 10, 5),
      );
      final detailed = t.withDetails(
        marketType: 'open_market',
        cropCategory: 'Vegetable',
        batchNumber: 'BATCH-TOMATO-261001-A0001',
      );
      expect(detailed.unit, 'crate');
      expect(detailed.quantityKg, 12.75);
      expect(detailed.amount, 1275.50);
      expect(detailed.marketType, 'open_market');
      expect(detailed.cropCategory, 'Vegetable');
      expect(detailed.batchNumber, 'BATCH-TOMATO-261001-A0001');
    });

    test('every channel reads only completed sales', () {
      final src = read('lib/data/repositories/farmer_transaction_repository.dart');
      // A sale row exists only once the delivery was received.
      expect(src, contains(".from('member_sales_transactions')"));
      expect(src, contains(".eq('status', 'completed')")); // orders, and offers
      expect(src, contains(".from('market_linking_sales')"));
      expect(src, contains("where((r) => r['completed_at'] != null)"));
      // Never assumes kg: the unit comes from the sale row.
      expect(src, contains("unitOrDefault(r['unit'] as String?)"));
      // Each sale appears once.
      expect(src, contains('seen.add('));
    });

    test('the detail sheet shows the channel, market type and crop category', () {
      final src = read('lib/presentation/screens/farmer/farmer_transaction_history_screen.dart');
      for (final k in [
        'l10n.rptSellingChannel',
        'l10n.rptMarketType',
        'l10n.txnCropCategory',
        'l10n.rptQuantity',
        'l10n.rptAmount',
      ]) {
        expect(src, contains(k), reason: k);
      }
      // No staff identity is ever shown to a Farmer.
      expect(src, isNot(contains('recordedBy')));
      expect(src, isNot(contains('reviewer')));
    });
  });

  group('Loan requests', () {
    test('an item with no stock cannot be requested, and more than the stock is refused', () {
      const out = LoanableItem(
        loanItemId: 'l1',
        inventoryItemId: 'i1',
        itemName: 'Urea',
        category: 'Fertilizer',
        unit: 'bag',
        unitPrice: 1200,
        quantityOnHand: 0,
      );
      expect(out.inStock, isFalse);
      expect(out.allows(1), isFalse);

      const some = LoanableItem(
        loanItemId: 'l2',
        inventoryItemId: 'i2',
        itemName: 'Seeds',
        category: 'Seeds',
        unit: 'kg',
        unitPrice: 85.5,
        quantityOnHand: 4.5,
      );
      expect(some.inStock, isTrue);
      expect(some.allows(4.5), isTrue);
      expect(some.allows(4.51), isFalse);
      expect(some.allows(0), isFalse);
    });

    test('a Farmer\'s copy carries no staff identity; the staff copy names who decided', () {
      final farmer = LoanRequestModel.fromFarmerJson({
        'id': 'r1',
        'request_no': 'LQR-20261030-A001',
        'status': 'disapproved',
        'total_value': 2400,
        'requested_at': '2026-10-30T01:00:00Z',
        'decided_at': '2026-10-30T03:00:00Z',
        'decision_note': 'Out of stock this month',
        'items': [
          {'item_name': 'Urea', 'unit': 'bag', 'quantity': 2, 'unit_price': 1200, 'line_total': 2400},
        ],
      });
      expect(farmer.isDisapproved, isTrue);
      expect(farmer.reviewerName, isNull);
      expect(farmer.decisionNote, 'Out of stock this month');
      expect(farmer.items.single.label, 'Urea × 2 bag');

      final staff = LoanRequestModel.fromStaffRow(
        {
          'id': 'r1',
          'request_no': 'LQR-20261030-A001',
          'status': 'approved',
          'total_value': 2400,
          'requested_at': '2026-10-30T01:00:00Z',
          'reviewed_at': '2026-10-30T03:00:00Z',
          'farmer_id': 'f1',
          'loan_id': 'loan1',
          'loan_request_items': [
            {'item_name': 'Urea', 'unit': 'bag', 'quantity': 2, 'unit_price': 1200, 'line_total': 2400, 'inventory_item_id': 'i1'},
          ],
        },
        farmerName: 'Juan Dela Cruz',
        reviewerName: 'Maria Manager',
        loanReference: 'LRN-20261030-A001',
      );
      expect(staff.isApproved, isTrue);
      expect(staff.reviewerName, 'Maria Manager');
      expect(staff.loanReference, 'LRN-20261030-A001');
      expect(staff.items.single.inventoryItemId, 'i1');
    });

    test('a request line short on stock is flagged for the Manager / Officer', () {
      const item = LoanRequestItem(
        itemName: 'Urea',
        unit: 'bag',
        quantity: 5,
        unitPrice: 1200,
        lineTotal: 6000,
      );
      expect(item.withStock(10).shortOnStock, isFalse);
      expect(item.withStock(4.99).shortOnStock, isTrue);
      expect(item.shortOnStock, isFalse); // stock unknown: not flagged
    });

    test('the Farmer screen blocks zero stock and caps the quantity at the stock', () {
      final src = read('lib/presentation/screens/farmer/request_loan_screen.dart');
      expect(src, contains('item.inStock ? () => _editQuantity(item) : null'));
      expect(src, contains('DecimalInputFormatter(max: item.quantityOnHand)'));
      expect(src, contains('v > widget.item.quantityOnHand + 1e-9'));
    });

    test('the Farmer app only calls the request functions, never writes the tables', () {
      final src = read('lib/data/repositories/loan_repository.dart');
      for (final fn in ['list_loanable_items', 'submit_loan_request', 'get_my_loan_requests', 'cancel_loan_request']) {
        expect(src, contains("'$fn'"), reason: fn);
      }
      expect(src, isNot(contains(".from('loan_requests')")));
      expect(src, isNot(contains(".from('loan_request_items')")));
    });

    test('the Manager / Officer decide through the one database function', () {
      final src = read('lib/data/repositories/admin_loan_repository.dart');
      expect(src, contains("'review_loan_request'"));
      expect(src, contains("'p_decision': 'approve'"));
      expect(src, contains("'p_decision': 'disapprove'"));
      expect(src, isNot(contains(".from('loan_requests').update")));
    });
  });

  group('The capital-share loan requirement is removed', () {
    test('issue_loan no longer checks it', () {
      final sql = sqlCode('supabase_schema/supabase_schema_farmer_loan_requests.sql');
      final issue = sql.substring(
        sql.indexOf('CREATE OR REPLACE FUNCTION public.issue_loan('),
        sql.indexOf('CREATE OR REPLACE FUNCTION public.list_loanable_items'),
      );
      expect(issue, isNot(contains('minimum_capital_contribution')));
      expect(issue, isNot(contains('member_capital_shares')));
      expect(issue, isNot(contains('capital contribution')));
      // What still applies to a loan.
      expect(issue, contains('NOT public.is_staff()'));
      expect(issue, contains("v_farmer_status <> 'active'"));
      expect(issue, contains('Insufficient stock for %'));
      expect(issue, contains('idempotency_key'));
    });

    test('Issue New Loan has no capital gate left', () {
      final src = read('lib/presentation/screens/admin/issue_new_loan_screen.dart');
      expect(src, isNot(contains('_capitalEligible')));
      expect(src, isNot(contains('issueLoanCapitalBlocked')));
      expect(src, isNot(contains('issueLoanCapitalIneligible')));
      final repo = read('lib/data/repositories/admin_loan_repository.dart');
      expect(repo, isNot(contains('loan_capital_eligibility')));
      expect(repo, isNot(contains('member_capital_shares')));
    });

    test('nothing replaces it: no new eligibility rule in the request functions', () {
      final sql = sqlCode('supabase_schema/supabase_schema_farmer_loan_requests.sql');
      expect(sql, isNot(contains('loan_policy_settings')));
      expect(sql, isNot(contains("status = 'overdue'")));
    });
  });

  group('Loan requests: database rules', () {
    final sql = sqlCode('supabase_schema/supabase_schema_farmer_loan_requests.sql');

    test('stock is checked when the request is made, and again when it is approved', () {
      expect(sql, contains('is out of stock.'));
      expect(sql, contains('Not enough stock for %'));
      // Approval goes through issue_loan(), which locks the stock rows.
      expect(sql, contains('FROM public.issue_loan('));
      expect(sql, contains('FOR UPDATE'));
    });

    test('a request does not take stock; the loan does, exactly once', () {
      final submit = sql.substring(
        sql.indexOf('CREATE OR REPLACE FUNCTION public.submit_loan_request'),
        sql.indexOf('CREATE OR REPLACE FUNCTION public.cancel_loan_request'),
      );
      expect(submit, isNot(contains('UPDATE cooperative_inventory')));
      expect(submit, isNot(contains('inventory_transactions')));
      // A replay of the same approval returns the same loan (issue_loan is keyed).
      expect(sql, contains("'loan_request:' || p_request_id::TEXT"));
    });

    test('Farmers cannot read the tables or see who decided', () {
      expect(sql, contains('CREATE POLICY "loan_requests: staff reads"'));
      expect(sql, contains('USING (public.is_staff())'));
      final mine = sql.substring(
        sql.indexOf('CREATE OR REPLACE FUNCTION public.get_my_loan_requests'),
        sql.indexOf('CREATE OR REPLACE FUNCTION public.review_loan_request'),
      );
      expect(mine, isNot(contains('reviewed_by')));
    });

    test('the Manager / Officer who decides is recorded, with the time', () {
      expect(sql, contains('reviewed_by = auth.uid()'));
      expect(sql, contains('reviewed_at = NOW()'));
      expect(sql, contains("_wf_log('loan_request', p_request_id, 'approved'"));
      expect(sql, contains("_wf_log('loan_request', p_request_id, 'disapproved'"));
      expect(sql, contains("_wf_log('loan', NEW.id, 'issued'"));
      expect(sql, contains("'payment_recorded'"));
    });

    test('disapproval needs a reason; only a pending request can be decided or cancelled', () {
      expect(sql, contains('loan_requests_disapproval_needs_reason'));
      expect(sql, contains('Enter the reason for disapproving this request.'));
      expect(sql, contains("IF v_req.status <> 'pending'"));
    });
  });

  group('Layout on a narrow phone', () {
    testWidgets('the Cancel button never wraps letter by letter', (tester) async {
      await runIgnoringFontErrors(() async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 230,
                  child: ManagementModalActions(primaryLabel: 'Save Expense', onPrimary: () {}),
                ),
              ),
            ),
          ),
        );
        final size = tester.getSize(find.text('Cancel'));
        // One line of text is about 20px high; three stacked letters would be 60+.
        expect(size.height, lessThan(30));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the old 1:2 split wrapped Cancel; the equal split with tight padding does not', (tester) async {
      await runIgnoringFontErrors(() async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        Widget host(Widget row) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(child: SizedBox(width: 200, child: row)),
          ),
        );

        // As it was: Cancel gets a third of the row and the default 24px padding.
        await tester.pumpWidget(host(Row(children: [
          Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton(onPressed: () {}, child: const Text('Save Expense'))),
        ])));
        final before = tester.getSize(find.text('Cancel')).height;

        // As it is now: equal share, tight padding, one line that shrinks to fit.
        await tester.pumpWidget(host(Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Cancel', maxLines: 1, softWrap: false),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Save Expense', maxLines: 1, softWrap: false),
              ),
            ),
          ),
        ])));
        final after = tester.getSize(find.text('Cancel')).height;

        expect(before, greaterThan(40), reason: 'the old layout stacked the letters');
        expect(after, lessThan(30), reason: 'one line of text');
      });
    });

    test('the Add Expense dialog gives Cancel and Save an equal share', () {
      final src = read('lib/presentation/screens/farmer/my_expenses_screen.dart');
      final dialog = src.substring(src.indexOf('class _AddExpenseDialogState'));
      expect(dialog, isNot(contains('flex: 2')));
      expect(dialog, contains('AppLocalizations.of(context).cancel'));
      expect(dialog, contains('softWrap: false'));
    });
  });

  group('Localization', () {
    test('every new Farm Records string exists in English and Tagalog', () {
      Map<String, dynamic> arb(String lang) =>
          jsonDecode(read('lib/core/l10n/app_$lang.arb')) as Map<String, dynamic>;
      final en = arb('en');
      final tl = arb('tl');
      final fresh = en.keys.where(
        (k) => !k.startsWith('@') &&
            (k.startsWith('loanReq') ||
                k.startsWith('profileAnnual') ||
                k.startsWith('profileLoans') ||
                k.startsWith('profileMlk') ||
                k.startsWith('txn') ||
                k.startsWith('wfDetailLoan') ||
                k.startsWith('adminLogLoanRequest')),
      );
      expect(fresh.length, greaterThan(60));
      for (final k in fresh) {
        expect(tl.containsKey(k), isTrue, reason: 'missing Tagalog for $k');
      }
    });
  });
}
