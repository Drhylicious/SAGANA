import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/presentation/widgets/report_ui_widgets.dart';

import 'support/ignore_font_errors.dart';

String _read(String path) => File(path).readAsStringSync();

Widget _host(Widget child, {double width = 360}) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('Reports screens (source checks)', () {
    test('Cooperative Stock shows the search bar before the filter chips', () {
      final src = _read('lib/presentation/screens/admin/cooperative_stock_report_screen.dart');
      final search = src.indexOf('hintText: l10n.reportsSearchItems');
      final chips = src.indexOf('label: l10n.reportsAll');
      expect(search, greaterThan(0));
      expect(chips, greaterThan(search));
    });

    test('Loan Report has period filters only, no status filter chips', () {
      final src = _read('lib/presentation/screens/admin/loan_report_screen.dart');
      expect(src, contains('ReportPeriodFilter'));
      expect(src, isNot(contains('_statusFilter')));
      expect(src, isNot(contains('_buildStatusChips')));
      expect(src, isNot(contains('loanHistoryFilterAll')));
      // Statuses are still shown on every loan.
      expect(src, contains('rptStatusOverdue'));
      expect(src, contains('rptStatusPaid'));
    });

    test('Harvest Report no longer shows the always-true sync statistics', () {
      final src = _read('lib/presentation/screens/admin/harvest_report_screen.dart');
      expect(src, isNot(contains('reportsUnsyncedEntries')));
      expect(src, isNot(contains('reportsPendingSync')));
      expect(src, isNot(contains('reportsReserved')));
    });

    test('Export Center reports success and failure through the shared toast',
        () {
      final src = _read('lib/presentation/screens/admin/export_center_screen.dart');
      expect(src, contains('PostActionFeedback.success'));
      expect(src, contains('PostActionFeedback.error'));
      expect(src, isNot(contains('ScaffoldMessenger')));
    });

    test('Analytics has no KPI cards or snapshot, and no report has a dates '
        'line under the period chips', () {
      final analytics = _read(
        'lib/presentation/screens/admin/analytics_dashboard_screen.dart',
      );
      expect(analytics, isNot(contains('ReportIconStatCard')));
      expect(analytics, isNot(contains('rptAnalyticsSnapshot')));
      final export = _read(
        'lib/presentation/screens/admin/export_center_screen.dart',
      );
      expect(export, isNot(contains('showRange')));
      expect(
        _read('lib/presentation/widgets/report_ui_widgets.dart'),
        isNot(contains('Icons.date_range_rounded')),
      );
    });

    test('the removed explanatory lines are gone from the report screens', () {
      for (final path in [
        'lib/presentation/screens/admin/harvest_report_screen.dart',
        'lib/presentation/screens/admin/loan_report_screen.dart',
      ]) {
        final src = _read(path);
        expect(src, isNot(contains('ReportInfoNote')), reason: path);
        expect(src, isNot(contains('rptSoldHint')), reason: path);
        expect(src, isNot(contains('rptCommittedHint')), reason: path);
        expect(src, isNot(contains('rptLoanSummaryHint')), reason: path);
      }
    });

    test('Member Patronage and Balik-Tangkilik do not use the new report '
        'widgets', () {
      for (final path in [
        'lib/presentation/screens/admin/member_contribution_report_screen.dart',
        'lib/presentation/screens/admin/balik_tangkilik_management_screen.dart',
      ]) {
        expect(_read(path), isNot(contains('report_ui_widgets')), reason: path);
      }
    });
  });

  group('Shared report widgets', () {
    testWidgets('period filter lists the four periods and names the dates', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        ReportPeriod? picked;
        await tester.pumpWidget(
          _host(
            ReportPeriodFilter(
              period: ReportPeriod.allTime,
              onSelected: (p) => picked = p,
            ),
            // Wide enough that the horizontally scrolling row builds all four
            // chips at once (a phone-width row builds the off-screen ones lazily).
            width: 700,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('All Time'), findsOneWidget);
        expect(find.text('This Month'), findsOneWidget);
        expect(find.text('This Quarter'), findsOneWidget);
        expect(find.text('This Year'), findsOneWidget);
        // The selected chip already says which period is shown.
        expect(find.text('All dates'), findsNothing);

        await tester.tap(find.text('This Month'));
        expect(picked, ReportPeriod.thisMonth);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('search field clears itself and tells the screen', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final controller = TextEditingController();
        var latest = 'unset';
        await tester.pumpWidget(
          _host(
            ReportSearchField(
              controller: controller,
              hint: 'Search',
              onChanged: (v) => latest = v,
            ),
          ),
        );
        expect(find.byIcon(Icons.close_rounded), findsNothing);

        await tester.enterText(find.byType(TextField), 'palay');
        await tester.pump();
        expect(latest, 'palay');
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();
        expect(controller.text, isEmpty);
        expect(latest, '');
      });
    });

    testWidgets('filter chips report the tapped value and stay in bounds', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        String? selected;
        await tester.pumpWidget(
          _host(
            ReportFilterChips<String?>(
              options: const [
                ReportFilterOption<String?>(null, 'All Channels'),
                ReportFilterOption<String?>('marketplace', 'Marketplace'),
                ReportFilterOption<String?>(
                  'da_amad_market_linking',
                  'DA-AMAD Market Linking',
                ),
              ],
              selected: selected,
              onSelected: (v) => selected = v,
            ),
            width: 320,
          ),
        );
        await tester.tap(find.text('Marketplace'));
        expect(selected, 'marketplace');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a trend card with too little data says so instead of drawing',
        (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          _host(
            ReportTrendCard(
              title: 'Revenue Trend',
              values: const [10],
              valueFormatter: (v) => '$v',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Not enough data for a trend yet.'), findsOneWidget);
        expect(find.text('Last 6 months. Not affected by the period filter.'),
            findsOneWidget);
      });
    });
  });
}
