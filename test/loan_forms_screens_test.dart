import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_loan_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/issue_new_loan_screen.dart';
import 'package:sagana/presentation/screens/admin/loan_history_screen.dart';
import 'package:sagana/presentation/screens/admin/record_payment_screen.dart';
import 'package:sagana/presentation/widgets/shared_widgets.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// Record Payment and Issue New Loan after the redesign: what they show, the
/// inline validation, and the payment notices. The network is unreachable in
/// tests, so the loan comes from the same on-device cache the screen falls back
/// to when offline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final loan = AdminLoanSummary(
    id: 'loan-1',
    farmerId: 'farmer-1',
    farmerName: 'Juan Dela Cruz',
    referenceNo: 'LRN-20261024-A001',
    issuedDate: DateTime(2026, 10, 24),
    totalValue: 12000,
    amountPaid: 2000,
    status: 'active',
    monthlyPayment: 1000,
    itemNames: const ['Urea'],
    nextPaymentDate: DateTime(2026, 11, 7),
  );

  const roster = [
    FarmerPickerResult(id: 'farmer-3', fullName: 'Pedro Penduko'),
    FarmerPickerResult(id: 'farmer-1', fullName: 'Juan Dela Cruz'),
    FarmerPickerResult(id: 'farmer-2', fullName: 'Maria Clara'),
  ];

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();

    final dir = Directory.systemTemp.createTempSync('sagana_loan_forms');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );

    await HiveService.init();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
    await HiveService.cacheActiveLoans([loan.toCacheMap()]);
    await HiveService.cacheFarmerRoster([
      for (final f in roster) f.toMap(),
    ]);
  });

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) => runIgnoringFontErrors(() => body(tester)));

  Future<void> show(WidgetTester tester, Widget screen, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder amountField() => find.byType(TextFormField).first;

  group('Record Payment - choosing a farmer', () {
    ftest('lists who owes first, with their loans and balance', (tester) async {
      await show(tester, const RecordPaymentScreen());

      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('1 active loan'), findsOneWidget);
      expect(find.text('₱10,000'), findsOneWidget);
      // Farmers with nothing to pay are folded away, not listed as dead rows.
      expect(find.text('Maria Clara'), findsNothing);
      expect(find.text('Pedro Penduko'), findsNothing);
      expect(find.text('No active loans (2)'), findsOneWidget);
    });

    ftest('the folded farmers can be shown and hidden', (tester) async {
      await show(tester, const RecordPaymentScreen());

      await tester.tap(find.text('No active loans (2)'));
      await tester.pump();
      expect(find.text('Maria Clara'), findsOneWidget);
      expect(find.text('Pedro Penduko'), findsOneWidget);
      expect(find.text('No active loans'), findsNWidgets(2));

      await tester.tap(find.text('No active loans (2)'));
      await tester.pump();
      expect(find.text('Maria Clara'), findsNothing);
    });

    ftest('searching a farmer with no loan still finds them', (tester) async {
      await show(tester, const RecordPaymentScreen());

      await tester.enterText(find.byType(TextField), 'maria');
      await tester.pump();

      expect(find.text('Maria Clara'), findsOneWidget);
      expect(find.text('No active loans'), findsOneWidget);
      expect(find.text('Juan Dela Cruz'), findsNothing);
    });

    ftest('choosing a farmer who owes opens their loan', (tester) async {
      await show(tester, const RecordPaymentScreen());

      await tester.tap(find.text('Juan Dela Cruz'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('LRN-20261024-A001'), findsOneWidget);
      expect(find.text('Payment Details'), findsOneWidget);
    });

    ftest('fits a 360 px phone without overflow', (tester) async {
      await show(
        tester,
        const RecordPaymentScreen(),
        size: const Size(360, 640),
      );
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
    });
  });

  group('Record Payment', () {
    ftest('shows the loan, its reference and quick amounts', (tester) async {
      await show(tester, const RecordPaymentScreen(loanId: 'loan-1'));

      expect(find.text('LRN-20261024-A001'), findsOneWidget);
      expect(find.text('₱10,000.00'), findsOneWidget); // balance
      expect(find.text('17% repaid'), findsOneWidget);
      expect(find.text('Loan Value'), findsOneWidget);
      expect(find.text('Paid So Far'), findsOneWidget);
      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('Amount Received *'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Full Balance'), findsOneWidget);
      // The default amount is this month's instalment.
      expect(
        tester.widget<TextFormField>(amountField()).controller!.text,
        '1000',
      );
      expect(find.text('Record ₱1,000.00 Payment'), findsOneWidget);
    });

    ftest('Full balance fills the amount and says the loan is settled', (
      tester,
    ) async {
      await show(tester, const RecordPaymentScreen(loanId: 'loan-1'));

      await tester.tap(find.text('Full Balance'));
      await tester.pump();

      expect(
        tester.widget<TextFormField>(amountField()).controller!.text,
        '10000',
      );
      expect(find.text('This payment settles the loan in full.'), findsOneWidget);
    });

    ftest('an amount above the balance shows the overpayment notice', (
      tester,
    ) async {
      await show(tester, const RecordPaymentScreen(loanId: 'loan-1'));

      await tester.enterText(amountField(), '15000');
      await tester.pump();

      expect(find.text('This exceeds the remaining balance.'), findsOneWidget);
      expect(find.text('This payment settles the loan in full.'), findsNothing);
    });

    ftest('an empty amount shows an inline error, not a snackbar', (
      tester,
    ) async {
      await show(tester, const RecordPaymentScreen(loanId: 'loan-1'));

      await tester.enterText(amountField(), '');
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    ftest('fits a 360 px phone without overflow', (tester) async {
      await show(
        tester,
        const RecordPaymentScreen(loanId: 'loan-1'),
        size: const Size(360, 640),
      );
      expect(find.text('LRN-20261024-A001'), findsOneWidget);
    });
  });

  group('Issue New Loan', () {
    ftest('the farmer picker lists farmers A to Z and marks the chosen one', (
      tester,
    ) async {
      await show(tester, const IssueNewLoanScreen());

      await tester.tap(find.text('Tap to select a farmer'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Select Farmer'), findsOneWidget);
      expect(find.text('3 farmers'), findsOneWidget);
      final names = ['Juan Dela Cruz', 'Maria Clara', 'Pedro Penduko'];
      final tops = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
      expect(tops[0] < tops[1] && tops[1] < tops[2], isTrue); // A to Z
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.tap(find.text('Maria Clara'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Select Farmer'), findsNothing);
      expect(find.text('Maria Clara'), findsOneWidget); // now in the Borrower field

      // Opened again, the chosen farmer is marked.
      await tester.tap(find.text('Maria Clara'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    ftest('the farmer picker fits a 360 px phone without overflow', (
      tester,
    ) async {
      await show(
        tester,
        const IssueNewLoanScreen(),
        size: const Size(360, 640),
      );
      await tester.tap(find.text('Tap to select a farmer'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Select Farmer'), findsOneWidget);
    });

    ftest('is grouped into Borrower, Input Items, Repayment Terms and Notes', (
      tester,
    ) async {
      await show(tester, const IssueNewLoanScreen());

      expect(find.text('Borrower'), findsOneWidget);
      expect(find.text('Input Items'), findsOneWidget);
      expect(find.text('Repayment Terms'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Notes (optional)'), findsNothing);
      expect(find.text('Total Loan Value'), findsOneWidget);
      expect(find.text('Monthly Payment *'), findsOneWidget);
      expect(find.text('Issue Loan'), findsOneWidget);
      // Nothing is flagged before the Manager tries to issue.
      expect(find.text('Please select a farmer first.'), findsNothing);
      expect(find.text('Please add at least one input item.'), findsNothing);
    });

    ftest('issuing an empty form flags each missing part inline', (tester) async {
      await show(tester, const IssueNewLoanScreen());

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(find.text('Please select a farmer first.'), findsOneWidget);
      expect(find.text('Please add at least one input item.'), findsOneWidget);
      expect(find.text('Enter the monthly payment.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    ftest('the monthly payment is not pre-filled or tied to a 12-month term', (
      tester,
    ) async {
      await show(tester, const IssueNewLoanScreen());

      final monthly = find.byType(TextFormField).first;
      expect(tester.widget<TextFormField>(monthly).controller!.text, '');
      expect(
        find.text('What the farmer pays each month at the BOD meeting.'),
        findsOneWidget,
      );
      expect(find.textContaining('12'), findsNothing);
    });

    ftest('a zero monthly payment is refused inline', (tester) async {
      await show(tester, const IssueNewLoanScreen());

      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.pump();

      expect(
        find.text('Monthly payment must be greater than zero.'),
        findsOneWidget,
      );
    });

    ftest('the monthly payment takes at most 2 decimals', (tester) async {
      await show(tester, const IssueNewLoanScreen());

      await tester.enterText(find.byType(TextFormField).first, '150.756');
      await tester.pump();

      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text,
        '150.75',
      );
    });

    ftest('fits a 360 px phone without overflow', (tester) async {
      await show(
        tester,
        const IssueNewLoanScreen(),
        size: const Size(360, 640),
      );
      expect(find.text('Borrower'), findsOneWidget);
    });
  });
  group('Loan History', () {
    bool isSelected(WidgetTester tester, String label) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
        .selected;

    // The test font is much wider than the real one, so these use a wide screen
    // to have all four chips on show; the narrow-screen test below covers scrolling.
    const wide = Size(1000, 900);

    ftest('shows the four status chips and a Filter button', (tester) async {
      await show(tester, const LoanHistoryScreen(), size: wide);

      for (final label in ['All', 'Active Loans', 'Overdue Loans', 'Paid']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      // Four chips: the Filter button is not one of them.
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      expect(isSelected(tester, 'All'), isTrue);

      // Row 1: the search box with the Filter button beside it. Row 2: the chips.
      final search = tester.getRect(find.byType(TextField));
      final filter = tester.getRect(find.byIcon(Icons.tune_rounded));
      expect(filter.left, greaterThan(search.right));
      expect(filter.center.dy, closeTo(search.center.dy, 2));
      for (final label in ['All', 'Active Loans', 'Overdue Loans', 'Paid']) {
        final chip = tester.getRect(find.widgetWithText(ChoiceChip, label));
        expect(chip.top, greaterThan(search.bottom), reason: label);
      }
    });

    ftest('choosing a status selects only that chip', (tester) async {
      await show(tester, const LoanHistoryScreen(), size: wide);

      await tester.tap(find.text('Overdue Loans'));
      await tester.pump();

      expect(isSelected(tester, 'Overdue Loans'), isTrue);
      expect(isSelected(tester, 'All'), isFalse);
      expect(isSelected(tester, 'Paid'), isFalse);
    });

    ftest('the Filter button applies a period, shown as a tag that clears it', (
      tester,
    ) async {
      await show(tester, const LoanHistoryScreen());
      expect(find.textContaining('Issued:'), findsNothing);

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Filter Loans'), findsOneWidget);
      await tester.tap(find.text('This Month'));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Issued: This Month'), findsOneWidget);

      await tester.tap(find.text('Issued: This Month'));
      await tester.pump();
      expect(find.textContaining('Issued:'), findsNothing);
    });

    ftest('on a very narrow phone the chips stay in one row and scroll sideways', (
      tester,
    ) async {
      await show(
        tester,
        const LoanHistoryScreen(),
        size: const Size(300, 700),
      );

      Rect rectOf(String label) =>
          tester.getRect(find.widgetWithText(ChoiceChip, label));

      // One row, side by side, never on top of each other.
      final allBefore = rectOf('All');
      final activeBefore = rectOf('Active Loans');
      expect(activeBefore.top, closeTo(allBefore.top, 1));
      expect(activeBefore.left, greaterThanOrEqualTo(allBefore.right));

      // The row is wider than the screen: a sideways drag moves it, and the
      // last chip ends up fully on screen.
      final chipRow = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      );
      expect(chipRow, findsOneWidget);
      await tester.drag(chipRow, const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(rectOf('Paid').right, lessThanOrEqualTo(300));
      expect(find.widgetWithText(ChoiceChip, 'All'), findsNothing); // scrolled out

      // Each chip is still its own selectable button.
      await tester.tap(find.text('Paid'));
      await tester.pump();
      expect(isSelected(tester, 'Paid'), isTrue);
    });

    ftest('fits a 360 px phone without overflow', (tester) async {
      await show(
        tester,
        const LoanHistoryScreen(),
        size: const Size(360, 640),
      );
      expect(find.text('Loan History'), findsOneWidget);
    });
  });
}