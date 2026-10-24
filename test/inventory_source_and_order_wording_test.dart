import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/input_validation_utils.dart';
import 'package:sagana/data/models/buyer_order_model.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/presentation/widgets/channel_only_badge.dart';

import 'support/ignore_font_errors.dart';

BuyerOrderModel _order(String status) => BuyerOrderModel.fromMap({
  'id': 'abcdef12-0000-0000-0000-000000000000',
  'listing_id': 'l1',
  'quantity_kg': 1,
  'price_per_kg': 10,
  'total_price': 10,
  'status': status,
  'created_at': '2026-10-24T00:00:00Z',
  'updated_at': '2026-10-24T00:00:00Z',
});

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Inventory Source is required (Add and Edit Item)', () {
    test('empty and blank are refused', () {
      expect(checkInventorySource(null), InventorySourceIssue.empty);
      expect(checkInventorySource(''), InventorySourceIssue.empty);
      expect(checkInventorySource('   '), InventorySourceIssue.empty);
    });

    test('a real source is accepted, spaces around it do not count', () {
      expect(checkInventorySource('DA donation'), isNull);
      expect(checkInventorySource('  Board Resolution #102  '), isNull);
    });

    test('the 150-character limit matches the database rule', () {
      expect(kInventorySourceMaxLength, 150);
      expect(checkInventorySource('x' * 150), isNull);
      expect(checkInventorySource('x' * 151), InventorySourceIssue.tooLong);
    });
  });

  group('order wording: Pending Order / Disapproved', () {
    // The stored statuses do not change; only what people read.
    test('English', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.buyerOrdersStatusPending, 'Pending Order');
      expect(en.buyerOrderDetailStepPendingReview, 'Pending Order');
      expect(en.adminOrderStatusPendingReview, 'Pending Order');
      expect(en.orderStatusRejected, 'Disapproved');
      expect(en.buyerOrderDetailRejectedStatus, 'Disapproved');
      expect(en.buyerOrdersEmptyRejected, 'No disapproved orders.');
      expect(en.adminOrderDetailCancelTitle, 'Disapprove Order');
    });

    test('Tagalog uses the same term as the Members screens', () {
      final tl = lookupAppLocalizations(const Locale('tl'));
      expect(tl.orderStatusRejected, 'Hindi Inaprubahan');
      expect(tl.buyerOrdersStatusPending, 'Nakabinbing Order');
      expect(tl.orderStatusRejected, tl.farmerMgmtStatusRejectedLabel);
    });

    test('the model labels follow, and the stored value is untouched', () {
      expect(_order('pending').statusLabel, 'Pending Order');
      expect(_order('rejected').statusLabel, 'Disapproved');
      expect(_order('rejected').status, 'rejected');
      expect(_order('rejected').isRejected, isTrue);
    });
  });

  group('DA-AMAD indicator', () {
    setUp(
      () => MarketTypes.instance.debugSet(
        channels: const [
          SellingChannel(
            code: 'da_amad_market_linking',
            name: 'DA-AMAD Market Linking',
            requiresExclusiveCrop: true,
          ),
        ],
      ),
    );
    tearDown(() => MarketTypes.instance.debugSet());

    Widget host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('a reserved crop shows "DA-AMAD Market Linking Only"', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(const ChannelOnlyBadge(channel: 'da_amad_market_linking')),
        );
        await tester.pump();
        expect(find.text('DA-AMAD Market Linking Only'), findsOneWidget);
      });
    });

    testWidgets('an ordinary crop shows nothing', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(const ChannelOnlyBadge(channel: null)));
        await tester.pump();
        expect(find.textContaining('Only'), findsNothing);
      });
    });
  });
}
