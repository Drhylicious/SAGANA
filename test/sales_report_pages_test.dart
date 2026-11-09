import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/sales_report_screen.dart';
import 'package:sagana/presentation/widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

/// The Sales Report: Marketplace Sales and Cooperative Product Sales on two pages you swipe
/// between, each with its own overview, revenue trend, search and transactions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_sales_pages');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    await HiveService.init();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
      httpClient: fake,
    );
    await loadStandInFonts();
  });

  Future<void> open(WidgetTester tester) async {
    fake.reset();
    fake.on('GET /rest/v1/program_product_purchases', (r) {
      if (r.url.query.contains('total_amount') &&
          !r.url.query.contains('order_number')) {
        return [
          {'total_amount': 90, 'farmer_id': 'f1'},
        ];
      }
      return [
        {
          'id': 'p1',
          'order_number': 'PSO-20261108-A001',
          'farmer_id': 'f1',
          'item_name': 'Peanut Cookies',
          'program_name': 'Peanut Cookies Sale',
          'unit': 'sack',
          'quantity': 2,
          'total_amount': 90,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        },
      ];
    });
    fake.on(
      'GET /rest/v1/user_information',
      (_) => [
        {'user_id': 'f1', 'full_name': 'Maria Santos'},
      ],
    );
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SalesReportScreen()),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    // Until the data is in (the loading skeleton is gone): the real cache file is slow at times.
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(SkeletonList).evaluate().isEmpty && i > 2) break;
    }
  }

  /// Lets the page animation and the data finish (the loading skeleton never "settles").
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppLocalizations l10nOf(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold).first));

  // One walk through the screen (a single test: the real cache file does not like being reopened
  // by a second widget test in the same run).
  testWidgets(
    'opens on Marketplace Sales; swipe or tap to Cooperative Product Sales, each with its own overview, trend, search and sales',
    (tester) async {
      await runIgnoringFontErrors(() async {
        await open(tester);
        final l10n = l10nOf(tester);

        // Page 1: Marketplace Sales, with both tabs on top.
        expect(find.text(l10n.rptTabMarketplaceSales), findsOneWidget);
        expect(find.text(l10n.rptTabProductSales), findsOneWidget);
        expect(find.byKey(const Key('salesPage_marketplace')), findsOneWidget);
        expect(find.text(l10n.reportsSalesOverview), findsOneWidget);
        expect(find.text(l10n.rptSalesBySellingChannel), findsOneWidget);
        expect(find.byKey(const Key('productSalesSection')), findsNothing);

        // Swipe left: Cooperative Product Sales.
        await tester.fling(
          find.byKey(const Key('salesPages')),
          const Offset(-400, 0),
          1500,
        );
        await settle(tester);
        expect(find.byKey(const Key('productSalesSection')), findsOneWidget);
        expect(find.text(l10n.reportsRevenueTrend), findsOneWidget);
        expect(find.text(l10n.reportsTransactionDetails), findsOneWidget);
        expect(find.text('Peanut Cookies • Maria Santos'), findsOneWidget);
        expect(find.text(l10n.rptSearchProductSales), findsOneWidget);
        expect(
          find.text(l10n.rptSalesBySellingChannel),
          findsNothing,
        ); // the channels are page 1 only

        // Its own search.
        await tester.enterText(find.byType(TextField), 'nobody');
        await tester.pump();
        expect(find.text('Peanut Cookies • Maria Santos'), findsNothing);
        expect(find.text(l10n.rptNoMatches), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'peanut');
        await tester.pump();
        expect(find.text('Peanut Cookies • Maria Santos'), findsOneWidget);

        // Tap the first tab: back to Marketplace Sales, as it was.
        await tester.tap(find.byKey(const Key('salesTab_0')));
        await settle(tester);
        expect(find.text(l10n.rptSalesBySellingChannel), findsOneWidget);
        expect(find.byKey(const Key('productSalesSection')), findsNothing);

        // And the second tab goes to the product page again.
        await tester.tap(find.byKey(const Key('salesTab_1')));
        await settle(tester);
        expect(find.byKey(const Key('productSalesSection')), findsOneWidget);
      });
    },
  );
}
