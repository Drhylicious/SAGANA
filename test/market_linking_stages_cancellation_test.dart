import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/repositories/market_linking_repository.dart';
import 'package:sagana/presentation/widgets/market_linking_sale_widgets.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

String sqlCode(String path) =>
    read(path).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

/// The source of one class, from its declaration to the next top-level class.
String classSource(String src, String name) {
  final start = src.indexOf('class $name ');
  if (start < 0) throw StateError('class $name not found');

  final next = src.indexOf('\nclass ', start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}

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

MarketLinkingModel request({
  String status = 'submitted',
  double volume = 80,
  double sold = 0,
  Map<String, dynamic> extra = const {},
}) =>
    MarketLinkingModel.fromMap({
      'id': 'p1',
      'farmer_id': 'f1',
      'farmer_name': 'Juan Dela Cruz',
      'crop_name': 'Ginger',
      'season_year': 2026,
      'status': status,
      'volume_kg': volume,
      'sold_kg': sold,
      'submitted_at': '2026-10-01T00:00:00Z',
      ...extra,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const managerScreen = 'lib/presentation/screens/admin/market_linking_screen.dart';
  const farmerScreen = 'lib/presentation/screens/farmer/my_market_linking_screen.dart';

  group('Terminology: "Completed" and "Complete Sale"', () {
    test('no Market Linking string says "Finish"', () {
      for (final lang in ['en', 'tl']) {
        final json = jsonDecode(read('lib/core/l10n/app_$lang.arb')) as Map<String, dynamic>;
        for (final e in json.entries.where((e) => e.key.startsWith('mlk') && e.value is String)) {
          expect((e.value as String).toLowerCase(), isNot(contains('finish')), reason: '$lang ${e.key}');
        }
      }
    });

    test('the final status and the filter use the same Completed word as every channel', () {
      expect(read(managerScreen), contains('l10n.statCompleted'));
      expect(read(farmerScreen), contains('l10n.statCompleted'));
      final shared = read('lib/presentation/widgets/market_linking_sale_widgets.dart');
      expect(shared, contains('l10n.statCompleted'));
      expect(shared, isNot(contains('mlkStatusSold')));
      expect(read('lib/core/l10n/app_en.arb'), contains('"mlkActionCompleteSale": "Complete Sale"'));
    });
  });

  group('Stage 2: Buyer Details are buyer information only', () {
    final src = read(managerScreen);
    final sheet = classSource(src, '_BuyerDetailsSheetState');

    test('asks for name, contact and email only; no address, price, quantity, batch or notes', () {
      for (final f in ['_nameCtrl', '_contactCtrl', '_emailCtrl']) {
        expect(sheet, contains(f), reason: f);
      }
      for (final gone in ['_addressCtrl', 'mlkBuyerAddress', '_priceCtrl', '_qtyCtrl', '_notesCtrl', 'Batch', 'batch', 'parseDecimal']) {
        expect(sheet, isNot(contains(gone)), reason: gone);
      }
      expect(sheet, contains('l10n.mlkBuyerNameRequired'));
      expect(sheet, contains('l10n.mlkBuyerContactRequired'));
      expect(sheet, contains('l10n.mlkBuyerEmailInvalid'));
    });

    test('saving buyer details calls only the buyer-details function (no sale, no stock)', () {
      expect(sheet, contains('saveBuyerDetails('));
      expect(sheet, isNot(contains('recordSale')));
      final repo = read('lib/data/repositories/market_linking_repository.dart');
      final save = repo.substring(repo.indexOf('Future<void> saveBuyerDetails'),
          repo.indexOf('Future<String> recordSale'));
      expect(save, contains("'save_market_linking_buyer_details'"));
      expect(save, isNot(contains('record_market_linking_sale')));
      expect(save, isNot(contains('inventory_batches')));
    });

    test('Complete Sale has no buyer fields: it shows the saved buyer and the batch read-only', () {
      final sale = classSource(src, '_CompleteSaleSheetState');
      expect(sale, isNot(contains('_buyerCtrl')));
      expect(sale, contains('l10n.mlkSaleBuyerLabel'));
      expect(sale, contains('l10n.mlkSaleBatchLabel'));
      expect(sale, contains('l10n.mlkSaleReviewNote'));
    });

    test('the card offers Add Buyer Details first and Complete Sale only after a buyer is saved', () {
      final card = classSource(src, '_EntryCard');
      expect(card, contains('l10n.mlkActionAddBuyer'));
      final addAt = card.indexOf('if (isWaiting) ...[');
      final saleAt = card.indexOf('if (isBuyerFound) ...[');
      expect(addAt, greaterThan(0));
      expect(saleAt, greaterThan(addAt));
      // Complete Sale is only inside the buyer-found branch
      expect(card.substring(0, saleAt), isNot(contains('l10n.mlkActionCompleteSale')));
    });

    test('model: a request has a buyer only once the details are saved', () {
      expect(request().hasBuyer, isFalse);
      expect(request(status: 'buyer_found', extra: {'buyer_name': 'Buyer A'}).hasBuyer, isTrue);
      expect(request(extra: {'buyer_name': '  '}).hasBuyer, isFalse);
    });
  });

  group('Cancellation starts with the Farmer', () {
    final manager = read(managerScreen);
    final farmer = read(farmerScreen);

    test('the Manager/Officer screen has no cancel or close action of its own', () {
      expect(manager, isNot(contains('mlkActionCloseRequest')));
      expect(manager, isNot(contains('closeRequest')));
      expect(manager, isNot(contains('_UpdateStatusSheet')));
      expect(manager, isNot(contains('onCancel:')));
      final card = classSource(manager, '_EntryCard');
      expect(card, isNot(contains('l10n.cancel')));
      // only a review of the Farmer's request
      expect(card, contains('l10n.mlkApproveCancellation'));
      expect(card, contains('l10n.mlkDeclineCancellation'));
    });

    test('approving or declining goes through the review function; declining needs a reason', () {
      final sheet = classSource(manager, '_ReviewCancellationSheetState');
      expect(sheet, contains('respondToCancellation('));
      expect(sheet, contains('l10n.mlkDeclineReasonRequired'));
      expect(sheet, contains('!widget.approve && _reasonCtrl.text.trim().isEmpty'));
      expect(sheet, contains('AppToast.show')); // over a dialog
    });

    test('the Farmer asks with a required reason; it is sent for review, not applied', () {
      expect(farmer, contains('l10n.mlkRequestCancellation'));
      final sheet = classSource(farmer, '_CancellationRequestSheetState');
      expect(sheet, contains('l10n.mlkCancelReasonRequired'));
      expect(sheet, contains('requestCancellation('));
      expect(sheet, isNot(contains('respondToCancellation')));
      // offline is refused with a message, like the other server-only actions
      expect(farmer, contains('l10n.mlkCancelOffline'));
    });

    test('model: who may ask, and what the statuses mean', () {
      final open = request(status: 'buyer_found', sold: 50);
      expect(open.canRequestCancellation, isTrue);
      expect(request(status: 'buyer_found', extra: {'cancellation_status': 'requested'}).canRequestCancellation,
          isFalse);
      expect(request(status: 'buyer_found', extra: {'cancellation_status': 'requested'}).isCancellationRequested,
          isTrue);
      // fully sold, completed or cancelled: nothing to cancel
      expect(request(status: 'buyer_found', sold: 80).canRequestCancellation, isFalse);
      expect(request(status: 'completed', sold: 80).canRequestCancellation, isFalse);
      expect(request(status: 'cancelled').canRequestCancellation, isFalse);
      // a declined request is open again and can be asked once more
      final declined = request(extra: {
        'cancellation_status': 'rejected',
        'cancellation_review_notes': 'Buyer confirmed again',
      });
      expect(declined.wasCancellationDeclined, isTrue);
      expect(declined.canRequestCancellation, isTrue);
    });

    testWidgets('the card says Cancellation Requested, in English and Tagalog', (tester) async {
      await runIgnoringFontErrors(() async {
        final e = request(status: 'buyer_found', extra: {'cancellation_status': 'requested'});
        await tester.pumpWidget(localized(MarketLinkingStatusChip(entry: e)));
        expect(find.text('Cancellation Requested'), findsOneWidget);
        await tester.pumpWidget(localized(MarketLinkingStatusChip(entry: e), locale: const Locale('tl')));
        expect(find.text('Hiniling na Kanselahin'), findsOneWidget);
      });
    });
  });

  group('The four stages are distinct on the Manager/Officer card', () {
    testWidgets('Request -> Buyer Details -> Complete Sale -> Completed', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(MarketLinkingStageBar(entry: request())));
        for (final label in ['Request', 'Buyer Details', 'Complete Sale', 'Completed']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        // a request waiting for a buyer: the Request stage is done, nothing else
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);

        await tester.pumpWidget(localized(MarketLinkingStageBar(
          entry: request(status: 'buyer_found', extra: {'buyer_name': 'Buyer A'}),
        )));
        expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));

        await tester.pumpWidget(localized(MarketLinkingStageBar(
          entry: request(status: 'completed', sold: 80),
        )));
        expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
      });
    });

    testWidgets('the saved buyer shows name, contact and email', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(MarketLinkingBuyerBlock(
          entry: request(status: 'buyer_found', extra: {
            'buyer_name': 'Buyer A',
            'buyer_contact': '0917 000 0001',
            'buyer_email': 'buyer.a@example.com',
          }),
        )));
        for (final t in ['Buyer A', '0917 000 0001', 'buyer.a@example.com']) {

          expect(find.text(t), findsOneWidget, reason: t);
        }
        // nothing shown until the details are saved
        await tester.pumpWidget(localized(MarketLinkingBuyerBlock(entry: request())));
        expect(find.text('Buyer Details'), findsNothing);
      });
    });
  });

  group('Database: stages and cancellation', () {
    final sql = sqlCode('supabase_schema/supabase_schema_market_linking_buyer_cancellation.sql');

    test('Buyer Found needs only a buyer name; a completed request still needs its price', () {
      final guard = sql.substring(sql.indexOf('FUNCTION public.guard_market_linking_sale'),
          sql.indexOf('FUNCTION public.guard_market_linking_cancel'));
      expect(guard, contains("NEW.status = 'buyer_found'"));
      expect(guard, contains('btrim(NEW.buyer_name)'));
      final buyerBranch = guard.substring(guard.indexOf("'buyer_found'"), guard.indexOf("'completed'"));
      expect(buyerBranch, isNot(contains('price')));
      expect(buyerBranch, isNot(contains('requested_volume')));
      expect(guard, contains('price_per_kg <= 0'));
    });

    test('saving buyer details touches only buyer columns and the status; never stock or sales', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.save_market_linking_buyer_details'),
          sql.indexOf('FUNCTION public.record_market_linking_sale'));
      expect(fn, isNot(contains('inventory_batches')));
      expect(fn, isNot(contains('market_linking_sales')));
      expect(fn, isNot(contains('sold_kg')));
      expect(fn, isNot(contains('reserved_kg')));
      expect(fn, contains('IF NOT public.is_staff()'));
      expect(fn, contains("v_mail !~ '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+\$'"));
    });

    test('a sale needs saved buyer details and reads the buyer from the request', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.record_market_linking_sale'),
          sql.indexOf('FUNCTION public.complete_market_linking'));
      expect(fn, contains('Save the buyer'));
      expect(fn, isNot(contains('p_buyer_name')));
      expect(fn, contains('v_prog.buyer_name'));
      // the unsold quantity is not deducted: only the quantity sold moves
      expect(fn, contains('v_from_res := LEAST(p_quantity_kg, v_prog.reserved_kg)'));
    });

    test('nobody but an approved cancellation can cancel', () {
      expect(sql, contains('trg_market_linking_guard_cancel'));
      expect(sql, contains("current_setting('sagana.ml_cancel_ok', true)"));
      expect(sql, contains('REVOKE ALL ON FUNCTION public.close_market_linking_request(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated'));
      // the legacy completion no longer closes the rest of a request
      final wrapper = sql.substring(sql.indexOf('FUNCTION public.complete_market_linking'),
          sql.indexOf('FUNCTION public.request_market_linking_cancellation'));
      expect(wrapper, isNot(contains('close_market_linking_request')));
    });

    test('the Farmer asks with a reason, only for their own open, not-fully-sold request', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.request_market_linking_cancellation'),
          sql.indexOf('FUNCTION public.respond_to_market_linking_cancellation'));
      expect(fn, contains('farmer_id = auth.uid()'));
      expect(fn, contains('Tell us why'));
      expect(fn, contains("status NOT IN ('submitted', 'buyer_found')"));
      expect(fn, contains('v_prog.sold_kg >= v_prog.volume_kg'));
      expect(fn, contains("cancellation_status = 'requested'"));
      // asking releases nothing
      expect(fn, isNot(contains('_ml_release_reserved')));
      expect(fn, isNot(contains('close_market_linking_request')));
    });

    test('the Manager/Officer reviews it: stock is released only on approval; declining needs a reason', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.respond_to_market_linking_cancellation'));
      expect(fn, contains('IF NOT public.is_staff()'));
      expect(fn, contains('Give a reason for declining'));
      final approve = fn.substring(fn.indexOf('IF p_approve THEN'), fn.indexOf('ELSE\n    UPDATE'));
      expect(approve, contains('close_market_linking_request'));
      final decline = fn.substring(fn.indexOf('ELSE\n    UPDATE'));
      expect(decline, isNot(contains('close_market_linking_request')));
      expect(decline, isNot(contains('_ml_release_reserved')));
      // both outcomes tell the Farmer
      expect(fn, contains("'Cancellation Approved'"));
      expect(fn, contains("'Cancellation Declined'"));
    });

    test('a sale already recorded is kept when the rest is cancelled', () {
      final close = sql.substring(sql.indexOf('FUNCTION public.close_market_linking_request'),
          sql.indexOf('FUNCTION public.save_market_linking_buyer_details'));
      expect(close, contains('IF v_prog.sold_kg > 0 THEN'));
      expect(close, contains("SET status = 'completed'"));
      expect(close, isNot(contains('DELETE')));
      expect(close, isNot(contains('market_linking_sales')));
    });
  });
}
