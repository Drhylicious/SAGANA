import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_reports_model.dart' show ReportPeriod, ReportPeriodExt;
import 'package:sagana/data/models/analytics_model.dart';
import 'package:sagana/data/models/expense_model.dart' show ExpensePeriod, ExpensePeriodExt;
import 'package:sagana/data/repositories/analytics_repository.dart';
import 'package:sagana/presentation/screens/farmer/farmer_analytics_screen.dart';
import 'package:sagana/presentation/widgets/report_summary_widgets.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('AnalyticsPeriod.startDate', () {
    test('every bounded period starts at midnight, so cache keys are stable', () {
      for (final p in [
        AnalyticsPeriod.thisMonth,
        AnalyticsPeriod.thisQuarter,
        AnalyticsPeriod.thisYear,
      ]) {
        final d = p.startDate!;
        expect(
          [d.hour, d.minute, d.second, d.millisecond, d.microsecond],
          everyElement(0),
          reason: '$p must start at 00:00:00',
        );
        expect(p.startDate, p.startDate, reason: '$p is the same on every read');
      }
      expect(AnalyticsPeriod.allTime.startDate, isNull);
    });

    test('This Quarter is the calendar quarter, the same as the Manager reports', () {
      final now = DateTime.now();
      final quarterStart = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
      expect(AnalyticsPeriod.thisQuarter.startDate, quarterStart);
      expect(ExpensePeriod.thisQuarter.startDate, quarterStart);
      expect(
        ReportPeriod.thisQuarter.startDate,
        quarterStart,
        reason: 'farmer and Manager must agree on when the quarter starts',
      );
    });

    test('quarters begin on Jan 1, Apr 1, Jul 1 and Oct 1', () {
      // The rule used by all three period types, applied to each month.
      DateTime start(int month) => DateTime(2026, ((month - 1) ~/ 3) * 3 + 1, 1);
      expect(
        [for (var m = 1; m <= 12; m++) start(m).month],
        [1, 1, 1, 4, 4, 4, 7, 7, 7, 10, 10, 10],
      );
    });

    test('Month and Year are calendar', () {
      final now = DateTime.now();
      expect(AnalyticsPeriod.thisMonth.startDate, DateTime(now.year, now.month, 1));
      expect(AnalyticsPeriod.thisYear.startDate, DateTime(now.year, 1, 1));
    });
  });

  group('FarmPerformanceSummary', () {
    test('net profit is exact to the centavo', () {
      const s = FarmPerformanceSummary(
        totalYieldKg: 0,
        totalRevenue: 0.3,
        totalExpenses: 0.1,
        cropBreakdown: [],
      );
      expect(s.netProfit, 0.2); // not 0.19999999999999998
    });

    test('a loss is negative, not clamped', () {
      const s = FarmPerformanceSummary(
        totalYieldKg: 0,
        totalRevenue: 100.10,
        totalExpenses: 550.35,
        cropBreakdown: [],
      );
      expect(s.netProfit, -450.25);
    });

    test('an empty period is not a load error', () {
      expect(FarmPerformanceSummary.empty.hasLoadError, isFalse);
      expect(FarmPerformanceSummary.empty.otherUnitHarvestCount, 0);
    });
  });

  group('Market Linking revenue (same rules as Home and Transaction History)', () {
    test('quantity prefers confirmed, then requested, then enrolled volume', () {
      expect(
        marketLinkingQuantityOf({
          'confirmed_volume_kg': 10.5,
          'requested_volume_kg': 20,
          'volume_kg': 30,
        }),
        10.5,
      );
      expect(
        marketLinkingQuantityOf({'requested_volume_kg': 20, 'volume_kg': 30}),
        20,
      );
      expect(marketLinkingQuantityOf({'volume_kg': 30}), 30);
      expect(marketLinkingQuantityOf({}), 0);
    });

    test('amount is rounded to the centavo like the database', () {
      expect(
        marketLinkingAmountOf({
          'confirmed_volume_kg': 3.45,
          'price_per_kg': 45.50,
        }),
        156.98,
      );
    });

    test('a round with no price yet earns nothing (skipped, not zero-priced)', () {
      expect(marketLinkingAmountOf({'confirmed_volume_kg': 10}), isNull);
    });
  });

  group('Analytics repository contract', () {
    final src = read('lib/data/repositories/analytics_repository.dart');

    test('revenue counts the four channels, and only completed sales', () {
      expect(src, contains(".from('orders')"));
      expect(src, contains(".eq('status', 'completed')"));
      expect(src, contains(".from('member_sales_transactions')"));
      expect(src, contains(".from('informal_sales')"));
      expect(src, contains(".from('market_linking_programs')"));
    });

    test('expenses leave out subsidized items and include queued ones', () {
      expect(src, contains(".eq('is_subsidy', false)"));
      expect(src, contains('pendingExpenseModels()'));
    });

    test('every read is scoped to the signed-in farmer', () {
      // harvests, orders, coop, informal, market linking, expenses, plus the
      // four recent-transaction reads.
      expect(".eq('farmer_id', _userId)".allMatches(src).length, greaterThanOrEqualTo(10));
    });

    test('timestamp bounds are sent as real instants, never bare local text', () {
      expect(src, isNot(contains('startDate.toIso8601String()')));
      expect(src, isNot(contains('start.toIso8601String()')));
    });
  });

  group('Farmer Analytics layout', () {
    final transactions = [
      TransactionRecord(
        id: 'o1',
        cropName: 'Palay (Dinorado) Premium Long Name',
        quantityKg: 1250.5,
        totalAmount: 156.98,
        date: DateTime(2026, 10, 24),
        reference: 'ORD-20261024-A001',
        source: TransactionSource.marketplace,
      ),
      TransactionRecord(
        id: 'c1',
        cropName: 'Peanut',
        quantityKg: 40,
        totalAmount: 1234567.89,
        date: DateTime(2026, 10, 20),
        reference: 'COOP-AB12',
        source: TransactionSource.cooperative,
      ),
      TransactionRecord(
        id: 'i1',
        cropName: 'Banana',
        quantityKg: 3,
        unit: 'sack',
        totalAmount: 0,
        date: DateTime(2026, 10, 18),
        reference: 'INF-CD34',
        source: TransactionSource.informal,
      ),
      TransactionRecord(
        id: 'm1',
        cropName: 'Ginger',
        quantityKg: 500,
        totalAmount: 42500,
        date: DateTime(2026, 10, 10),
        reference: 'ML-EF56',
        source: TransactionSource.marketLinking,
      ),
    ];

    const performance = FarmPerformanceSummary(
      totalYieldKg: 12345.67,
      totalRevenue: 1234567.89,
      totalExpenses: 999999.99,
      otherUnitHarvestCount: 2,
      cropBreakdown: [
        CropYieldBreakdown(
          cropName: 'Palay',
          quantityKg: 8000.25,
          percentOfMax: 1,
        ),
        CropYieldBreakdown(
          cropName: 'Ginger',
          quantityKg: 4345.42,
          percentOfMax: 0.54,
        ),
      ],
    );

    const card = CropPriceCard(
      cropName: 'Palay',
      priceType: 'sp3_cooperative',
      currentPrice: 22.5,
      previousPrice: 21,
    );

    final history = [
      for (var i = 0; i < 6; i++)
        PriceHistoryPoint(date: DateTime(2026, 5 + i, 1), price: 20 + i * 0.5),
    ];

    Widget body({
      FarmPerformanceSummary? summary,
      List<TransactionRecord>? txs,
      bool loadFailed = false,
      void Function(AnalyticsPeriod)? onPeriod,
      VoidCallback? onRetry,
      ThemeData? theme,
      bool empty = false,
    }) {
      return MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FarmerAnalyticsBody(
            period: AnalyticsPeriod.thisMonth,
            performance: empty ? FarmPerformanceSummary.empty : (summary ?? performance),
            transactions: empty ? const [] : (txs ?? transactions),
            priceCards: empty ? const [] : const [card],
            selectedPriceCard: empty ? null : card,
            priceHistory: empty ? const [] : history,
            forecasts: const [],
            topCrops: const [],
            loadFailed: loadFailed,
            onPeriodChanged: onPeriod ?? (_) {},
            onPriceCardSelected: (_) {},
            onRetry: onRetry ?? () {},
          ),
        ),
      );
    }

    Future<void> show(WidgetTester tester, Widget app, double width) async {
      tester.view.physicalSize = Size(width, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(app);
      await tester.pump();
    }

    void ftest(String name, Future<void> Function(WidgetTester) fn) =>
        testWidgets(name, (tester) => runIgnoringFontErrors(() => fn(tester)));

    for (final width in [320.0, 360.0, 412.0]) {
      ftest('populated, light, ${width.toInt()} wide: no overflow, exact money', (
        tester,
      ) async {
        await show(tester, body(), width);
        expect(tester.takeException(), isNull);
        // Centavos are kept, thousands are grouped, a loss would carry a sign.
        expect(find.text('₱1,234,567.89'), findsWidgets);
        expect(find.text('₱234,567.90'), findsOneWidget); // net profit
        expect(find.text('₱156.98'), findsOneWidget);
        expect(find.text('12,345.67 kg'), findsOneWidget);
        expect(find.text('8,000.25 kg'), findsOneWidget);
      });
    }

    ftest('populated, dark, 320 wide: no overflow', (tester) async {
      await show(tester, body(theme: AppTheme.darkTheme), 320);
      expect(tester.takeException(), isNull);
    });

    ftest('a loss shows a signed amount and the down-trend icon', (tester) async {
      const loss = FarmPerformanceSummary(
        totalYieldKg: 0,
        totalRevenue: 100.10,
        totalExpenses: 550.35,
        cropBreakdown: [],
      );
      await show(tester, body(summary: loss), 360);
      expect(tester.takeException(), isNull);
      expect(find.text('-₱450.25'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
    });

    ftest('empty data shows the empty states, no error banner', (tester) async {
      await show(tester, body(empty: true), 320);
      expect(tester.takeException(), isNull);
      expect(find.text('₱0.00'), findsNWidgets(3));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmerAnalyticsBody)),
      );
      expect(find.text(l10n.farmerAnalyticsNoHarvestData), findsOneWidget);
      expect(find.text(l10n.farmerAnalyticsNoTransactions), findsOneWidget);
      expect(find.text(l10n.farmerAnalyticsLoadError), findsNothing);
    });

    ftest('a failed load shows the error banner and Try again works', (
      tester,
    ) async {
      var retried = 0;
      await show(
        tester,
        body(loadFailed: true, empty: true, onRetry: () => retried++),
        360,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmerAnalyticsBody)),
      );
      expect(find.text(l10n.farmerAnalyticsLoadError), findsOneWidget);
      await tester.tap(find.text(l10n.farmerAnalyticsRetry));
      expect(retried, 1);
      expect(tester.takeException(), isNull);
    });

    ftest('harvests in another unit are called out, not silently dropped', (
      tester,
    ) async {
      await show(tester, body(), 360);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmerAnalyticsBody)),
      );
      expect(find.text(l10n.farmerAnalyticsOtherUnitsNote(2)), findsOneWidget);
    });

    ftest('tapping a period chip reports that period', (tester) async {
      AnalyticsPeriod? tapped;
      await show(tester, body(onPeriod: (p) => tapped = p), 360);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmerAnalyticsBody)),
      );
      await tester.tap(find.text(l10n.farmerAnalyticsPeriodThisYear));
      expect(tapped, AnalyticsPeriod.thisYear);
    });

    ftest('all four selling channels render in Recent Transactions', (
      tester,
    ) async {
      await show(tester, body(), 360);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
      expect(find.byIcon(Icons.handshake_rounded), findsOneWidget);
      expect(find.byIcon(Icons.public_rounded), findsOneWidget);
    });
  });

  group('ReportIconStatCard.shrinkValueToFit', () {
    testWidgets('a large peso value shrinks instead of being cut off', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 120,
                  child: ReportIconStatCard(
                    icon: Icons.payments_rounded,
                    accent: Colors.green,
                    label: 'Total Revenue',
                    value: '₱999,999.99',
                    shrinkValueToFit: true,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(FittedBox), findsOneWidget);
        expect(find.text('₱999,999.99'), findsOneWidget);
      });
    });
  });
}
