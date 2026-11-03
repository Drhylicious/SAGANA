import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/farmer_crop_model.dart';
import 'package:sagana/data/models/inventory_batch_model.dart';
import 'package:sagana/data/repositories/market_linking_repository.dart';
import 'package:sagana/presentation/widgets/crop_photo_capture.dart';
import 'package:sagana/presentation/widgets/market_linking_sale_widgets.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

/// [child] inside a localized app, so widgets that read AppLocalizations render.
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


/// A code-only view of an SQL file (comments removed).
String sqlCode(String path) =>
    read(path).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

Map<String, dynamic> cropRow({String? photo, Map<String, dynamic> extra = const {}}) => {
      'id': 'c1',
      'farmer_id': 'f1',
      'crop_name': 'Ginger',
      'category': 'Root & Spice Crop',
      'photo_url': photo,
      'created_at': '2026-10-01T00:00:00Z',
      ...extra,
    };

/// The source of one class, from its declaration to the next top-level class.
String classSource(String src, String name) {
  final start = src.indexOf('class $name ');
  expect(start, greaterThanOrEqualTo(0), reason: 'class $name');
  final next = src.indexOf('\nclass ', start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}

Map<String, dynamic> requestRow({
  String status = 'buyer_found',
  double volume = 80,
  double sold = 0,
  List<Map<String, dynamic>> sales = const [],
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': 'p1',
      'farmer_id': 'f1',
      'farmer_name': 'Juan Dela Cruz',
      'crop_name': 'Ginger',
      'season_year': 2026,
      'status': status,
      'volume_kg': volume,
      'sold_kg': sold,
      'reserved_kg': volume - sold,
      'submitted_at': '2026-10-01T00:00:00Z',
      'sales': sales,
      ...extra,
    };


Map<String, dynamic> saleRow(String buyer, double qty, double price, String day) => {
      'id': 's-$buyer',
      'buyer_name': buyer,
      'confirmed_volume_kg': qty,
      'price_per_kg': price,
      'total_amount': (qty * price * 100).round() / 100,
      'completed_at': day,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('A Farmer crop shows only the Farmer\'s own photo', () {
    test('a crop with no photo has none, even if the catalog has an image', () {
      final crop = FarmerCropModel.fromMap(cropRow(
        extra: {'catalog_image_url': 'https://example.invalid/catalog.jpg'},
      ));
      expect(crop.hasPhoto, isFalse);
      expect(crop.needsPhoto, isTrue);
      expect(crop.displayImageUrl, isNull);
      expect(crop.hasDisplayImage, isFalse);
    });

    test('a crop with its own photo shows that photo', () {
      final crop = FarmerCropModel.fromMap(cropRow(photo: 'https://example.invalid/own.jpg'));
      expect(crop.needsPhoto, isFalse);
      expect(crop.displayImageUrl, 'https://example.invalid/own.jpg');
    });

    test('an empty photo link counts as no photo', () {
      expect(FarmerCropModel.fromMap(cropRow(photo: '')).needsPhoto, isTrue);
    });

    test('an inventory batch without a photo is not ready for Marketplace/Coop/Market Linking', () {
      InventoryBatchModel batch({String? photo}) => InventoryBatchModel.fromMap({
            'id': 'b1',
            'farmer_id': 'f1',
            'harvest_record_id': 'h1',
            'crop_id': 'c1',
            'crop_name': 'Ginger',
            'batch_number': 'BATCH-GING-260730-G0001',
            'quantity_kg': 20,
            'available_kg': 20,
            'reserved_kg': 0,
            'sold_kg': 0,
            'display_image_url': photo,
            'created_at': '2026-10-01T00:00:00Z',
          });
      expect(batch().hasPhoto, isFalse);
      final after = batch().withPhoto('https://example.invalid/own.jpg');
      expect(after.hasPhoto, isTrue);
      expect(after.cropId, 'c1');
      expect(after.availableKg, 20);
    });

    test('the photo lookups never read the Crop Master image', () {
      final lookup = read('lib/data/repositories/crop_lookup.dart');
      final fn = lookup.substring(lookup.indexOf('Future<Map<String, String>> fetchFarmerCropImageMap'));
      expect(fn, isNot(contains('crop_master')));
      expect(fn, isNot(contains('image_url')));
      final repo = read('lib/data/repositories/crop_repository.dart');
      final fetch = repo.substring(repo.indexOf('Future<List<FarmerCropModel>> fetchCrops'),
          repo.indexOf('fetchCropCatalog'));
      expect(fetch, isNot(contains('image_url')));
      final tx = read('lib/data/repositories/farmer_transaction_repository.dart');
      expect(tx.substring(tx.indexOf('_loadCropImageEntries')), isNot(contains('image_url')));
    });
  });

  group('Photos are taken with the camera only', () {
    test('no gallery or file source anywhere in the crop photo flows', () {
      for (final f in [
        'lib/presentation/widgets/crop_photo_capture.dart',
        'lib/presentation/widgets/edit_crop_sheet.dart',
        'lib/presentation/widgets/crop_catalog_sheet.dart',
        'lib/presentation/screens/farmer/crop_listing_screen.dart',
        'lib/presentation/screens/farmer/manage_inventory_screen.dart',
        'lib/presentation/screens/farmer/create_listing_screen.dart',
      ]) {
        final src = read(f);
        expect(src, isNot(contains('ImageSource.gallery')), reason: f);
        expect(src, isNot(contains('Upload Photo')), reason: f);
      }
      expect(read('lib/presentation/widgets/crop_photo_capture.dart'),
          contains('ImageSource.camera'));
    });

    test('Edit Crop opens the camera directly (no source choice)', () {
      final src = read('lib/presentation/widgets/edit_crop_sheet.dart');
      expect(src, contains('captureCropPhoto(context)'));
      expect(src, isNot(contains('_PhotoSourceSheet')));
      expect(src, isNot(contains('showModalBottomSheet')));
    });

    testWidgets('the red "Photo Required" mark reads Photo Required', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: PhotoRequiredBadge())),
        ));
        expect(find.text('Photo Required'), findsOneWidget);
      });
    });

    test('the Crop Roster marks every crop that has no photo, and the mark opens the camera', () {
      final src = read('lib/presentation/screens/farmer/crop_listing_screen.dart');
      expect(src, contains('if (crop.needsPhoto)'));
      expect(src, contains('PhotoRequiredBadge()'));
    });
  });

  group('Crop requests are Crop Name, Category and Market Type only', () {
    test('the Request Crop form has no photo and the repository takes none', () {
      final form = read('lib/presentation/widgets/crop_catalog_sheet.dart');
      expect(form, isNot(contains('Photo (Optional)')));
      expect(form, isNot(contains('uploadCropRequestPhoto')));
      expect(form, isNot(contains('image_picker')));
      final repo = read('lib/data/repositories/crop_repository.dart');
      expect(repo, isNot(contains('uploadCropRequestPhoto')));
      final req = repo.substring(repo.indexOf('Future<FarmerCropModel> requestNewCrop'));
      expect(req.substring(0, req.indexOf('deleteCrop')), isNot(contains('photoUrl')));
      expect(req.substring(0, req.indexOf('deleteCrop')), isNot(contains("'photo_url'")));
    });

    test('Manager request review shows no request photo', () {
      final src = read('lib/presentation/screens/admin/crop_request_approval_screen.dart');
      expect(src, isNot(contains('photo_url')));
      expect(src, isNot(contains('photoUrl')));
    });

    test('approving a request sets no Crop Master image and copies no photo', () {
      final sql = sqlCode('supabase_schema/supabase_schema_crop_photos_selling_rules.sql');
      final fn = sql.substring(sql.indexOf('FUNCTION public.approve_crop_request'));
      expect(fn, isNot(contains('image_url')));
      expect(fn, isNot(contains('photo_url')));
      expect(fn, contains('SET crop_master_id = v_crop_master_id'));
    });
  });

  group('Selling needs the actual photo (Flutter and database)', () {
    test('Marketplace, Offer to Cooperative and Market Linking ask for it; Informal Sale does not', () {
      final inv = read('lib/presentation/screens/farmer/manage_inventory_screen.dart');
      expect(inv, contains('list this on the Marketplace'));
      expect(inv, contains('offer this to the Cooperative'));
      expect(inv, contains('submit this batch for Market Linking'));
      final informal = inv.substring(inv.indexOf('class _RecordInformalSaleDialogState'));
      expect(informal, isNot(contains('requireCropPhotoToSell')));
      expect(informal, isNot(contains('_withSellingPhoto')));
      expect(read('lib/presentation/screens/farmer/create_listing_screen.dart'),
          contains('requireCropPhotoToSell'));
    });

    test('the database refuses new listings, offers and requests without the photo', () {
      final sql = sqlCode('supabase_schema/supabase_schema_crop_photos_selling_rules.sql');
      for (final t in ['marketplace_listings', 'cooperative_purchase_offers', 'market_linking_programs']) {
        expect(sql, contains('BEFORE INSERT ON public.$t'), reason: t);
      }
      expect(sql, contains('PHOTO_REQUIRED'));
      // informal sales are deliberately not guarded
      expect(sql, isNot(contains('ON public.informal_sales')));
      // a listing always shows the Farmer's photo
      expect(sql, contains('NEW.photo_url := v_photo'));
    });

    test('the Marketplace refuses an exclusive-channel crop by configuration, not by name', () {
      final sql = sqlCode('supabase_schema/supabase_schema_crop_photos_selling_rules.sql');
      final fn = sql.substring(sql.indexOf('FUNCTION public.create_listing_with_reservation'),
          sql.indexOf('FUNCTION public.approve_crop_request'));
      expect(fn, contains('exclusive_channel'));
      expect(fn.toLowerCase(), isNot(contains('ginger')));
      expect(fn.toLowerCase(), isNot(contains('ilike')));
    });

    test('a database refusal for a missing photo reads as a sentence', () {
      expect(isPhotoRequiredError(Exception('PHOTO_REQUIRED: take a photo')), isTrue);
      expect(isPhotoRequiredError(Exception('something else')), isFalse);
    });
  });

  group('Market Linking: sold and remaining', () {
    test('80 submitted, 50 sold -> 50 sold, 30 remaining (still open)', () {
      final entry = MarketLinkingModel.fromMap(requestRow(
        sold: 50,
        sales: [saleRow('Buyer A', 50, 45.50, '2026-10-20T00:00:00Z')],
      ));
      expect(entry.isActive, isTrue);
      expect(entry.soldKg, 50);
      expect(entry.remainingKg, 30);
      expect(entry.soldValue, 2275.00);
      expect(entry.totalValue, 2275.00);
      expect(entry.hasSales, isTrue);
    });

    test('a completed request has nothing remaining and its sales add up', () {
      final entry = MarketLinkingModel.fromMap(requestRow(
        status: 'completed',
        sold: 80,
        sales: [
          saleRow('Buyer A', 50, 45.50, '2026-10-20T00:00:00Z'),
          saleRow('Buyer B', 30, 46.00, '2026-10-22T00:00:00Z'),
        ],
      ));
      expect(entry.remainingKg, 0);
      expect(entry.soldValue, 3655.00);
    });

    test('a request with no sales has no total yet', () {
      final entry = MarketLinkingModel.fromMap(requestRow(status: 'submitted'));
      expect(entry.remainingKg, 80);
      expect(entry.totalValue, isNull);
      expect(entry.hasSales, isFalse);
    });

    test('decimals stay exact (no 0.30000000000000004)', () {
      final entry = MarketLinkingModel.fromMap(requestRow(volume: 10.75, sold: 4.45));
      expect(entry.remainingKg, 6.30);
    });

    testWidgets('both screens show "Sold 50 of 80 kg" and "30 kg left to sell"', (tester) async {
      await runIgnoringFontErrors(() async {
        final entry = MarketLinkingModel.fromMap(requestRow(
          sold: 50,
          sales: [saleRow('Buyer A', 50, 45.50, '2026-10-20T00:00:00Z')],
        ));
        await tester.pumpWidget(localized(
          Column(children: [
            MarketLinkingSaleProgress(entry: entry),
            MarketLinkingSalesList(entry: entry),
          ]),
        ));
        // The quantities carry the request's unit (kg here), never a fixed "kg".
        expect(find.text('Sold 50 kg of 80 kg'), findsOneWidget);
        expect(find.text('30 kg left to sell'), findsOneWidget);
        expect(find.text('1 sale'), findsOneWidget);
        expect(find.text('₱2275.00 received'), findsOneWidget);
        // No buyer is saved on this request, so the sale names its own buyer
        // (with the date); the quantity and price are on their own line.
        expect(find.textContaining('Buyer A'), findsOneWidget);
        expect(find.text('50 kg × ₱45.50/kg'), findsOneWidget);
      });
    });

    testWidgets('the same request reads in Tagalog too', (tester) async {
      await runIgnoringFontErrors(() async {
        final entry = MarketLinkingModel.fromMap(requestRow(sold: 50));
        await tester.pumpWidget(localized(
          MarketLinkingSaleProgress(entry: entry),
          locale: const Locale('tl'),
        ));
        expect(find.text('Nabenta ang 50 kg sa 80 kg'), findsOneWidget);
        expect(find.text('30 kg na lang ang ibebenta'), findsOneWidget);
      });
    });

    testWidgets('a request closed early says what went back to stock', (tester) async {
      await runIgnoringFontErrors(() async {
        final entry = MarketLinkingModel.fromMap(requestRow(
          status: 'completed',
          sold: 50,
          sales: [saleRow('Buyer A', 50, 45.50, '2026-10-20T00:00:00Z')],
        ));
        await tester.pumpWidget(localized(MarketLinkingSaleProgress(entry: entry)));
        expect(find.text('30 kg returned to stock'), findsOneWidget);
      });
    });

    testWidgets('one plain status per request, the same words for both roles', (tester) async {
      await runIgnoringFontErrors(() async {
        Future<void> expectStatus(Map<String, dynamic> row, String label) async {
          await tester.pumpWidget(localized(
            MarketLinkingStatusChip(entry: MarketLinkingModel.fromMap(row)),
          ));
          expect(find.text(label), findsOneWidget, reason: label);
        }

        await expectStatus(requestRow(status: 'submitted'), 'Waiting for a buyer');
        await expectStatus(requestRow(status: 'buyer_found'), 'Buyer found');
        // "Completed" is the one final status, as in every selling channel.
        await expectStatus(requestRow(status: 'completed', sold: 80), 'Completed');
        await expectStatus(requestRow(status: 'completed', sold: 50), 'Completed');
        await expectStatus(requestRow(status: 'cancelled'), 'Cancelled');
        await expectStatus(
          requestRow(status: 'buyer_found', extra: {'cancellation_status': 'requested'}),
          'Cancellation Requested',
        );
      });
    });

    testWidgets('a long sales history stays compact until asked for', (tester) async {
      await runIgnoringFontErrors(() async {
        final entry = MarketLinkingModel.fromMap(requestRow(
          status: 'completed',
          sold: 80,
          sales: [
            saleRow('Buyer A', 20, 45, '2026-10-01T00:00:00Z'),
            saleRow('Buyer B', 20, 46, '2026-10-02T00:00:00Z'),
            saleRow('Buyer C', 20, 47, '2026-10-03T00:00:00Z'),
            saleRow('Buyer D', 20, 48, '2026-10-04T00:00:00Z'),
          ],
        ));
        await tester.pumpWidget(localized(MarketLinkingSalesList(entry: entry)));
        expect(find.textContaining('Buyer D'), findsOneWidget); // newest first
        expect(find.textContaining('Buyer C'), findsOneWidget);
        expect(find.textContaining('Buyer A'), findsNothing);
        expect(find.text('Show all 4 sales'), findsOneWidget);
        await tester.tap(find.text('Show all 4 sales'));
        await tester.pump();
        expect(find.textContaining('Buyer A'), findsOneWidget);
        expect(find.text('Show less'), findsOneWidget);
      });
    });

    testWidgets('the buyer shown in Buyer Details is not repeated on every sale', (tester) async {
      await runIgnoringFontErrors(() async {
        final entry = MarketLinkingModel.fromMap(requestRow(
          status: 'completed',
          sold: 70,
          sales: [
            saleRow('Buyer A', 20, 45, '2026-10-01T00:00:00Z'),
            saleRow('buyer  a ', 20, 46, '2026-10-02T00:00:00Z'), // same buyer, typed differently
            saleRow('Buyer B', 30, 47, '2026-10-03T00:00:00Z'), // a different buyer
          ],
          extra: {'buyer_name': 'Buyer A'},
        ));
        await tester.pumpWidget(localized(MarketLinkingSalesList(entry: entry)));
        // The request's own buyer is already in Buyer Details: not named again.
        expect(find.textContaining('Buyer A'), findsNothing);
        expect(find.textContaining('buyer  a'), findsNothing);
        // A sale that went to somebody else still says so.
        expect(find.textContaining('Buyer B'), findsOneWidget);
        // Every sale keeps its quantity, unit, price and date.
        expect(find.text('30 kg × ₱47.00/kg'), findsOneWidget);
        expect(find.text('20 kg × ₱46.00/kg'), findsOneWidget);
        expect(find.text('3 sales'), findsOneWidget);
      });
    });
  });

  group('Market Linking redesign: Farmer and Manager/Officer screens', () {
    test('English and Tagalog define exactly the same Market Linking strings', () {
      Set<String> keys(String lang) {
        final json = jsonDecode(read('lib/core/l10n/app_$lang.arb')) as Map<String, dynamic>;
        return json.keys.where((k) => k.startsWith('mlk')).toSet();
      }

      expect(keys('en').length, greaterThan(40));
      expect(keys('tl'), keys('en'));
    });

    test('the Farmer screen is plain: summary, In progress / Completed, no stage tracker', () {
      final src = read('lib/presentation/screens/farmer/my_market_linking_screen.dart');
      expect(src, contains('_SummaryCard'));
      expect(src, contains('l10n.mlkInProgress'));
      expect(src, contains('l10n.statCompleted'));
      expect(src, contains('MarketLinkingStatusChip'));
      for (final gone in ["'Submitted', 'Buyer Found', 'Completed'", 'Program — DA-AMAD', 'Season', 'committed', 'Buyer wants']) {
        expect(src, isNot(contains(gone)), reason: gone);
      }
    });

    test('the Manager screen has one filter row with counts and one main action per request', () {
      final src = read('lib/presentation/screens/admin/market_linking_screen.dart');
      expect(src, contains('MarketplaceFilterBar<_MlFilter>'));
      expect(src, contains('l10n.mlkActionCompleteSale'));
      expect(src, isNot(contains('_KpiStrip')));
      expect(src, isNot(contains('_stages')));
      // both screens use the same shared pieces
      for (final f in [
        'lib/presentation/screens/admin/market_linking_screen.dart',
        'lib/presentation/screens/farmer/my_market_linking_screen.dart',
      ]) {
        final s = read(f);
        for (final w in ['MarketLinkingStatusChip', 'MarketLinkingSaleProgress', 'MarketLinkingSalesList', 'MarketLinkingEntryPhoto']) {
          expect(s, contains(w), reason: '$f $w');
        }
      }
    });

    test('the new Market Linking text is localized, not hardcoded', () {
      for (final f in [
        'lib/presentation/screens/admin/market_linking_screen.dart',
        'lib/presentation/screens/farmer/my_market_linking_screen.dart',
        'lib/presentation/widgets/market_linking_sale_widgets.dart',
      ]) {
        final s = read(f);
        for (final hard in ["'Complete Sale'", "'Close Request'", "'Show all", "'Sold ", "Buyer name *", "Total sale amount"]) {
          expect(s, isNot(contains(hard)), reason: '$f hardcodes $hard');
        }
      }
    });
  });

  group('Market Linking: Manager/Officer workflow is wired to the checked functions', () {
    test('each stage is its own call; the Manager has no way to cancel', () {
      final repo = read('lib/data/repositories/market_linking_repository.dart');
      expect(repo, contains("'save_market_linking_buyer_details'"));
      expect(repo, contains("'record_market_linking_sale'"));
      expect(repo, contains("'request_market_linking_cancellation'"));
      expect(repo, contains("'respond_to_market_linking_cancellation'"));
      // no Dart path cancels or closes a request on its own
      expect(repo, isNot(contains("'close_market_linking_request'")));
      expect(repo, isNot(contains('Future<void> updateStatus')));
      expect(repo, isNot(contains('closeRequest')));
      // saving the buyer sends buyer fields only
      final save = repo.substring(repo.indexOf('Future<void> saveBuyerDetails'),
          repo.indexOf('Future<String> recordSale'));
      for (final notBuyer in ['price', 'quantity', 'batch', 'notes', 'volume']) {
        expect(save.toLowerCase(), isNot(contains("'p_$notBuyer")), reason: notBuyer);
      }
    });

    test('the Complete Sale form asks for the transaction only and shows the total', () {
      final src = read('lib/presentation/screens/admin/market_linking_screen.dart');
      final sale = classSource(src, '_CompleteSaleSheetState');
      expect(sale, isNot(contains('_buyerCtrl')));
      expect(sale, isNot(contains('_contactCtrl')));
      expect(sale, contains('l10n.mlkSaleBatchLabel'));
      expect(sale, contains('l10n.mlkSaleBuyerLabel'));
      for (final s in [
        'l10n.mlkSaleQty',
        'l10n.mlkSalePrice',
        'l10n.mlkSaleNotes',
        'l10n.mlkSaleTotal',
        'primaryLabel: l10n.mlkActionCompleteSale',
        'moneyOf(_qty!, _price!)',
        'AppToast.show',
      ]) {
        expect(src, contains(s), reason: s);
      }
      // It never creates Cooperative stock or revenue (stated to the Manager).
      final en = read('lib/core/l10n/app_en.arb');
      expect(en, contains('never becomes Cooperative stock or revenue'));
    });

    test('the Manager sees the Farmer\'s actual photo, never a catalog image', () {
      final repo = read('lib/data/repositories/market_linking_repository.dart');
      expect(repo, contains('fetchFarmerCropImageMap'));
      final shared = read('lib/presentation/widgets/market_linking_sale_widgets.dart');
      expect(shared, contains('cropPhotoUrl'));
      expect(shared, isNot(contains('crop_master')));
      expect(read('lib/presentation/screens/admin/market_linking_screen.dart'),
          contains('MarketLinkingEntryPhoto'));
    });
    test('every report reads the one sales ledger', () {
      for (final f in [
        'lib/data/repositories/admin_reports_repository.dart',
        'lib/data/repositories/farmer_transaction_repository.dart',
        'lib/data/repositories/dashboard_repository.dart',
        'lib/data/repositories/analytics_repository.dart',
      ]) {
        expect(read(f), contains(".from('market_linking_sales')"), reason: f);
      }
    });
  });

  group('Market Linking database rules', () {
    final sql = sqlCode('supabase_schema/supabase_schema_market_linking_partial_sales.sql');

    test('submitting reserves; a sale uses the reservation; closing releases the rest', () {
      expect(sql, contains('PERFORM public._apply_batch_reservation(p_inventory_batch_id, p_volume_kg)'));
      expect(sql, contains('reserved_kg, submitted_at'));
      expect(sql, contains('v_from_res := LEAST(p_quantity_kg, v_prog.reserved_kg)'));
      expect(sql, contains('FUNCTION public._ml_release_reserved'));
      expect(sql, contains('trg_market_linking_release_on_cancel'));
    });

    test('overselling and duplicate deduction are refused', () {
      expect(sql, contains('That is more than this request has left'));
      expect(sql, contains("v_prog.status NOT IN ('submitted', 'buyer_found')"));
      expect(sql, contains('FOR UPDATE'));
    });

    test('only Manager/Officer can record or close, and sales are written only by the function', () {
      expect(sql, contains('IF NOT public.is_staff()'));
      expect(sql, contains('market_linking_sales: staff read'));
      expect(sql, isNot(contains('ON public.market_linking_sales FOR INSERT')));
      expect(sql, isNot(contains('ON public.market_linking_sales FOR ALL')));
    });

    test('the sale is the Farmer\'s: recording or closing never touches Cooperative tables', () {
      final fns = sql.substring(sql.indexOf('FUNCTION public.record_market_linking_sale'),
          sql.indexOf('FUNCTION public.complete_market_linking'));
      expect(fns, isNot(contains('member_sales_transactions')));
      expect(fns, isNot(contains('cooperative_purchase_offers')));
      expect(sql, isNot(contains('INSERT INTO member_sales_transactions')));
    });


    test('the batch Sold figure reads the ledger and the total is computed by the database', () {
      expect(sql, contains('FROM market_linking_sales s'));
      expect(sql, contains('round(p_quantity_kg * p_price_per_kg, 2)'));
    });
  });
}
