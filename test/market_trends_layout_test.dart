import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/theme/sagana_colors.dart';
import 'package:sagana/data/models/price_record_model.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/presentation/screens/admin/price_management_screen.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';

import 'support/ignore_font_errors.dart';

const _public = MarketType(
  code: 'open_market',
  name: 'Public Market',
  nameTl: 'Pampublikong Market',
  buyerVisible: true,
  managerSetsPrice: false,
  sortOrder: 1,
  isActive: true,
);
const _coop = MarketType(
  code: 'sp3_cooperative',
  name: 'Cooperative Market',
  nameTl: 'Market ng Kooperatiba',
  buyerVisible: false,
  managerSetsPrice: true,
  sortOrder: 2,
  isActive: true,
);

PriceRecordModel _rec(String crop, String type, double price, int daysAgo) =>
    PriceRecordModel(
      id: '$crop$type$daysAgo',
      cropId: crop,
      cropName: 'Crop $crop',
      price: price,
      unit: 'kg',
      priceType: type,
      previousPrice: price - 1,
      recordedAt: DateTime(2026, 10, 24).subtract(Duration(days: daysAgo)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => MarketTypes.instance.debugSet(types: [_public, _coop]));
  tearDown(() => MarketTypes.instance.debugSet());

  Future<void> show(
    WidgetTester tester, {
    required Size size,
    required List<PriceRecordModel> trend,
    bool loading = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Twelve crops, two of them priced in both markets.
    final prices = [
      for (var i = 1; i <= 12; i++) _rec('$i', 'open_market', 40.0 + i, 1),
      _rec('1', 'sp3_cooperative', 55, 1),
      _rec('2', 'sp3_cooperative', 60, 1),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ManagementModalShell(
              title: 'Market Trends',
              body: MarketTrendsCard(
                prices: prices,
                trendData: trend,
                selectedCropId: '1',
                selectedMarket: null,
                loadingTrend: loading,
                onCropSelected: (_) {},
                onMarketSelected: (_) {},
                cs: Theme.of(context).colorScheme,
                sagana: context.saganaColors,
                l10n: AppLocalizations.of(context),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  final history = [
    for (var d = 20; d >= 0; d -= 2) _rec('1', 'open_market', 40 + d / 4, d),
  ];

  for (final size in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
    testWidgets('trends modal does not overflow at ${size.width.toInt()}', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await show(tester, size: size, trend: history);
        expect(find.text('Current price'.toUpperCase()), findsOneWidget);
        expect(find.text('Recent Entries'.toUpperCase()), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('a crop with one entry shows the empty state, no overflow', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await show(
        tester,
        size: const Size(320, 568),
        trend: [_rec('1', 'open_market', 41, 1)],
      );
      expect(find.text('Not enough history yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
