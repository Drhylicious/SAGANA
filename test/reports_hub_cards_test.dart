import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/dashboard_cards.dart';

import 'support/ignore_font_errors.dart';

String _read(String path) => File(path).readAsStringSync();

/// The Reports hub's two card sections, built from the real translated strings,
/// in the same shared grid the Dashboard and Marketplace tabs use.
List<DashboardModuleItem> _detailed(AppLocalizations l) => [
  DashboardModuleItem(
    icon: Icons.point_of_sale_rounded,
    title: l.reportsSalesReport,
    subtitle: l.rptHubSalesSub,
    badge: '₱1.2M',
    onTap: () {},
  ),
  DashboardModuleItem(
    icon: Icons.agriculture_rounded,
    title: l.reportsHarvestManagement,
    subtitle: l.rptHubHarvestSub,
    badge: '12,345 kg',
    onTap: () {},
  ),
  DashboardModuleItem(
    icon: Icons.inventory_2_rounded,
    title: l.reportsCoopStockReport,
    subtitle: l.rptHubStockSub,
    badge: l.rptHubBadgeLowStock(11),
    onTap: () {},
  ),
  DashboardModuleItem(
    icon: Icons.request_page_rounded,
    title: l.reportsLoanReport,
    subtitle: l.rptHubLoanSub,
    badge: l.rptHubBadgeOwed('₱99,999'),
    onTap: () {},
  ),
  DashboardModuleItem(
    icon: Icons.receipt_long_rounded,
    title: l.reportsExpenseReport,
    subtitle: l.rptHubExpenseSub,
    badge: '₱8,400',
    onTap: () {},
  ),
  DashboardModuleItem(
    icon: Icons.groups_rounded,
    title: l.reportsMemberContributionReport,
    subtitle: l.rptHubPatronageSub,
    badge: l.rptHubBadgeActive('100'),
    onTap: () {},
  ),
];

List<DashboardModuleItem> _tools(AppLocalizations l) => [
  DashboardModuleItem(
    icon: Icons.insights_rounded,
    title: l.reportsAnalyticsDashboard,
    subtitle: l.rptHubAnalyticsSub,
    badge: l.rptHubBadgeNoActivity(12),
    onTap: () {},
  ),
  DashboardModuleItem(
    icon: Icons.file_download_rounded,
    title: l.reportsExportCenter,
    subtitle: l.rptHubExportSub,
    badge: l.rptHubBadgeExports(12),
    onTap: () {},
  ),
];

Widget _host(Locale locale, double width, double textScale, Widget Function(AppLocalizations) items) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          size: Size(width, 900),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: items(AppLocalizations.of(context)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Reports hub cards', () {
    for (final locale in [const Locale('en'), const Locale('tl')]) {
      for (final scale in [1.0, 1.4]) {
        testWidgets(
          'both sections fit a 320 px phone at ${scale}x text (${locale.languageCode})',
          (tester) async {
            await runIgnoringFontErrors(() async {
              await tester.pumpWidget(
                _host(
                  locale,
                  320,
                  scale,
                  (l) => Column(
                    children: [
                      DashboardModuleGrid(items: _detailed(l)),
                      const SizedBox(height: 20),
                      DashboardModuleGrid(items: _tools(l)),
                    ],
                  ),
                ),
              );
              await tester.pumpAndSettle();
              // Any overflowing text or box shows up as a framework exception.
              expect(tester.takeException(), isNull);
              expect(find.byType(DashboardModuleGrid), findsNWidgets(2));
            });
          },
        );
      }
    }

    testWidgets('a tap on a card runs that card\'s action', (tester) async {
      await runIgnoringFontErrors(() async {
        var tapped = '';
        await tester.pumpWidget(
          _host(
            const Locale('en'),
            360,
            1.0,
            (l) => DashboardModuleGrid(
              items: [
                DashboardModuleItem(
                  icon: Icons.insights_rounded,
                  title: l.reportsAnalyticsDashboard,
                  subtitle: l.rptHubAnalyticsSub,
                  badge: l.rptHubBadgeNoActivity(3),
                  onTap: () => tapped = 'analytics',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 no activity'), findsOneWidget);
        await tester.tap(find.text('Analytics Dashboard'));
        expect(tapped, 'analytics');
      });
    });

    testWidgets('badges read naturally in both languages', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          _host(const Locale('en'), 360, 1.0, (l) {
            expect(l.rptHubBadgeExports(0), 'No exports');
            expect(l.rptHubBadgeExports(1), '1 export');
            expect(l.rptHubBadgeExports(4), '4 exports');
            expect(l.rptHubBadgeLowStock(11), '11 low stock');
            expect(l.rptHubBadgeOwed('₱9,084'), '₱9,084 owed');
            return const SizedBox();
          }),
        );
        await tester.pumpWidget(
          _host(const Locale('tl'), 360, 1.0, (l) {
            expect(l.rptHubBadgeExports(0), 'Walang export');
            expect(l.rptHubBadgeActive('20'), '20% aktibo');
            return const SizedBox();
          }),
        );
      });
    });
  });

  group('Reports hub screen (source checks)', () {
    final src = _read('lib/presentation/screens/admin/operational_reports_screen.dart');

    test('both sections use the shared Dashboard/Marketplace card', () {
      // Detailed Reports and the Officer's two tools use the same grid; the
      // Manager's two tools (Analytics Dashboard, Export Center) use it too.
      expect(RegExp('DashboardModuleGrid\\(').allMatches(src).length, 2);
      expect(src.contains('DashboardModuleStrip'), isFalse, reason: 'the Manager tools are now the same fixed two-column grid');
      // One grid for everyone: there is no longer a separate Officer branch.
      expect(src, contains('return DashboardModuleGrid(items: items);'));
      expect(src, isNot(contains('_reportCard(')));
      expect(src, isNot(contains('_ReportCardData')));
    });

    test('every card still opens its report', () {
      for (final route in [
        'AppRoutes.salesReport',
        'AppRoutes.harvestReport',
        'AppRoutes.coopStockReport',
        'AppRoutes.loanReport',
        'AppRoutes.expenseReport',
        'AppRoutes.memberContributionReport',
        'AppRoutes.adminAnalytics',
        'AppRoutes.exportCenter',
      ]) {
        expect(src, contains('context.push($route)'), reason: route);
      }
    });

    test('Balik-Tangkilik Management is gone from the hub', () {
      expect(src, isNot(contains('balikTangkilik')));
      expect(src, isNot(contains('volunteer_activism_rounded')));
    });

    test('the Snapshot is followed by one gap, not two, when there are no '
        'insights', () {
      expect(src, contains('if (_hasInsights) ...['));
      // The gap before Quick Insights lives inside that condition.
      final cond = src.indexOf('if (_hasInsights) ...[');
      final insights = src.indexOf('_buildQuickInsights(context, l10n, cs, sagana),');
      expect(insights, greaterThan(cond));
      final before = src.substring(cond, insights);
      expect(before, contains('SizedBox(height: AppConstants.spacingSectionV)'));
    });
  });
}
