import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/presentation/screens/admin/loan_history_screen.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';

import 'support/ignore_font_errors.dart';

/// The Loan History date filter: opens as a card with the four periods, Apply
/// returns the chosen one, Reset returns "All Time". Run on a 360 px phone, so
/// any overflow fails the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) => runIgnoringFontErrors(() => body(tester)));

  ReportPeriod? result;
  var closed = false;

  Future<void> open(WidgetTester tester, ReportPeriod initial) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    result = null;
    closed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showManagementModal<ReportPeriod>(
                  context: context,
                  builder: (_) => LoanPeriodFilterModal(initial: initial),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  ftest('shows the four periods under one labelled group', (tester) async {
    await open(tester, ReportPeriod.allTime);

    expect(find.text('Filter Loans'), findsOneWidget);
    expect(find.text('DATE ISSUED'), findsOneWidget);
    for (final label in ['All Time', 'This Month', 'This Quarter', 'This Year']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Reset All'), findsOneWidget);
    expect(find.text('Apply Filters'), findsOneWidget);
  });

  ftest('Apply returns the chosen period', (tester) async {
    await open(tester, ReportPeriod.allTime);

    await tester.tap(find.text('This Quarter'));
    await tester.pump();
    await tester.tap(find.text('Apply Filters'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(closed, isTrue);
    expect(result, ReportPeriod.thisQuarter);
  });

  ftest('Reset All returns All Time, whatever was chosen', (tester) async {
    await open(tester, ReportPeriod.thisYear);

    await tester.tap(find.text('This Month'));
    await tester.pump();
    await tester.tap(find.text('Reset All'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(result, ReportPeriod.allTime);
  });

  ftest('closing without applying changes nothing', (tester) async {
    await open(tester, ReportPeriod.thisMonth);

    await tester.tap(find.text('This Year'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(closed, isTrue);
    expect(result, isNull);
  });
}
