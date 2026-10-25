import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/price_record_model.dart';
import 'package:sagana/presentation/widgets/price_display_widgets.dart';

import 'support/ignore_font_errors.dart';

Widget _host(Widget child, {double width = 320, String locale = 'en'}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

PriceRecordModel _record(double price, int daysAgo, {String type = 'open_market'}) =>
    PriceRecordModel(
      id: 'r$daysAgo',
      cropId: 'c1',
      cropName: 'Ginger',
      price: price,
      unit: 'kg',
      priceType: type,
      recordedAt: DateTime(2026, 10, 24).subtract(Duration(days: daysAgo)),
    );

void main() {
  group('PriceTrendPanel', () {
    testWidgets('fewer than two entries: says so, draws no chart', (tester) async {
      await runIgnoringFontErrors(() async {
        final only = _record(120, 0);
        await tester.pumpWidget(
          _host(PriceTrendPanel(trend: [only], isLoading: false, current: only)),
        );

        expect(find.text('Not enough history for a trend chart yet'), findsOneWidget);
        // No date range under a chart that is not drawn.
        expect(find.textContaining('Oct 2'), findsNothing);
      });
    });

    testWidgets('no history: High / Low / Current still shown by default', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final only = _record(120, 0);
        await tester.pumpWidget(
          _host(PriceTrendPanel(trend: const [], isLoading: false, current: only)),
        );

        expect(find.text('High'), findsOneWidget);
        expect(find.text('Low'), findsOneWidget);
        expect(find.text('Current'), findsOneWidget);
      });
    });

    testWidgets('no history + showStatsWithoutHistory:false repeats nothing', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final only = _record(120, 0);
        await tester.pumpWidget(
          _host(
            PriceTrendPanel(
              trend: const [],
              isLoading: false,
              current: only,
              showAverage: true,
              showStatsWithoutHistory: false,
            ),
          ),
        );

        expect(find.text('High'), findsNothing);
        expect(find.text('Average'), findsNothing);
        expect(find.text('Not enough history for a trend chart yet'), findsOneWidget);
      });
    });

    testWidgets('with history: chart, first/last dates and correct figures', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final trend = [
          _record(100, 20),
          _record(130, 10),
          _record(110, 0),
        ];
        await tester.pumpWidget(
          _host(PriceTrendPanel(trend: trend, isLoading: false, current: trend.last)),
        );

        expect(find.text('Not enough history for a trend chart yet'), findsNothing);
        expect(find.text('Oct 4, 2026'), findsOneWidget); // first entry
        expect(find.text('Oct 24, 2026'), findsOneWidget); // last entry
        expect(find.text('₱130.00'), findsOneWidget); // High
        expect(find.text('₱100.00'), findsOneWidget); // Low
        expect(find.text('₱110.00/kg'), findsOneWidget); // Current
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('showAverage replaces Current with the mean of the entries', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final trend = [_record(100, 20), _record(130, 10), _record(110, 0)];
        await tester.pumpWidget(
          _host(
            PriceTrendPanel(
              trend: trend,
              isLoading: false,
              current: trend.last,
              showAverage: true,
            ),
          ),
        );

        expect(find.text('Current'), findsNothing);
        expect(find.text('Average'), findsOneWidget);
        expect(find.text('₱113.33'), findsOneWidget);
      });
    });

    testWidgets('loading shows a placeholder, not a verdict', (tester) async {
      await runIgnoringFontErrors(() async {
        final only = _record(120, 0);
        await tester.pumpWidget(
          _host(PriceTrendPanel(trend: const [], isLoading: true, current: only)),
        );

        expect(find.text('Not enough history for a trend chart yet'), findsNothing);
        expect(find.text('High'), findsNothing);
      });
    });

    testWidgets('fits a 320px phone in Tagalog without overflow', (tester) async {
      await runIgnoringFontErrors(() async {
        final trend = [_record(100, 20), _record(130, 10), _record(110, 0)];
        await tester.pumpWidget(
          _host(
            PriceTrendPanel(trend: trend, isLoading: false, current: trend.last),
            locale: 'tl',
          ),
        );

        expect(tester.takeException(), isNull);
      });
    });
  });

  group('groupPricesByCategory', () {
    test('categories alphabetical, uncategorised last under the given label', () {
      final groups = groupPricesByCategory<String?>(
        ['Rice', null, 'Fruit', '  ', 'Fruit2'],
        (c) => c,
        'Other',
      );
      expect(groups.map((g) => g.key), ['Fruit', 'Fruit2', 'Rice', 'Other']);
      expect(groups.last.value, [null, '  ']);
    });
  });

  group('Farmer Market Rates source contract', () {
    String read(String path) => File(path).readAsStringSync();

    test('the trend is read for the SELECTED market only', () {
      final repo = read('lib/data/repositories/farmer_market_rates_repository.dart');
      expect(repo, contains('priceType: marketType'));

      final price = read('lib/data/repositories/price_management_repository.dart');
      // Both the 30-day read and the older-entries fallback narrow by market.
      expect(
        RegExp(r"eq\('price_type', priceType\)").allMatches(price).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('Buyer and Farmer both use the shared trend panel', () {
      final buyer = read('lib/presentation/screens/buyer/price_monitoring_screen.dart');
      final details = read('lib/presentation/screens/farmer/market_rate_details_screen.dart');
      expect(buyer, contains('PriceTrendPanel('));
      expect(details, contains('PriceTrendPanel('));
      // Buyer asks for its card's market too.
      expect(buyer, contains('priceType: priceType'));
    });

    test('market chips are one horizontally scrolling row', () {
      final list = read('lib/presentation/screens/farmer/view_market_screen.dart');
      expect(list, contains('scrollDirection: Axis.horizontal'));
      expect(list, isNot(contains('Wrap(')));
    });

    test('Buyer Prices still filters out markets a Buyer cannot see', () {
      final buyer = read('lib/presentation/screens/buyer/price_monitoring_screen.dart');
      expect(buyer, contains('MarketTypes.instance.isBuyerVisible'));
    });
  });
}
