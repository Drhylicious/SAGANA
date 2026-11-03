import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/cooperative_inventory_item.dart';
import 'package:sagana/data/models/cooperative_inventory_history.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/presentation/widgets/cooperative_inventory_history.dart';
import 'support/ignore_font_errors.dart';

InventoryItem item(
  String farmer,
  double quantity, {
  String unit = 'kg',
  String name = 'Tomato',
}) => InventoryItem.fromMap({
  'id': farmer + unit,
  'item_name': name,
  'category': 'Harvest Stock',
  'unit': unit,
  'source_farmer_id': farmer,
  'source_crop_id': 'tomato-id',
  'source': farmer,
  'quantity_on_hand': quantity,
  'quantity_reserved': 0,
});

CooperativeInventoryEvent event(int n, {String action = 'harvest_received'}) =>
    CooperativeInventoryEvent.fromMap({
      'id': 'event-$n',
      'action': action,
      'occurred_at': '2026-10-29T08:45:12Z',
      'actor_name': 'Officer Ana',
      'source_farmer_name': 'Farmer JD',
      'quantity_change': action == 'harvest_received' ? 50.25 : null,
      'unit': 'kg',
      'transaction_id': 'stock-tx-$n',
      'reference_id': 'offer-$n',
      'details': {},
      if (action == 'harvest_received')
        'batch': {
          'id': 'batch-$n',
          'source_farmer_name': 'Farmer JD',
          'source_batch_number': 'BATCH-JD-001',
          'original_quantity': 50.25,
          'unit': 'kg',
          'harvest_date': '2026-10-20',
          'storage_location': 'Barn A',
          'offer_id': 'offer-$n',
          'source_transaction_id': 'sale-$n',
        },
    });

Widget host(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('both Farmer rows contribute to the 160 kg crop summary', () {
    final rows = [item('JD', 100), item('Other Farmer', 60)];
    expect(rows.map((r) => r.source).toSet(), {'JD', 'Other Farmer'});
    final totals = cooperativeCropTotals(rows);
    expect(totals.single.quantity, 160);
    expect(totals.single.unit, 'kg');
  });

  test(
    'summary uses crop identity, preserves decimals and separates units',
    () {
      final totals = cooperativeCropTotals([
        item('JD', 0.1),
        item('Other', 0.2, name: 'Renamed Tomato'),
        item('JD', 2, unit: 'sack'),
      ]);
      expect(totals.length, 2);
      expect(totals.first.quantity, 0.3);
      expect(totals.last.quantity, 2);
    },
  );

  test(
    'event preserves source, original quantity, timestamp and references',
    () {
      final e = event(1);
      expect(e.occurredAt.isUtc, true);
      expect(e.quantityChange, 50.25);
      expect(e.actorName, 'Officer Ana');
      expect(e.batch!.originalQuantity, 50.25);
      expect(e.batch!.harvestDate, DateTime(2026, 10, 20));
      expect(e.batch!.storageLocation, 'Barn A');
      expect(e.batch!.sourceTransactionId, 'sale-1');
      expect(event(2, action: 'edited').quantityChange, isNull);
    },
  );

  testWidgets('loading, failure and retry do not appear as empty history', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      final pending = Completer<List<CooperativeInventoryEvent>>();
      var attempts = 0;
      await tester.pumpWidget(
        host(
          CooperativeInventoryHistory(
            inventoryId: 'i',
            itemName: 'Tomato – JD',
            loadHistory: (_) =>
                ++attempts == 1 ? pending.future : Future.value([event(1)]),
            loadBatches: (_) async => [],
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load inventory records. Please retry.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Responsible user: Officer Ana'), findsOneWidget);
      expect(find.text('+50.25 kg'), findsOneWidget);
      expect(find.text('Storage location: Barn A'), findsOneWidget);
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'batches show immutable receipt details in a narrow Tagalog layout',
    (tester) async {
      await runIgnoringFontErrors(() async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            CooperativeInventoryHistory(
              inventoryId: 'i',
              itemName: 'Tomato – JD',
              loadHistory: (_) async => [],
              loadBatches: (_) async => [event(1).batch!],
            ),
            locale: 'tl',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mga batch ng ani'));
        await tester.pumpAndSettle();
        expect(find.text('Orihinal na dami: 50.25 kg'), findsOneWidget);
        expect(find.text('Pinagmulang Magsasaka: Farmer JD'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('a manual restock reads Manual Stock Addition, an offer receipt does not', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      final manual = CooperativeInventoryEvent.fromMap({
        'id': 'manual-1',
        'action': 'restock',
        'occurred_at': '2026-10-29T09:00:00Z',
        'actor_name': 'Officer Ana',
        'source_farmer_name': 'Farmer JD',
        'quantity_change': 5.25,
        'unit': 'kg',
        'transaction_id': 'stock-tx-manual',
        'reference_id': 'request-1',
        'reference_type': 'manual',
        'details': {'notes': 'Recount'},
        'batch': {
          'id': 'batch-manual',
          'original_quantity': 5.25,
          'unit': 'kg',
          'harvest_date': '2026-10-28',
          'storage_location': 'Barn B',
        },
      });
      expect(manual.isManualAddition, isTrue);
      expect(manual.batch!.isManualAddition, isTrue);
      expect(event(1).isManualAddition, isFalse);
      expect(event(1).batch!.isManualAddition, isFalse);

      await tester.pumpWidget(
        host(
          CooperativeInventoryHistory(
            inventoryId: 'i',
            itemName: 'Tomato – JD',
            loadHistory: (_) async => [manual, event(1)],
            loadBatches: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Title of the entry plus the label on its batch; the receipt has neither.
      expect(find.text('Manual Stock Addition'), findsNWidgets(2));
      expect(find.text('Responsible user: Officer Ana'), findsNWidgets(2));
    });
  });

  test('program pickers tell same-crop Farmer items apart', () {
    DistributionItem row(String farmerId, String? source) =>
        DistributionItem.fromMap({
          'id': 'i-${source ?? 'none'}',
          'item_name': 'Tomato',
          'category': 'Harvest Stock',
          'unit': 'kg',
          'quantity_on_hand': 10,
          'source': source,
          'source_farmer_id': farmerId.isEmpty ? null : farmerId,
        });
    expect(row('a', 'Farmer JD').displayName, 'Tomato — Farmer JD');
    expect(row('b', 'Other Farmer').displayName, 'Tomato — Other Farmer');
    // Supplies keep their plain name; their source is a supplier, not a Farmer.
    expect(row('', 'Agri Supplier Inc.').displayName, 'Tomato');
  });

  testWidgets('history beyond the first page remains reachable', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      final offsets = <int>[];
      await tester.pumpWidget(
        host(
          CooperativeInventoryHistory(
            inventoryId: 'i',
            itemName: 'Tomato – JD',
            loadHistory: (offset) async {
              offsets.add(offset);
              return offset == 0
                  ? List.generate(50, (i) => event(i, action: 'edited'))
                  : [event(50, action: 'archived')];
            },
            loadBatches: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(offsets, [0, 50]);
      expect(find.text('Item archived'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });
  });
}
