import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/loan_sorting.dart';
import 'package:sagana/data/models/expense_model.dart';
import 'package:sagana/data/models/loan_model.dart';
import 'package:sagana/data/models/loan_request_model.dart';
import 'package:sagana/presentation/widgets/loan_request_widgets.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

/// The source of one class, from its declaration to the next top-level class.
String classSource(String src, String name) {
  final start = src.indexOf('class $name ');
  expect(start, greaterThanOrEqualTo(0), reason: 'class $name');
  final next = src.indexOf('\nclass ', start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}

Widget localized(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

LoanRequestModel request({String status = 'pending'}) => LoanRequestModel.fromFarmerJson({
  'id': 'r1',
  'request_no': 'LQR-20261030-A001',
  'status': status,
  'total_value': 2400,
  'requested_at': '2026-10-30T01:00:00Z',
  'items': [
    {'item_name': 'Urea', 'unit': 'bag', 'quantity': 2, 'unit_price': 1200, 'line_total': 2400},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Expense category icons', () {
    test('each known category has its own icon, all from one rounded family', () {
      final icons = {
        for (final c in ['Fertilizer', 'Labor', 'Seeds', 'Tools', 'Irrigation', 'Transport'])
          c: categoryIcon(c),
      };
      expect(icons['Fertilizer'], Icons.compost_rounded);
      expect(icons['Labor'], Icons.engineering_rounded);
      expect(icons['Seeds'], Icons.spa_rounded);
      expect(icons['Tools'], Icons.handyman_rounded);
      expect(icons['Irrigation'], Icons.water_drop_rounded);
      expect(icons['Transport'], Icons.local_shipping_rounded);
      expect(icons.values.toSet().length, icons.length, reason: 'no two share an icon');
    });

    test('a category added later still gets a fitting icon', () {
      expect(categoryIcon('Pesticides'), Icons.bug_report_rounded);
      expect(categoryIcon('Animal Feeds'), Icons.pets_rounded);
      expect(categoryIcon('Fuel'), Icons.local_gas_station_rounded);
      expect(categoryIcon('Land rental'), Icons.landscape_rounded);
      expect(categoryIcon('Electricity bill'), Icons.bolt_rounded);
    });

    test('matching is by word, so look-alikes are not mistaken', () {
      expect(categoryIcon('Soil prep'), isNot(Icons.local_gas_station_rounded));
      expect(categoryIcon('Current expenses'), isNot(Icons.landscape_rounded));
      // Unknown and empty names get the neutral receipt icon.
      expect(categoryIcon('Other'), Icons.receipt_long_rounded);
      expect(categoryIcon('Miscellaneous'), Icons.receipt_long_rounded);
      expect(categoryIcon(''), Icons.receipt_long_rounded);
    });

    test('a category has one colour and one tint wherever it is shown', () {
      for (final c in ['Fertilizer', 'Labor', 'Pesticide', 'Other']) {
        expect(categoryColor(c), categoryColor(c));
        expect(categoryBgColor(c), isNot(categoryColor(c)));
      }
    });
  });

  group('Expenses screen', () {
    final src = read('lib/presentation/screens/farmer/my_expenses_screen.dart');

    test('has no photo or image functionality', () {
      // Code only: the comments may say "no photo".
      final code = src
          .split(RegExp(r'\r?\n'))
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(' ')
          .toLowerCase();
      for (final word in ['image_picker', 'imagepicker', 'image.network', 'photo', 'camera', 'attachment']) {
        expect(code, isNot(contains(word)),
            reason: 'expenses must stay simple text and numbers: found "$word"');
      }
      final model = read('lib/data/models/expense_model.dart');
      expect(model, isNot(contains('photo_url')));
      expect(model, isNot(contains('image_url')));
    });

    test('keeps adding an expense and reads, with the same repository and totals', () {
      expect(src, contains('_repo.fetchExpenses(_period)'));
      expect(src, contains('_repo.buildBreakdown(expenses)'));
      expect(src, contains('await widget.repo.addExpense('));
      expect(src, contains('_AddExpenseDialog('));
      // The period chips are the shared Manager > Loans chip, and the periods
      // are the same four as before.
      expect(src, contains('LoanChoiceChip('));
      expect(src, contains('ExpensePeriod.values'));
    });

    test('the detail is a modal with the category icon and a Close button', () {
      expect(src, contains('class _ExpenseDetailSheet'));
      expect(src, contains('showManagementModal<void>'));
      expect(src, contains('l10n.expnDetailCategory'));
      expect(src, contains('l10n.close'));
    });
  });

  group('Farmer Input Loans screen', () {
    final src = read('lib/presentation/screens/farmer/my_loans_screen.dart');

    test('follows the Manager layout, in order', () {
      final order = [
        '_OutstandingCard(',
        '_NextPaymentCard(',
        '_InputLoanInfoCard()',
        'l10n.loanMyHistoryTitle',
        'l10n.loanMyPaymentsTitle',
      ];
      var at = -1;
      for (final marker in order) {
        final i = src.indexOf(marker, at + 1);
        expect(i, greaterThan(at), reason: '$marker comes after the previous block');
        at = i;
      }
    });

    test('the landing page has no filter chips and no number beside the titles', () {
      expect(src, isNot(contains('LoanStatusChips')));
      expect(src, isNot(contains('LoanChoiceChip')));
      expect(src, isNot(contains('trailing:')));
    });

    test('both sections have a View All button that opens its own screen', () {
      expect(RegExp('viewAllLabel: l10n.loanMyViewAll').allMatches(src).length, 2);
      expect(src, contains('AppRoutes.myLoanHistory'));
      expect(src, contains('AppRoutes.myPaymentHistory'));
    });

    test('shows only the latest few, newest first, from the shared sort', () {
      expect(src, contains('static const _recentLoans = 3;'));
      expect(src, contains('static const _recentPayments = 5;'));
      expect(src, contains('loansNewestFirst(_loans).take(_recentLoans)'));
      expect(src, contains('paymentsNewestFirst(_loans)'));
      expect(src, contains('allPayments.take(_recentPayments)'));
    });

    test('Request a Loan is a floating + button, not a rectangular button', () {
      expect(src, contains('floatingActionButton: FloatingActionButton('));
      expect(src, contains('AppRoutes.requestLoan'));
      expect(src, isNot(contains('_RequestLoanCta')));
    });

    test('Loan Requests moved out of this screen', () {
      expect(src, isNot(contains('LoanRequestCard')));
      expect(src, isNot(contains('fetchMyLoanRequests')));
      expect(src, isNot(contains('loanReqSectionTitle')));
    });

    test('the balance comes from the same loans as the history and payments', () {
      expect(src, contains('_loans.where((l) => !l.isPaid)'));
      expect(src, contains('l.remainingBalance'));
      expect(src, isNot(contains('fetchTotalOutstanding')));
    });

    test('the Outstanding card is one colour throughout', () {
      final card = classSource(src, '_OutstandingCard');
      // The counts take the card's own accent: no separate green pill.
      expect(src, isNot(contains('_CountPill')));
      expect(card, contains('accent: accent'));
      expect(card, isNot(contains('successGreen.withValues')));
      // The width is used: repaid share, progress bar and three counts.
      expect(card, contains('LinearProgressIndicator('));
      expect(RegExp(r'_CountTile\(').allMatches(card).length, 3);
    });
  });

  group('Loan History and Payment History screens', () {
    final history = read('lib/presentation/screens/farmer/my_loan_history_screen.dart');
    final payments = read('lib/presentation/screens/farmer/my_payment_history_screen.dart');
    final widgets = read('lib/presentation/widgets/farmer_loan_widgets.dart');

    test('Loan History has every loan, the status chips with counts, newest first', () {
      expect(history, contains('loansNewestFirst(loans)'));
      expect(history, contains('LoanStatusChips('));
      expect(history, contains('counts: {'));
      expect(history, contains('FarmerLoanCard(loan: visible[i])')); // the full card
      for (final k in [
        'l10n.loanHistoryFilterAll',
        'l10n.loanDashActiveLoans',
        'l10n.loanDashOverdueLoans',
        'l10n.loanHistoryFilterPaid',
      ]) {
        expect(widgets, contains(k), reason: k);
      }
    });

    test('Payment History has every payment, newest first, grouped by month', () {
      expect(payments, contains('paymentsNewestFirst(loans)'));
      expect(payments, contains("DateFormat('MMMM yyyy')"));
      expect(payments, contains('FarmerPaymentRow('));
      expect(payments, contains('l10n.loanMyTotalPaid'));
    });

    test('the landing page and the View All screens show a record the same way', () {
      for (final f in [
        'lib/presentation/screens/farmer/my_loans_screen.dart',
        'lib/presentation/screens/farmer/my_loan_history_screen.dart',
        'lib/presentation/screens/farmer/my_payment_history_screen.dart',
      ]) {
        expect(read(f), contains('farmer_loan_widgets.dart'), reason: f);
      }
    });
  });

  group('Loan History: search by Loan ID', () {
    LoanModel loan(String id, String ref, String status) => LoanModel(
      id: id,
      farmerId: 'f1',
      referenceNo: ref,
      issuedDate: DateTime(2026, 10, 20),
      totalValue: 1000,
      amountPaid: 0,
      status: status,
      items: const [],
      payments: const [],
    );

    final loans = [
      loan('1', 'LRN-20261030-A002', 'active'),
      loan('2', 'LRN-20261030-A001', 'overdue'),
      loan('3', 'LRN-20260105-A001', 'paid'),
      loan('4', 'LN-2025-007', 'paid'),
    ];

    test('an empty search shows every loan, in the same order', () {
      expect(loansMatchingId(loans, '').map((l) => l.id), ['1', '2', '3', '4']);
      expect(loansMatchingId(loans, '   ').map((l) => l.id), ['1', '2', '3', '4']);
    });

    test('the full ID finds exactly that loan', () {
      expect(loansMatchingId(loans, 'LRN-20261030-A002').map((l) => l.id), ['1']);
    });

    test('case, spaces and dashes do not matter', () {
      expect(loansMatchingId(loans, 'lrn20261030a001').map((l) => l.id), ['2']);
      expect(loansMatchingId(loans, 'lrn 20261030 a001').map((l) => l.id), ['2']);
      expect(loansMatchingId(loans, '  LRN-20261030-a001  ').map((l) => l.id), ['2']);
    });

    test('any part of the ID matches', () {
      expect(loansMatchingId(loans, '20261030').map((l) => l.id), ['1', '2']);
      expect(loansMatchingId(loans, 'A001').map((l) => l.id), ['2', '3']);
      expect(loansMatchingId(loans, '2025').map((l) => l.id), ['4']);
    });

    test('an ID that does not exist finds nothing', () {
      expect(loansMatchingId(loans, 'LRN-29990101-Z999'), isEmpty);
    });

    test('the search and the status chips work together', () {
      // Search first, then the chip narrows what the search found.
      final found = loansMatchingId(loans, 'A001'); // 2 (overdue), 3 (paid)
      expect(found.where((l) => l.status == 'overdue').map((l) => l.id), ['2']);
      expect(found.where((l) => l.status == 'paid').map((l) => l.id), ['3']);
      expect(found.where((l) => l.status == 'active'), isEmpty);
    });

    test('the screen puts the search first, then the chips, then the records', () {
      final src = read('lib/presentation/screens/farmer/my_loan_history_screen.dart');
      final search = src.indexOf('controller: _searchCtrl');
      final chips = src.indexOf('LoanStatusChips(');
      final records = src.indexOf('FarmerLoanCard(loan: visible[i])');
      expect(search, greaterThan(0));
      expect(chips, greaterThan(search));
      expect(records, greaterThan(chips));
      expect(src, contains('l10n.loanMySearchHint'));
    });

    test('the chip counts and the list both come from the searched loans', () {
      final src = read('lib/presentation/screens/farmer/my_loan_history_screen.dart');
      expect(src, contains('List<LoanModel> get _searched => loansMatchingId(_loans, _search);'));
      expect(src, contains('_searched.where((l) => l.status == status).length'));
      expect(src, contains('_searched.where((l) => l.status == _statusFilter).toList()'));
      // The search can be cleared from the field.
      expect(src, contains("_searchCtrl.clear();"));
    });
  });

  group('Loan and payment order', () {
    LoanModel loan(String id, String ref, DateTime issued, {List<LoanPaymentModel> payments = const []}) =>
        LoanModel(
          id: id,
          farmerId: 'f1',
          referenceNo: ref,
          issuedDate: issued,
          totalValue: 1000,
          amountPaid: 0,
          status: 'active',
          items: const [],
          payments: payments,
        );

    LoanPaymentModel pay(String id, String loanId, DateTime day, double balance) => LoanPaymentModel(
      id: id,
      loanId: loanId,
      paymentDate: day,
      amountPaid: 100,
      runningBalance: balance,
    );

    test('loans are newest first by the date issued', () {
      final sorted = loansNewestFirst([
        loan('a', 'LRN-20260105-A001', DateTime(2026, 1, 5)),
        loan('c', 'LRN-20261020-A003', DateTime(2026, 10, 20)),
        loan('b', 'LRN-20260601-A002', DateTime(2026, 6, 1)),
      ]);
      expect(sorted.map((l) => l.id), ['c', 'b', 'a']);
    });

    test('two loans issued the same day: the later reference comes first', () {
      final sorted = loansNewestFirst([
        loan('x', 'LRN-20261020-A001', DateTime(2026, 10, 20)),
        loan('y', 'LRN-20261020-A002', DateTime(2026, 10, 20)),
      ]);
      expect(sorted.map((l) => l.id), ['y', 'x']);
    });

    test('older LN-YYYY-### references sort among the new ones by date', () {
      final sorted = loansNewestFirst([
        loan('old', 'LN-2025-007', DateTime(2025, 12, 1)),
        loan('new', 'LRN-20260301-A001', DateTime(2026, 3, 1)),
      ]);
      expect(sorted.map((l) => l.id), ['new', 'old']);
    });

    test('payments from every loan are merged and newest first', () {
      final l1 = loan('l1', 'LRN-1', DateTime(2026, 1, 1), payments: [
        pay('p1', 'l1', DateTime(2026, 2, 5), 900),
        pay('p2', 'l1', DateTime(2026, 4, 5), 800),
      ]);
      final l2 = loan('l2', 'LRN-2', DateTime(2026, 3, 1), payments: [
        pay('p3', 'l2', DateTime(2026, 3, 20), 900),
      ]);
      final sorted = paymentsNewestFirst([l1, l2]);
      expect(sorted.map((e) => e.payment.id), ['p2', 'p3', 'p1']);
      expect(sorted.first.loan.id, 'l1');
    });

    test('two payments on the same day: the one that left less owing is the later', () {
      final l = loan('l', 'LRN-1', DateTime(2026, 1, 1), payments: [
        pay('first', 'l', DateTime(2026, 5, 2), 700),
        pay('second', 'l', DateTime(2026, 5, 2), 400),
      ]);
      expect(paymentsNewestFirst([l]).map((e) => e.payment.id), ['second', 'first']);
    });

    test('the latest few are always a prefix of the full list', () {
      final l = loan('l', 'LRN-1', DateTime(2026, 1, 1), payments: [
        for (var i = 1; i <= 9; i++) pay('p$i', 'l', DateTime(2026, i, 10), 1000 - i * 100.0),
      ]);
      final all = paymentsNewestFirst([l]).map((e) => e.payment.id).toList();
      expect(all.take(5), ['p9', 'p8', 'p7', 'p6', 'p5']);
      expect(all.length, 9);
    });

    test('sorting never loses or duplicates a record', () {
      final l = loan('l', 'LRN-1', DateTime(2026, 1, 1), payments: [
        pay('a', 'l', DateTime(2026, 3, 1), 900),
        pay('b', 'l', DateTime(2026, 3, 1), 800),
        pay('c', 'l', DateTime(2026, 2, 1), 950),
      ]);
      final ids = paymentsNewestFirst([l]).map((e) => e.payment.id).toList();
      expect(ids.toSet(), {'a', 'b', 'c'});
      expect(ids.length, 3);
    });
  });

  group('Request a Loan screen', () {
    final src = read('lib/presentation/screens/farmer/request_loan_screen.dart');

    test('has no subtitle above the search bar and keeps the chips', () {
      expect(src, isNot(contains('_IntroBanner')));
      expect(src, isNot(contains('loanReqIntro')));
      final search = src.indexOf('TextField(\n                          controller: _searchCtrl');
      final chips = src.indexOf('_CategoryChips(');
      expect(search, greaterThan(0));
      expect(chips, greaterThan(search), reason: 'chips follow the search bar');
    });

    test('has a requests history icon that opens My Loan Requests', () {
      expect(src, contains('trailing: ['));
      expect(src, contains('Icons.assignment_outlined'));
      expect(src, contains('AppRoutes.myLoanRequests'));
    });

    test('keeps the stock checks and the submission', () {
      expect(src, contains('item.inStock ? () => _editQuantity(item) : null'));
      expect(src, contains('DecimalInputFormatter(max: item.quantityOnHand)'));
      expect(src, contains('submitLoanRequest('));
      // After sending it stays: a clean selection and the requests list.
      expect(src, contains('setState(_quantities.clear)'));
    });
  });

  group('Manager / Officer Loan Requests screen', () {
    final src = read('lib/presentation/screens/admin/loan_requests_screen.dart');

    test('has no subtitle, a search bar, then All / Pending / Approved / Disapproved with counts', () {
      expect(src, isNot(contains('loanReqAdminSubtitle')));
      expect(src, contains('l10n.loanReqAdminSearchHint'));
      for (final k in [
        'loanReqFilterAllCount',
        'loanReqFilterPendingCount',
        'loanReqFilterApprovedCount',
        'loanReqFilterDisapprovedCount',
      ]) {
        expect(src, contains('l10n.$k'), reason: k);
      }
      expect(src.indexOf('TextField('), lessThan(src.indexOf('l10n.loanReqFilterAllCount')));
      expect(src, isNot(contains('l10n.loanReqFilterCancelled')));
    });

    test('counts and the list come from the same searched requests', () {
      expect(src, contains('_searched.where((r) => r.status == status).length'));
      expect(src, contains(': _searched.where((r) => r.status == _statusFilter).toList()'));
      // A request the Farmer withdrew is not listed (nothing to decide).
      expect(src, contains('if (r.isCancelled) return false;'));
    });

    test('the search covers the farmer, request and loan numbers, items and the deciding staff', () {
      for (final f in ['r.farmerName', 'r.requestNo', 'r.loanReference', 'r.reviewerName', 'i.itemName']) {
        expect(src, contains(f), reason: f);
      }
    });

    test('shows who approved or disapproved', () {
      expect(src, contains('l10n.loanReqApprovedBy'));
      expect(src, contains('l10n.loanReqDisapprovedBy'));
      expect(src, contains('r.reviewerName'));
    });
  });

  group('Loan request widgets', () {
    testWidgets('a pending request shows its number, items and status', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(LoanRequestCard(request: request(), onTap: () {})));
        expect(find.text('LQR-20261030-A001'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.textContaining('Urea'), findsWidgets);
        expect(find.text('₱2,400.00'), findsOneWidget);
      });
    });

    testWidgets('statuses read the same on the card as in the filters', (tester) async {
      await runIgnoringFontErrors(() async {
        for (final entry in {
          'approved': 'Approved',
          'disapproved': 'Disapproved',
          'cancelled': 'Cancelled',
        }.entries) {
          await tester.pumpWidget(
            localized(LoanRequestCard(request: request(status: entry.key), onTap: () {})),
          );
          expect(find.text(entry.value), findsOneWidget, reason: entry.key);
        }
      });
    });
  });

  group('Integrity SQL', () {
    final audit = read('supabase_schema/supabase_schema_loan_request_integrity_audit.sql');
    final hardening = read('supabase_schema/supabase_schema_loan_request_integrity_hardening.sql');

    test('the audit is read-only and checks every inventory and balance rule', () {
      final code = audit.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      for (final write in ['INSERT ', 'UPDATE ', 'DELETE ', 'ALTER ', 'DROP ', 'CREATE ']) {
        expect(code.toUpperCase(), isNot(contains(write)), reason: write);
      }
      for (final item in [
        'approved request with no loan',
        'request that is NOT approved but has a loan',
        'same item deducted twice for one loan',
        'deducted quantity differs from the approved request',
        'negative stock on hand',
        'loan total differs from the sum of its items',
        'amount paid differs from the sum of its payments',
      ]) {
        expect(audit, contains(item), reason: item);
      }
    });

    test('the guards are created only when the data already satisfies them', () {
      expect(hardening, contains('CREATE UNIQUE INDEX uq_inventory_loan_issue_once'));
      expect(hardening, contains('Guard 1 SKIPPED'));
      expect(hardening, contains('cooperative_inventory_quantity_non_negative'));
      expect(hardening, contains('Guard 2 SKIPPED'));
      expect(hardening, isNot(contains('DELETE FROM')));
    });
  });
}
