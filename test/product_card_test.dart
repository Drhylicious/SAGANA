import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/quantity_utils.dart';
import 'package:sagana/data/models/buyer_listing_model.dart';
import 'package:sagana/presentation/widgets/product_card.dart';

import 'support/ignore_font_errors.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(
    WidgetTester tester,
    List<Widget> cards, {
    double width = 360,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: ProductCard.gridDelegate.mainAxisSpacing,
              crossAxisSpacing: ProductCard.gridDelegate.crossAxisSpacing,
              childAspectRatio: ProductCard.gridDelegate.childAspectRatio,
              padding: const EdgeInsets.all(20),
              children: cards,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ProductCard card({
    String name = 'Peanut Cookies',
    String price = '₱45.00/sack',
    String buyers = '1 buyer',
    String? market = 'Public Market',
    String available = '90 sack available',
    String sold = '10 sack sold',
    bool soldOut = false,
    String? badge,
  }) => ProductCard(
    name: name,
    priceText: price,
    buyersText: buyers,
    marketTypeText: market,
    availableText: available,
    soldText: sold,
    soldOut: soldOut,
    badgeLabel: badge,
    badgeColor: Colors.red,
  );

  group('ProductCard', () {
    testWidgets('shows name, price/unit, buyers, market type, available and sold', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, [card(), card(name: 'Other')]);
        expect(tester.takeException(), isNull);
        expect(find.text('Peanut Cookies'), findsOneWidget);
        expect(find.text('₱45.00/sack'), findsNWidgets(2));
        expect(find.text('1 buyer'), findsNWidgets(2));
        expect(find.text('Public Market'), findsNWidgets(2));
        expect(find.text('90 sack available'), findsNWidgets(2));
        expect(find.text('10 sack sold'), findsNWidgets(2));
      });
    });

    testWidgets('never cuts the figures off with an ellipsis, even when long', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, [
          card(
            price: '₱12,500.00/sack',
            buyers: '1,204 buyers',
            available: '12,345.50 sack available',
            sold: '9,999.25 sack sold',
          ),
          card(),
        ], width: 320);
        expect(tester.takeException(), isNull);
        // The text is present in full (scaled to fit), not shortened.
        expect(find.text('12,345.50 sack available'), findsOneWidget);
        expect(find.text('9,999.25 sack sold'), findsOneWidget);
        expect(find.text('₱12,500.00/sack'), findsOneWidget);
      });
    });

    testWidgets('lays out with a large system font and a narrow phone', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, [
          card(badge: 'Low Stock'),
          card(name: 'A very long product name that must not wrap', soldOut: true, badge: 'Sold Out'),
        ], width: 320, textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('market type and hint lines are optional (Product Sales has no market type)', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, [card(market: null)]);
        expect(tester.takeException(), isNull);
        expect(find.text('Public Market'), findsNothing);
      });
    });

    testWidgets('tapping the card calls onTap', (tester) async {
      await runIgnoringFontErrors(() async {
        var taps = 0;
        await pump(tester, [
          ProductCard(
            name: 'Tap me',
            priceText: '₱1.00/kg',
            buyersText: '0 buyers',
            availableText: '1 kg available',
            soldText: '0 kg sold',
            onTap: () => taps++,
          ),
        ]);
        await tester.tap(find.text('Tap me'));
        expect(taps, 1);
      });
    });
  });

  group('Units on the card use the existing unit helpers', () {
    test('price and quantities carry the listing\'s own unit', () {
      expect(formatPricePerUnit(45, 'sack'), '₱45.00/sack');
      expect(formatPricePerUnit(45, 'piece'), '₱45.00/piece');
      expect(formatQuantityUnit(90, 'sack'), '90 sack');
      expect(formatQuantityUnit(12.5, 'pack'), '12.50 pack');
      // A listing with no unit is kg, as every row was before units existed.
      expect(formatPricePerUnit(45, null), '₱45.00/kg');
    });
  });

  group('BuyerListingModel buyers', () {
    Map<String, dynamic> row({Object? buyers}) => {
      'id': 'l1',
      'crop_name': 'Peanut Cookies',
      'volume_kg': 100,
      'remaining_kg': 90,
      'price_per_kg': 45,
      'unit': 'sack',
      'created_at': '2026-11-05T00:00:00Z',
      'sold_kg': 10,
      if (buyers != null) 'buyers': buyers,
    };

    test('reads the buyer count', () {
      final m = BuyerListingModel.fromMap(row(buyers: 3));
      expect(m.buyers, 3);
      expect(m.unit, 'sack');
      expect(m.soldKg, 10);
    });

    test('defaults to 0 when the database does not send it yet', () {
      expect(BuyerListingModel.fromMap(row()).buyers, 0);
    });
  });

  group('Both Marketplace cards and the Product Sales card use the one ProductCard', () {
    for (final f in const [
      'lib/presentation/screens/buyer/marketplace_browse_screen.dart',
      'lib/presentation/screens/farmer/farmer_marketplace_tab.dart',
    ]) {
      test(f.split('/').last, () {
        final src = _read(f);
        expect(src, contains('ProductCard('));
        expect(src, contains('ProductCard.gridDelegate'));
      });
    }

    test('the Farmer cannot buy their own listing: UI guard and its own-listing badge are kept', () {
      final tab = _read('lib/presentation/screens/farmer/farmer_marketplace_tab.dart');
      expect(tab, contains('isOwn'));
      expect(tab, contains('farmerBrowseOwnListingBadge'));
      final details = _read('lib/presentation/screens/buyer/listing_details_screen.dart');
      expect(details, contains('_isOwnListing'));
    });

    test('workflows are unchanged: Buyer opens listingDetails, Farmer opens farmerMarketplaceListingDetail', () {
      expect(
        _read('lib/presentation/screens/buyer/marketplace_browse_screen.dart'),
        contains('AppRoutes.listingDetails'),
      );
      expect(
        _read('lib/presentation/screens/farmer/farmer_marketplace_tab.dart'),
        contains('AppRoutes.farmerMarketplaceListingDetail'),
      );
    });
  });

  group('Buyer count (database script, read from the file)', () {
    final sql = _read('supabase_schema/supabase_schema_marketplace_listing_buyers.sql');
    final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('only completed orders count, buyers are distinct people', () {
      expect(code, contains("status = 'completed'"));
      expect(code, contains('COUNT(DISTINCT buyer_id)'));
    });

    test('it adds a column to the view without changing the existing ones', () {
      expect(code, contains('SUM(quantity_kg)          AS sold_kg'));
      expect(code.indexOf('AS sold_kg'), lessThan(code.indexOf('AS buyers')));
    });

    test('it exposes a count only: no names, prices or single orders', () {
      for (final s in ['full_name', 'total_price', 'user_information']) {
        expect(code.contains(s), isFalse, reason: s);
      }
    });

    test('it changes no table or policy and does not touch place_order', () {
      for (final w in ['CREATE TABLE', 'ALTER TABLE', 'CREATE POLICY', 'DROP ', 'place_order']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });

    test('the guest function is patched in place and the script stops if it cannot', () {
      expect(code, contains('pg_get_functiondef'));
      expect(code, contains('RAISE EXCEPTION'));
    });
  });

  group('Repository keeps working before the SQL is run', () {
    test('asks for buyers, then falls back to sold_kg only', () {
      final src = _read('lib/data/repositories/buyer_marketplace_repository.dart');
      expect(src, contains("load('listing_id, sold_kg, buyers')"));
      expect(src, contains("load('listing_id, sold_kg')"));
    });
  });
}
