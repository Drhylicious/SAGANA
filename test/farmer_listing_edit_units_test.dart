import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/listing_edit_utils.dart';
import 'package:sagana/core/utils/listing_order.dart';
import 'package:sagana/core/utils/quantity_utils.dart';
import 'package:sagana/data/models/marketplace_listing_model.dart';
import 'package:sagana/data/repositories/market_linking_repository.dart';
import 'package:sagana/presentation/widgets/market_linking_sale_widgets.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

/// An SQL file without its comment lines.
String sqlCode(String path) =>
    read(path).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

Widget localized(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.lightTheme,
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

MarketplaceListingModel listing(String name, String status, {double remaining = 50, String unit = 'kg'}) =>
    MarketplaceListingModel(
      id: name,
      farmerId: 'f1',
      cropName: name,
      pricePerKg: 20,
      volumeKg: 100,
      remainingKg: remaining,
      unit: unit,
      status: status,
      createdAt: DateTime(2026, 10, 1),
    );

List<String> names(Iterable<MarketplaceListingModel> l) => l.map((e) => e.cropName).toList();

Map<String, dynamic> requestRow({
  String unit = 'kg',
  double volume = 80,
  double sold = 50,
  List<Map<String, dynamic>> sales = const [],
}) => {
  'id': 'p1',
  'farmer_id': 'f1',
  'farmer_name': 'Juan Dela Cruz',
  'crop_name': 'Ginger',
  'season_year': 2026,
  'status': 'buyer_found',
  'volume_kg': volume,
  'sold_kg': sold,
  'reserved_kg': volume - sold,
  'unit': unit,
  'submitted_at': '2026-10-01T00:00:00Z',
  'sales': sales,
};

void main() {
  group('Farmer > Listing order: live listings first, finished ones at the bottom', () {
    final arrived = [
      listing('SoldOut', 'approved', remaining: 0),
      listing('Pending', 'pending_review'),
      listing('Withdrawn', 'withdrawn', remaining: 0),
      listing('Available', 'approved'),
      listing('Disapproved', 'rejected', remaining: 0),
      listing('Sold', 'sold', remaining: 0),
      listing('Available2', 'approved', remaining: 3.25),
    ];

    test('Pending Approval and Available come first, in their arrival order', () {
      final out = names(orderForFarmerListings(arrived));
      expect(out.take(3), ['Pending', 'Available', 'Available2']);
    });

    test('Sold Out, Disapproved and Withdrawn go to the bottom, in their arrival order', () {
      final out = names(orderForFarmerListings(arrived));
      expect(out.skip(3), ['SoldOut', 'Withdrawn', 'Disapproved', 'Sold']);
    });

    test('nothing is dropped or repeated, and ordering twice changes nothing', () {
      final once = orderForFarmerListings(arrived);
      expect(once.length, arrived.length);
      expect(names(orderForFarmerListings(once)), names(once));
    });

    test('an approved listing with nothing left counts as Sold Out; with 0.25 left it is Available', () {
      expect(farmerListingGroup(listing('A', 'approved', remaining: 0)), 1);
      expect(farmerListingGroup(listing('A', 'approved', remaining: 0.25)), 0);
    });

    test('the Farmer screen applies it after the filter and the search', () {
      final src = read('lib/presentation/screens/farmer/my_listings_screen.dart');
      expect(src, contains('orderForFarmerListings('));
      expect(src, contains('_activeFilter.matches(l)'));
    });
  });

  group('Edit Listing: the checks mirror the database', () {
    ListingEditResult check({
      String qty = '6.00',
      String price = '13.75',
      String desc = 'Fresh',
      double ordered = 1.25,
      double? max = 10,
    }) => checkListingEdit(
      quantityText: qty,
      priceText: price,
      description: desc,
      orderedQuantity: ordered,
      maxQuantity: max,
    );

    test('a valid edit returns the decimals untouched', () {
      final r = check(qty: '10.25', price: '50.75', desc: '  Fresh and sweet ', max: 100);
      expect(r.isValid, isTrue);
      expect(r.quantity, 10.25);
      expect(r.price, 50.75);
      expect(r.description, 'Fresh and sweet');
    });

    test('decimal quantities and prices are accepted: 10.5, 10.25, 50.00, 50.50, 50.75', () {
      for (final q in ['10.5', '10.25', '0.45']) {
        expect(check(qty: q, ordered: 0, max: 100).isValid, isTrue, reason: q);
      }
      for (final p in ['50.00', '50.50', '50.75', '50']) {
        expect(check(price: p).isValid, isTrue, reason: p);
      }
    });

    test('a quantity must be more than what is already ordered', () {
      expect(check(qty: '1.25').problem, ListingEditProblem.quantityNotAboveOrdered);
      expect(check(qty: '1.00').problem, ListingEditProblem.quantityNotAboveOrdered);
      expect(check(qty: '1.26').isValid, isTrue);
    });

    test('nothing is ordered yet: any positive quantity within the stock is fine', () {
      expect(check(qty: '0.01', ordered: 0).isValid, isTrue);
    });

    test('a quantity above what the batch can give is refused', () {
      expect(check(qty: '10.01', max: 10).problem, ListingEditProblem.quantity);
      expect(check(qty: '10.00', max: 10).isValid, isTrue);
    });

    test('empty, zero, text and 3-decimal quantities are refused', () {
      for (final q in ['', '0', 'abc', '1.234', '-2']) {
        expect(check(qty: q).problem, ListingEditProblem.quantity, reason: q);
      }
    });

    test('empty, zero, text and 3-decimal prices are refused', () {
      for (final p in ['', '0', 'abc', '12.345']) {
        expect(check(price: p).problem, ListingEditProblem.price, reason: p);
      }
    });

    test('a blank description is refused', () {
      expect(check(desc: '   ').problem, ListingEditProblem.description);
      expect(check(desc: '').problem, ListingEditProblem.description);
    });

    test('"changed" compares in hundredths, so 12.5 and 12.50 are the same', () {
      bool changed({double q = 5, double p = 12.5, String d = 'x', bool photo = false}) =>
          listingEditChanged(
            quantity: q,
            price: p,
            description: d,
            currentQuantity: 5,
            currentPrice: 12.50,
            currentDescription: ' x ',
            newPhoto: photo,
          );
      expect(changed(), isFalse);
      expect(changed(q: 5.01), isTrue);
      expect(changed(p: 12.51), isTrue);
      expect(changed(d: 'y'), isTrue);
      expect(changed(photo: true), isTrue);
    });
  });

  group('Edit Listing: wiring', () {
    final detail = read('lib/presentation/screens/farmer/farmer_listing_detail_screen.dart');
    final edit = read('lib/presentation/screens/farmer/edit_listing_screen.dart');
    final repo = read('lib/data/repositories/listing_repository.dart');

    test('Edit is offered for Pending Approval and for Available listings, never for the others', () {
      final pending = detail.substring(detail.indexOf('if (listing.isPending)'), detail.indexOf('if (listing.isAvailable)'));
      expect(pending, contains('_openEdit'));
      expect(pending, contains('Withdraw Listing'));
      final available = detail.substring(detail.indexOf('if (listing.isAvailable)'), detail.indexOf('if (listing.isRejected)'));
      expect(available, contains('_openEdit'));
      expect(available, isNot(contains('_confirmWithdraw')), reason: 'an approved listing cannot be withdrawn');
      final rest = detail.substring(detail.indexOf('if (listing.isRejected)'));
      expect(rest, isNot(contains('_openEdit')));
    });

    test('the only write goes through the update_my_listing RPC', () {
      expect(repo, contains("'update_my_listing'"));
      expect(edit, contains('updateListing('));
      expect(edit, isNot(contains(".from('marketplace_listings')")));
    });

    test('the crop and the unit are shown, never editable', () {
      expect(edit, contains('_locked(_listing.displayName)'));
      expect(edit, contains('String get _unit => unitOrDefault(_listing.unit)'));
      expect(edit, isNot(contains('_unitController')));
    });

    test('the quantity is bounded by the listing plus what the batch still has free', () {
      expect(edit, contains('_listing.volumeKg + _batch!.availableKg'));
      expect(edit, contains('DecimalInputFormatter(max: max)'));
    });

    test('the route is registered', () {
      expect(read('lib/routes/app_routes.dart'), contains("editListing = '/farmer/marketplace/edit'"));
      expect(read('lib/presentation/navigation/app_router.dart'), contains('EditListingScreen('));
    });

    test('Listing KPIs and the Sold Out amount use the orders\' own totals, not the current price', () {
      expect(repo, contains('fetchOrderedAmounts'));
      expect(read('lib/presentation/screens/farmer/my_listings_screen.dart'), contains('_orderedAmounts[l.id]'));
      expect(detail, contains('_orderedAmount ??'));
    });

    test('English and Tagalog both have every new string', () {
      final en = read('lib/core/l10n/app_en.arb');
      final tl = read('lib/core/l10n/app_tl.arb');
      for (final k in [
        'editListingTitle', 'editListingAction', 'editListingApprovedNote', 'editListingPendingNote',
        'editListingSave', 'editListingSaved', 'editListingRetakePhoto', 'editListingQtyTooLow',
        'editListingOffline', 'editListingFailed', 'editListingNotEditable',
      ]) {
        expect(en, contains('"$k"'), reason: 'en $k');
        expect(tl, contains('"$k"'), reason: 'tl $k');
      }
    });
  });

  group('update_my_listing SQL', () {
    final sql = sqlCode('supabase_schema/supabase_schema_farmer_listing_edit.sql');

    test('only the owner, only an active Farmer, only Pending Approval or Available', () {
      expect(sql, contains("v_role IS DISTINCT FROM 'farmer'"));
      expect(sql, contains('farmer_id = v_uid'));
      expect(sql, contains("l.status NOT IN ('pending_review', 'approved')"));
      expect(sql, contains("l.status = 'approved' AND l.remaining_kg <= 0"));
    });

    test('it takes the same row lock place_order takes', () {
      expect(sql, contains('FOR UPDATE'));
    });

    test('stock moves only through the existing reservation helpers, by the difference', () {
      expect(sql, contains('_apply_batch_reservation(l.inventory_batch_id, v_delta)'));
      expect(sql, contains('_release_batch_reservation(l.inventory_batch_id, -v_delta)'));
      expect(sql, contains('remaining_kg = l.remaining_kg + v_delta'));
    });

    test('the quantity must stay above what is already ordered; decimals are checked', () {
      expect(sql, contains('v_ordered := l.volume_kg - l.remaining_kg'));
      expect(sql, contains('p_quantity <= v_ordered'));
      expect(sql, contains('round(p_quantity, 2)'));
      expect(sql, contains('round(p_price_per_kg, 2)'));
    });

    test('the crop, the unit, the batch and the status are never written', () {
      final update = sql.substring(sql.indexOf('UPDATE marketplace_listings'), sql.indexOf('WHERE id = l.id;'));
      for (final column in ['crop_name', 'crop_id', 'unit', 'inventory_batch_id', 'status', 'farmer_id']) {
        expect(update, isNot(contains('$column ')), reason: column);
      }
    });

    test('the photo can only be the crop\'s own current photo, never a client address', () {
      expect(sql, contains('farmer_crop_photo_for_batch(l.inventory_batch_id)'));
      expect(sql, isNot(contains('p_photo_url')));
    });

    test('staff are told, and nothing re-approves the listing', () {
      expect(sql, contains("'Listing Updated'"));
      expect(sql, isNot(contains("status       = 'pending_review'")));
    });

    test('withdraw_listing is untouched by this file', () {
      expect(sql, isNot(contains('withdraw_listing')));
    });

    test('anonymous callers cannot run it', () {
      expect(sql, contains('REVOKE ALL ON FUNCTION public.update_my_listing'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.update_my_listing'));
    });
  });

  group('Withdraw stays Pending Approval only', () {
    test('the database function refuses anything but pending_review', () {
      final sql = read('supabase_schema/batch0_03_missing_notices.sql');
      final fn = sql.substring(sql.indexOf('CREATE OR REPLACE FUNCTION withdraw_listing'));
      expect(fn, contains("v_listing.status != 'pending_review'"));
    });
  });

  group('Ginger / DA-AMAD follows the harvest unit', () {
    test('the harvest form no longer fixes Ginger to kg', () {
      final src = read('lib/presentation/screens/farmer/harvest_entry_form_screen.dart');
      expect(src, isNot(contains('_unitLocked')));
      expect(src, isNot(contains('measured in kg')));
      expect(src, contains('unitLocked: false'));
    });

    test('SQL: the kg-only rule is removed and the unit is copied to the request and each sale', () {
      final sql = sqlCode('supabase_schema/supabase_schema_ginger_any_unit.sql');
      expect(sql, contains('ALTER TABLE public.market_linking_programs ADD COLUMN IF NOT EXISTS unit'));
      expect(sql, contains('ALTER TABLE public.market_linking_sales    ADD COLUMN IF NOT EXISTS unit'));
      expect(sql, contains('inherit_unit_from_batch()'));
      expect(sql, contains('inherit_unit_from_program()'));
      final fn = sql.substring(sql.indexOf('FUNCTION public.prepare_harvest_record'));
      expect(fn, isNot(contains("NEW.unit <> 'kg'")));
      expect(fn, contains('Unknown unit'));
    });

    test('the Market Linking request and sale carry the unit', () {
      final request = MarketLinkingModel.fromMap(requestRow(unit: 'sack'));
      expect(request.unit, 'sack');
      expect(MarketLinkingModel.fromMap(requestRow()).unit, 'kg');
      final withoutColumn = requestRow()..remove('unit');
      expect(MarketLinkingModel.fromMap(withoutColumn).unit, 'kg', reason: 'a database without the column is kg');
    });

    testWidgets('progress reads in the request\'s unit: "Sold 12.50 sack of 80 sack"', (tester) async {
      await runIgnoringFontErrors(() async {
        final entry = MarketLinkingModel.fromMap(requestRow(unit: 'sack', sold: 12.5));
        await tester.pumpWidget(localized(MarketLinkingSaleProgress(entry: entry)));
        // A quantity with a fraction always shows 2 decimals (12.50), as everywhere.
        expect(find.text('Sold 12.50 sack of 80 sack'), findsOneWidget);
        expect(find.text('67.50 sack left to sell'), findsOneWidget);
        expect(find.textContaining('kg'), findsNothing);
      });
    });

    test('the summary adds per unit and never mixes a sack into a kilogram', () {
      final s = MarketLinkingSummary.of([
        MarketLinkingModel.fromMap(requestRow(unit: 'kg', volume: 80, sold: 50.5)),
        MarketLinkingModel.fromMap(requestRow(unit: 'sack', volume: 10, sold: 3)),
        MarketLinkingModel.fromMap(requestRow(unit: 'kg', volume: 20, sold: 0.45)),
      ]);
      expect(s.soldText, '50.95 kg + 3 sack');
      expect(s.kgSold, 50.95);
      expect(s.remainingText, '49.05 kg + 7 sack'); // 29.50 + 19.55 kg, 7 sack
    });

    test('the Manager Complete Sale form uses the request\'s unit, not a fixed kg', () {
      final src = read('lib/presentation/screens/admin/market_linking_screen.dart');
      expect(src, isNot(contains("suffixText: 'kg'")));
      expect(src, isNot(contains("unit: 'kg'")));
      expect(src, contains('unitOrDefault(e.unit)'));
    });

    test('Transaction History, the Sales Report and the analytics list read the sale\'s unit', () {
      for (final f in [
        'lib/data/repositories/farmer_transaction_repository.dart',
        'lib/data/repositories/admin_reports_repository.dart',
        'lib/data/repositories/analytics_repository.dart',
      ]) {
        expect(read(f), contains("unitOrDefault("), reason: f);
        expect(read(f), contains('unit'), reason: f);
      }
    });
  });

  group('A unit is shown wherever a price is shown', () {
    test('no price per kg is printed with a fixed "/kg" on the screens that carry a unit', () {
      for (final f in [
        'lib/presentation/screens/farmer/farmer_marketplace_tab.dart',
        'lib/presentation/screens/farmer/farmer_transaction_history_screen.dart',
        'lib/presentation/screens/admin/sales_report_screen.dart',
      ]) {
        expect(read(f), isNot(contains("}/kg'")), reason: f);
      }
    });

    test('the Offer to Cooperative activity log names the offer\'s own unit', () {
      final repo = read('lib/data/repositories/cooperative_offer_repository.dart');
      expect(repo, contains('formatQuantityUnit(kg ?? 0, unit)'));
      expect(repo, isNot(contains('(kg ?? 0).toStringAsFixed(1)')));
    });
  });

  group('Totals are never rounded to a whole number', () {
    test('formatKgTotal keeps the decimals of a total', () {
      expect(formatKgTotal(0.45), '0.45 kg');
      expect(formatKgTotal(1250), '1,250 kg');
      expect(formatKgTotal(1250.5), '1,250.50 kg');
      expect(formatKgTotal(10.75 + 0.3), '11.05 kg');
    });

    test('the report and summary screens use it instead of toStringAsFixed(0)', () {
      for (final f in [
        'lib/presentation/screens/admin/sales_report_screen.dart',
        'lib/presentation/screens/admin/harvest_report_screen.dart',
        'lib/presentation/screens/admin/operational_reports_screen.dart',
        'lib/presentation/screens/admin/admin_dashboard_screen.dart',
      ]) {
        expect(read(f), isNot(contains('toStringAsFixed(0)} kg')), reason: f);
      }
    });
  });
}
